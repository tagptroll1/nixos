{ pkgs, config, ... }:

let
  appDir  = "/var/lib/byggogbedrag";
  appPort = 3001;
in
{
  # ── Runtime service (build on start, then serve) ─────────────────────────────
  systemd.services."byggogbedrag" = {
    description = "byggogbedrag.no SvelteKit site";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];

    path = with pkgs; [ git nodejs pnpm coreutils bash ];

    environment = {
      NODE_ENV = "production";
      HOST     = "0.0.0.0";
      PORT     = toString appPort;
      ORIGIN   = "https://byggogbedrag.no";
      HOME     = appDir;
      # SMTP — mailserver on this host. 587 = STARTTLS. SMTP_PASS via sops below.
      SMTP_HOST = "mail.yesbutmaybe.no";
      SMTP_PORT = "587";
      SMTP_USER = "post@byggogbedrag.no";
    };

    preStart = ''
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

    serviceConfig = {
      User             = "byggogbedrag";
      Group            = "byggogbedrag";
      WorkingDirectory = appDir;
      ExecStart        = "${pkgs.nodejs}/bin/node ${appDir}/build/index.js";
      Restart          = "on-failure";
      RestartSec       = "10s";
      TimeoutStartSec  = "300";
      ProtectSystem    = "full";
      ReadWritePaths   = [ appDir ];
      EnvironmentFile  = [
        config.sops.secrets."github_token".path
        config.sops.secrets."byggogbedrag_smtp_pass".path
      ];
    };
  };

  # ── Daily update — restarts the service which triggers a rebuild ──────────────
  systemd.services."byggogbedrag-update" = {
    description = "Rebuild and redeploy byggogbedrag.no";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart byggogbedrag.service";
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
