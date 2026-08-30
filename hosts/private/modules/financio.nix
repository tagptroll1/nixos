{ config, pkgs, ... }:
let
  # The binary is built by CI on this host (see forgejo-runner.nix) and
  # installed under releases/<commit>/financio, with `current` pointing at the
  # release that should be running. It is deliberately not a nix package: the
  # frontend is a pnpm build and the Go build is cgo, and the user chose a
  # runner-built artifact over carrying two content hashes in this repo.
  #
  # The trade-off is written down here because it is not the usual one on this
  # host: a NixOS generation rollback does NOT roll the application back. To
  # undo a bad deploy, point `current` at the previous release and restart:
  #
  #   ln -sfn <sha> /var/lib/financio-releases/current.tmp
  #   mv -T /var/lib/financio-releases/current.tmp /var/lib/financio-releases/current
  #   systemctl restart financio
  releases = "/var/lib/financio-releases";
  binary = "${releases}/current/financio";

  # The ledger, its snapshots, the raw bank payloads and the parsed PDF
  # statements. DATA_DIR roots all four, so the unit's working directory can
  # never decide which database is opened.
  stateDir = "/var/lib/financio";

  # Operational config that can change without a rebuild. financio is not a
  # container so it is not in `my.apps`, but it follows the same convention -
  # modules/apps.nix owns the directory, this file owns the one file in it.
  # Read last, so a value here beats `environment` below. That is the point,
  # and also the footgun: setting PORT here without moving the Caddy upstream
  # in networking.nix takes the site down.
  envFile = "/var/lib/appenv/financio.env";

  # 8080 is taken on this host by the hello container and is open in the
  # firewall for it. financio only binds loopback so they would not actually
  # collide, but sharing a number between a demo container and the ledger is
  # asking for the wrong one to be debugged.
  port = 8086;

  environment = {
    DATA_DIR = stateDir;
    PORT = toString port;
    BIND_ADDR = "127.0.0.1";
    # The bank redirects the browser to <PUBLIC_URL>/api/auth/callback after
    # consent, so this has to be what the user actually reaches it through.
    PUBLIC_URL = "https://bank.ybmn.no";
    RECEIPT_OCR_URL = "http://10.2.10.10:8099";
  };

  # Shared by the server and the nightly sync: same user, same state, same
  # secrets. pdftotext is a hard runtime dependency of statement import - the
  # upload returns 503 without it - and the debit/credit split depends on its
  # -bbox-layout x-coordinates, so re-parse a known statement after a nixpkgs
  # bump that moves poppler.
  common = {
    inherit environment;

    path = [ pkgs.poppler-utils ];

    serviceConfig = {
      User = "financio";
      Group = "financio";

      WorkingDirectory = stateDir;

      # systemd reads these in order and the later one wins, so the
      # mutable file can override anything above it. The `-` prefix keeps
      # a missing file non-fatal: tmpfiles creates it, but the unit must
      # not depend on that having happened first.
      EnvironmentFile = [
        config.sops.secrets."financio/env".path
        "-${envFile}"
      ];

      # Not DynamicUser: three units share one state directory, and the
      # ledger has to survive them all.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ stateDir ];
    };
  };
in
{
  users.users.financio = {
    isSystemUser = true;
    group = "financio";
  };
  users.groups.financio = { };

  systemd.tmpfiles.rules = [
    # 0700: the ledger is every transaction ever synced, plus the account
    # holder's name and IBANs.
    "d ${stateDir} 0700 financio financio - -"

    # CI writes here and financio reads it, so it is traversable rather than
    # private. Nothing secret lives in it - it holds built binaries.
    "d ${releases} 0755 forgejo-runner forgejo-runner - -"

    # `f` creates it empty when missing and never touches it again, so a
    # rebuild cannot clobber an edit.
    "f ${envFile} 0640 root root - -"
  ];

  systemd.services.financio = common // {
    description = "financio - Nordea ledger";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = common.serviceConfig // {
      ExecStart = "${binary} serve";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.financio-sync = common // {
    description = "financio nightly sync";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = common.serviceConfig // {
      Type = "oneshot";
      ExecStart = "${binary} sync";
    };
  };

  systemd.timers.financio-sync = {
    description = "financio nightly sync";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      # The bank allows four calls per account per day on a rolling 24h
      # window, shared with the UI. 03:00 spends one while nobody is using
      # it, and leaves the whole day's remainder to the user. A spent
      # allowance exits 0 on purpose, so a failed unit here is a real
      # fault worth looking at.
      OnCalendar = "03:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  # Editing the env file restarts the server. PathChanged rather than
  # PathModified because `sudo -e` and vim write a new file and rename it over
  # the old one, which is a change of the path rather than a write to the
  # inode. The nightly sync is a oneshot and picks up the new value on its own
  # next run, so it needs no watcher.
  systemd.paths.financio-env = {
    description = "financio env watcher";
    wantedBy = [ "multi-user.target" ];

    pathConfig.PathChanged = envFile;
  };

  systemd.services.financio-env = {
    description = "restart financio after an env change";

    path = [ pkgs.systemd ];

    serviceConfig.Type = "oneshot";

    script = ''
      			echo "restarting financio after an env change"
      			systemctl restart financio.service
      		'';
  };

  # CI touches releases/.stamp as the last step of a green build. Watching a
  # file it writes means the runner needs no sudo, no root unit to call and no
  # credential that executes anything - it can only put a binary in place and
  # say so.
  systemd.paths.financio-deploy = {
    description = "financio release watcher";
    wantedBy = [ "multi-user.target" ];

    pathConfig.PathModified = "${releases}/.stamp";
  };

  systemd.services.financio-deploy = {
    description = "financio deploy";

    path = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.systemd
    ];

    serviceConfig.Type = "oneshot";

    script = ''
      			set -euo pipefail

      			rev=$(readlink ${releases}/current || true)
      			if [ -z "$rev" ]; then
      				echo "no current release to deploy" >&2
      				exit 1
      			fi

      			# Logged on every deploy so `journalctl -u financio-deploy` answers
      			# "what is running and where did it come from" without a git
      			# archaeology session.
      			echo "deploying financio $rev"

      			# A binary that will not start leaves the unit failed and the old
      			# release still on disk, which is what makes the symlink rollback in
      			# this file's header work.
      			systemctl restart financio.service

      			# Keep the five most recent releases. Older ones are only useful
      			# as a rollback target, and a rollback that far back is a rebuild.
      			# -type d does not follow symlinks, so `current` is never a
      			# candidate; the release it points at is skipped explicitly.
      			cd ${releases}
      			find . -maxdepth 1 -mindepth 1 -type d -printf '%T@ %P\n' \
      				| sort -rn | tail -n +6 | while read -r _ old; do
      				if [ "$old" = "$rev" ]; then continue; fi
      				echo "pruning $old"
      				rm -rf -- "$old"
      			done
      		'';
  };
}
