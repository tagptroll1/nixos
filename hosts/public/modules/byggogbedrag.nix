{ pkgs, config, ... }:

let
  appDir  = "/var/lib/byggogbedrag";
  appPort = 3001;

  buildEnv = {
    NODE_ENV = "production";
    HOME     = appDir;
  };

  serveEnv = {
    NODE_ENV = "production";
    # mail.yesbutmaybe.no has no proper AAAA — IPv6 lookup falls through to the
    # *.yesbutmaybe.no wildcard (the VPS), which serves a self-signed cert on 587.
    # IPv4 resolves to the local mailserver with the valid LE cert. Force v4.
    NODE_OPTIONS = "--dns-result-order=ipv4first";
    HOST     = "0.0.0.0";
    PORT     = toString appPort;
    ORIGIN   = "https://byggogbedrag.no";
    HOME     = appDir;
    # SMTP — mailserver on this host. 587 = STARTTLS. SMTP_PASS via sops below.
    SMTP_HOST = "mail.yesbutmaybe.no";
    SMTP_PORT = "587";
    SMTP_USER = "post@byggogbedrag.no";
  };
in
{
  # ── Mailserver name → loopback ───────────────────────────────────────────────
  # Public DNS for mail.yesbutmaybe.no has no usable A/AAAA for this host; lookups
  # fall through the *.yesbutmaybe.no wildcard to the VPS, which serves a
  # self-signed cert on 587. The mailserver is local — pin the name to loopback so
  # the app reaches local postfix and validates the real LE cert (CN matches).
  networking.hosts."127.0.0.1" = [ "mail.yesbutmaybe.no" ];

  # ── Build — fetch + compile into appDir. Runs while the old server keeps ──────
  #    serving, so a rebuild never takes the site offline. Inactive once done, so
  #    a plain `nixos-rebuild switch` does NOT re-trigger it.
  systemd.services."byggogbedrag-build" = {
    description = "Build byggogbedrag.no";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];   # build once at boot
    before      = [ "byggogbedrag.service" ];

    path = with pkgs; [ git nodejs pnpm coreutils bash ];

    environment = buildEnv;

    serviceConfig = {
      Type             = "oneshot";
      User             = "byggogbedrag";
      Group            = "byggogbedrag";
      WorkingDirectory = appDir;
      TimeoutStartSec  = "300";
      ProtectSystem    = "full";
      ReadWritePaths   = [ appDir ];
      EnvironmentFile  = [ config.sops.secrets."github_token".path ];
      ExecStart = pkgs.writeShellScript "byggogbedrag-build" ''
        set -e
        if [ ! -d ${appDir}/.git ]; then
          git clone https://github.com/tagptroll1/byggogbedrag.git ${appDir}
        else
          git -C ${appDir} fetch origin
          git -C ${appDir} reset --hard origin/main
        fi
        cd ${appDir}
        pnpm install --frozen-lockfile
        pnpm build
      '';
    };
  };

  # ── Serve — node only. Fast to (re)start; depends on a finished build. ────────
  systemd.services."byggogbedrag" = {
    description = "byggogbedrag.no SvelteKit site";
    after       = [ "network-online.target" "byggogbedrag-build.service" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];

    environment = serveEnv;

    serviceConfig = {
      User             = "byggogbedrag";
      Group            = "byggogbedrag";
      WorkingDirectory = appDir;
      ExecStart        = "${pkgs.nodejs}/bin/node ${appDir}/build/index.js";
      Restart          = "on-failure";
      RestartSec       = "10s";
      ProtectSystem    = "full";
      EnvironmentFile  = [ config.sops.secrets."byggogbedrag_smtp_pass".path ];
    };
  };

  # ── Deploy — build (old server stays up), then swap. Triggered by the timer ───
  #    or manually: `systemctl start byggogbedrag-update`.
  systemd.services."byggogbedrag-update" = {
    description = "Rebuild and redeploy byggogbedrag.no";
    serviceConfig = {
      Type = "oneshot";
      # Sequential: if the build fails the restart never runs, so a broken build
      # is never swapped in.
      ExecStart = [
        "${pkgs.systemd}/bin/systemctl start byggogbedrag-build.service"
        "${pkgs.systemd}/bin/systemctl restart byggogbedrag.service"
      ];
    };
  };

  systemd.timers."byggogbedrag-update" = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar        = "daily";
      RandomizeDelaySec = "30min";
      Persistent        = true;
    };
  };

  # ── App directory ─────────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d ${appDir} 0755 byggogbedrag byggogbedrag - -"
  ];
}
