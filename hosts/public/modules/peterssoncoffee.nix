{ pkgs, config, ... }:

let
  appDir  = "/var/lib/peterssoncoffee";
  appPort = 3000;

  buildEnv = {
    NODE_ENV = "production";
    HOME     = appDir;
  };

  serveEnv = {
    NODE_ENV = "production";
    HOST     = "0.0.0.0";
    PORT     = toString appPort;
    ORIGIN   = "https://yesbutmaybe.no";
    HOME     = appDir;
  };
in
{
  # ── Build — fetch + compile into appDir. Runs while the old server keeps ──────
  #    serving, so a rebuild never takes the site offline. Inactive once done, so
  #    a plain `nixos-rebuild switch` does NOT re-trigger it. Only this unit gets
  #    the github token — the long-running serve process never sees it.
  systemd.services."peterssoncoffee-build" = {
    description = "Build petersson.coffee";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];   # build once at boot
    before      = [ "peterssoncoffee.service" ];

    path = with pkgs; [ git nodejs pnpm coreutils bash ];

    environment = buildEnv;

    serviceConfig = {
      Type             = "oneshot";
      User             = "peterssoncoffee";
      Group            = "peterssoncoffee";
      WorkingDirectory = appDir;
      TimeoutStartSec  = "300";
      ProtectSystem    = "full";
      ReadWritePaths   = [ appDir ];
      EnvironmentFile  = [ config.sops.secrets."github_token".path ];
      ExecStart = pkgs.writeShellScript "peterssoncoffee-build" ''
        set -e
        if [ ! -d ${appDir}/.git ]; then
          git clone https://github.com/tagptroll1/peterssoncoffee.git ${appDir}
        else
          git -C ${appDir} fetch origin
          git -C ${appDir} reset --hard origin/master
        fi
        cd ${appDir}
        pnpm install --frozen-lockfile
        pnpm build
      '';
    };
  };

  # ── Serve — node only. Fast to (re)start; depends on a finished build. ────────
  systemd.services."peterssoncoffee" = {
    description = "petersson.coffee SvelteKit site";
    after       = [ "network-online.target" "peterssoncoffee-build.service" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];

    environment = serveEnv;

    serviceConfig = {
      User             = "peterssoncoffee";
      Group            = "peterssoncoffee";
      WorkingDirectory = appDir;
      ExecStart        = "${pkgs.nodejs}/bin/node ${appDir}/build/index.js";
      Restart          = "on-failure";
      RestartSec       = "10s";
      ProtectSystem    = "full";
    };
  };

  # ── Deploy — build (old server stays up), then swap. Triggered by the timer ───
  #    or manually: `systemctl start peterssoncoffee-update`.
  systemd.services."peterssoncoffee-update" = {
    description = "Rebuild and redeploy petersson.coffee";
    serviceConfig = {
      Type = "oneshot";
      # Sequential: if the build fails the restart never runs, so a broken build
      # is never swapped in.
      ExecStart = [
        "${pkgs.systemd}/bin/systemctl start peterssoncoffee-build.service"
        "${pkgs.systemd}/bin/systemctl restart peterssoncoffee.service"
      ];
    };
  };

  systemd.timers."peterssoncoffee-update" = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar        = "daily";
      RandomizeDelaySec = "30min";
      Persistent        = true;
    };
  };

  # ── App directory ─────────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d ${appDir} 0755 peterssoncoffee peterssoncoffee - -"
  ];
}
