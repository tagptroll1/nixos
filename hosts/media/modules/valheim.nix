# Valheim dedicated server (1.0 / Deep North), installed natively by steamcmd.
# There is no `services.valheim` NixOS module and no valheim package in
# nixpkgs, so the shipped binary runs under steam-run, same as zomboid.
#
# External requirements, none of which this file can create:
#
#   sops — hosts/media/secrets/valheimSecret.yaml must exist and hold the key
#     server_pw, at least 5 characters (the server refuses shorter ones) and
#     not a substring of serverName or worldName below (it refuses that too).
#     The secret is wired up in hosts/media/default.nix. Create it before the
#     first rebuild:
#       nix shell nixpkgs#sops -c sops hosts/media/secrets/valheimSecret.yaml
#
#   First install — nothing downloads the 2 GB of game files on a rebuild, so
#     after the first switch run:
#       sudo systemctl start valheim-update.service
#     Every night after that the restart job below updates before it starts.
#
#   Pangolin — the public path is a raw UDP resource, same as factorio's 34197:
#     traefik on the pangolin VPS listens on the udp-2456 entrypoint (declared
#     in hosts/pangolin/modules/pangolin.nix as rawUdpPorts) and forwards over
#     the newt tunnel to this host. The resource itself, 2456 → the media site
#     at 10.2.10.10:2456, lives in the Pangolin dashboard/db and has to be
#     created there by hand.
#
#     Only the game port is tunnelled. The steam query port would need
#     -public 1 to answer at all, and the join path clients use here is the
#     address, not a browser listing.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # The steam install lives on the games share (see storage.nix), same as
  # cs2/factorio/zomboid. HOME points at valheimRoot so steamcmd keeps its own
  # state (~/.local/share/Steam) inside it.
  valheimRoot = "/mnt/games/valheim";
  valheimServer = "${valheimRoot}/server"; # steamcmd force_install_dir

  # -savedir. Holds worlds_local/ (the live world and the automatic backups)
  # plus adminlist.txt, bannedlist.txt and permittedlist.txt.
  #
  # On the VM's local disk, not the games share, for the same reason as
  # zomboid: /mnt/games is virtiofs onto the host's ZFS pool and fsyncs there
  # cost ~10 ms against ~0.8 ms here. Valheim serialises the whole world and
  # writes it out on every autosave, and every player feels that as a hitch, so
  # the write wants the fast disk.
  valheimData = "/var/lib/valheim";

  # Nothing on the VM's local disk is backed up — the off-site job only covers
  # the host's ZFS datasets. So the server's own backup sets are copied here,
  # onto the games share, by valheim-backup-sync below. Writes here are never
  # on the save path, so their latency does not matter.
  valheimBackups = "${valheimRoot}/backups";

  # How many backup sets to keep on the share. Roughly ten days at the vanilla
  # 2h-then-12h cadence below.
  backupsKept = 20;

  # Shows in the community browser and is what -password may not be part of.
  serverName = "Yesbutmaybeno";

  # Creates <valheimData>/worlds_local/<worldName> on first start, and loads it
  # every start after. Renaming this starts a brand new world.
  worldName = "ybmn";

  # Base port. The server also binds port+1 (2457) for the Steam query socket.
  port = 2456;

  # Steam app id of the Valheim Dedicated Server (free, anonymous login).
  appId = "896660";

  # The game's own app id. The server has to register with steam under it, not
  # under the dedicated server tool's id — upstream's start_server.sh exports
  # exactly this.
  gameAppId = "892970";

  # Public branch — 1.0 is the default branch since 2026-09-09, so no -beta
  # flag. `validate` is left off: it rehashes the whole install, which is only
  # worth it to repair a broken one, by hand:
  #   steamcmd +force_install_dir <dir> +login anonymous \
  #     +app_update 896660 validate +quit
  updateCmd = "${pkgs.steamcmd}/bin/steamcmd +force_install_dir ${valheimServer} +login anonymous +app_update ${appId} +quit";

  # Steam writes the installed build id here on every app_update, so it is the
  # only record of which build the files on disk are.
  appManifest = "${valheimServer}/steamapps/appmanifest_${appId}.acf";

  # Upstream's start_server.sh hardcodes its own -name/-world/-password and
  # never forwards "$@", so the binary is invoked directly. The two exports are
  # the parts of that script that matter: the bundled steam libraries sit in
  # linux64/, and the server reads SteamAppId to know which app it is.
  #
  # -password on the command line is visible in /proc/<pid>/cmdline, which is
  # world readable, and in `systemctl status`. Valheim takes the join password
  # no other way — there is no stdin prompt, config file or environment
  # variable for it — so this is the price of having one at all. It is a join
  # password, not an admin credential: admin rights come from steam ids listed
  # in <valheimData>/adminlist.txt.
  startScript = pkgs.writeShellScript "valheim-start" ''
    set -eu
    export LD_LIBRARY_PATH="${valheimServer}/linux64:''${LD_LIBRARY_PATH:-}"
    export SteamAppId=${gameAppId}

    # exec so systemd's SIGINT lands on the server and not on this shell.
    exec ${valheimServer}/valheim_server.x86_64 \
      -name "${serverName}" \
      -world "${worldName}" \
      -port ${toString port} \
      -savedir "${valheimData}" \
      -password "$VALHEIM_SERVER_PASSWORD" \
      -public 0 \
      -saveinterval 1800 \
      -backups 4 \
      -backupshort 7200 \
      -backuplong 43200
  '';

  # Valheim has no -backupdir: 1.0 writes each backup set as its own directory
  # <world>_backup_auto-<timestamp> right beside the live world inside
  # worlds_local, so getting them onto the share means copying them out.
  #
  # Copy rather than move, so the server's own -backups retention keeps working
  # on the local copies and a restore from the last few hours needs no trip to
  # the share. That does make retention here ours to do, at the bottom.
  backupSyncScript = pkgs.writeShellScript "valheim-backup-sync" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
      ]
    }

    src=${valheimData}/worlds_local

    # Nothing to do before the world exists.
    [ -d "$src" ] || exit 0

    # A backup set is never written to again once it is complete, so -mmin +5
    # is all it takes to stay clear of one being created right now. -n skips
    # what is already here, and -a copies either shape: 1.0's directory or the
    # .db/.fwl file pair older builds wrote.
    find "$src" -mindepth 1 -maxdepth 1 -name '${worldName}_backup_auto-*' -mmin +5 \
      -exec cp -a -n -t ${valheimBackups} {} +

    # The timestamps are yyyymmdd-hhmmss, so sorting the names by text sorts
    # them by age. Everything past the newest ${toString backupsKept} goes.
    find ${valheimBackups} -mindepth 1 -maxdepth 1 -name '${worldName}_backup_auto-*' -printf '%f\n' \
      | sort -r \
      | tail -n +${toString (backupsKept + 1)} \
      | while read -r old; do
          rm -rf ${valheimBackups}/"$old"
        done
  '';

  # Nightly cycle. Valheim ships no RCON, no console socket and no in-game
  # message command, so there is no way to warn players first and no way to ask
  # whether anyone is connected — the restart is simply scheduled for an hour
  # nobody plays.
  #
  # The update check lives here rather than in its own timer because steamcmd
  # writes over the running server's files: fetching a build at any other time
  # would leave a half-swapped install serving players until the next restart.
  # Stopping first, updating, then starting is the whole of it.
  restartScript = pkgs.writeShellScript "valheim-restart" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
        config.systemd.package
      ]
    }

    installedBuild() {
      [ -e ${appManifest} ] || return 0
      sed -E -n 's/^[[:space:]]*"buildid"[[:space:]]+"([0-9]+)".*/\1/p' ${appManifest}
    }

    before=$(installedBuild)

    # KillSignal=SIGINT below: the world is written to disk before the process
    # exits. TimeoutStopSec bounds how long that may take.
    systemctl stop valheim.service

    # Blocks until the oneshot finishes, however long steam takes.
    systemctl start valheim-update.service

    after=$(installedBuild)
    if [ -n "$before" ] && [ "$before" != "$after" ]; then
      echo "valheim updated: build $before -> $after"
    fi

    systemctl start valheim.service
  '';
in
{
  options.myServices.valheim.enable = lib.mkEnableOption "the Valheim dedicated server";

  config = lib.mkIf config.myServices.valheim.enable {
    systemd.tmpfiles.settings."10-valheim" = {
      "${valheimRoot}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${valheimServer}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${valheimBackups}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${valheimData}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      # The server creates this itself on first start; pre-creating it is what
      # lets valheim-backup-sync run before anyone has ever played.
      "${valheimData}/worlds_local".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      # Where the steamworks game server library looks for steamclient.so.
      # Without it the server falls back to the copy in its install directory
      # and only half initialises steam.
      # Declared explicitly, not left to be created as a parent of sdk64:
      # tmpfiles makes missing parents root-owned, and then refuses to descend
      # from a games-owned directory into a root-owned one ("unsafe path
      # transition"), which drops the sdk64 rule and the symlink below with it.
      # steamcmd also puts its own .steam/root symlink here and runs as games.
      "${valheimRoot}/.steam".d = {
        user = "games";
        group = "games";
        mode = "0750";
      };
      "${valheimRoot}/.steam/sdk64".d = {
        user = "games";
        group = "games";
        mode = "0750";
      };
      "${valheimRoot}/.steam/sdk64/steamclient.so"."L+".argument =
        "${valheimServer}/linux64/steamclient.so";
    };

    # Join password, out of the nix store.
    sops.templates."valheim.env" = {
      owner = "games";
      content = ''
        VALHEIM_SERVER_PASSWORD=${config.sops.placeholder."valheim/server_pw"}
      '';
    };

    systemd.services.valheim = {
      description = "Valheim dedicated server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "mnt-games.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "mnt-games.mount" ];

      environment.HOME = valheimRoot;

      serviceConfig = {
        User = "games";
        Group = "games";
        WorkingDirectory = valheimServer;
        EnvironmentFile = config.sops.templates."valheim.env".path;

        # Nothing to start before the game files exist. A failing ExecCondition
        # leaves the unit inactive instead of triggering Restart=, so an empty
        # install waits for valheim-update rather than looping every 30s.
        ExecCondition = "${pkgs.coreutils}/bin/test -x ${valheimServer}/valheim_server.x86_64";

        # The shipped binary and its bundled steam libraries are plain FHS
        # objects — steam-run supplies the loader and libraries they expect.
        ExecStart = "${pkgs.steam-run}/bin/steam-run ${startScript}";

        # The server only writes the world out on SIGINT. SIGTERM, systemd's
        # default, terminates it where it stands and loses everything since the
        # last autosave.
        KillSignal = "SIGINT";
        TimeoutStopSec = 120;

        # A ceiling, not a tuning knob — it makes a runaway kill one unit
        # instead of hanging the whole VM, which this host has had happen.
        # Restart=always brings it back.
        MemoryMax = "6G";

        Restart = "always";
        RestartSec = 30;
      };
    };

    # Downloading the game is not part of starting it: as an ExecStartPre it
    # would make every `systemctl start` and every nixos-rebuild block until
    # steam is done. Kept in its own unit, the server starts in seconds and
    # updates are a job that runs, and can be watched, on its own.
    systemd.services.valheim-update = {
      description = "Install or update the Valheim dedicated server from Steam";
      after = [
        "network-online.target"
        "mnt-games.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "mnt-games.mount" ];

      environment = {
        HOME = valheimRoot;
        SteamAppId = appId;
      };

      serviceConfig = {
        Type = "oneshot";
        User = "games";
        Group = "games";
        WorkingDirectory = valheimServer;
        ExecStart = updateCmd;
        # The first run downloads the whole game; steam sets no pace for it.
        TimeoutStartSec = "infinity";
      };
    };

    systemd.services.valheim-backup-sync = {
      description = "Copy Valheim's automatic backups off the local disk onto the games share";
      after = [ "mnt-games.mount" ];
      requires = [ "mnt-games.mount" ];

      serviceConfig = {
        Type = "oneshot";
        User = "games";
        Group = "games";
        ExecStart = backupSyncScript;
      };
    };

    systemd.timers.valheim-backup-sync = {
      description = "Half-hourly sweep of Valheim's automatic backups onto the games share";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:00/30";
        # Catch up after a boot: the sweep is what puts the backups somewhere
        # that survives this VM.
        Persistent = true;
      };
    };

    systemd.services.valheim-restart = {
      description = "Nightly Valheim restart, updating the server first if steam has a new build";
      serviceConfig = {
        Type = "oneshot";
        # Root: it drives valheim.service and valheim-update.service, which run
        # as games themselves.
        ExecCondition = "${config.systemd.package}/bin/systemctl --quiet is-active valheim.service";
        ExecStart = restartScript;
        # Bounded by the download, which steam sets no pace for.
        TimeoutStartSec = "infinity";
      };
    };

    systemd.timers.valheim-restart = {
      description = "Nightly Valheim restart and update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Clear of zomboid's 04:45 update and 05:00 restart, so two steamcmd
        # downloads never run at once.
        OnCalendar = "05:30";
        Persistent = false;
      };
    };

    # Game traffic, UDP only. This covers LAN and Tailscale clients directly,
    # and public clients arriving out of the newt tunnel, which newt delivers
    # to this host's own address rather than to loopback.
    #
    # port + 1 is the steam query socket. The server only binds it under
    # -public 1, so today nothing answers there; it is opened so flipping that
    # flag is a one-line change.
    networking.firewall.allowedUDPPorts = [
      port
      (port + 1)
    ];
  };
}
