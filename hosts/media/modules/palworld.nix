{ config, pkgs, ... }:
let
  palworldData = "/mnt/games/palworld";
in {
  # games:games (uid 5 / gid 60), 2770 — matches factorio/cs2 data on the games
  # share (see storage.nix). PUID/PGID below make the container write as games.
  systemd.tmpfiles.settings."10-palworld" = {
    "${palworldData}".d = { user = "games"; group = "games"; mode = "2770"; };
  };

  # Shared bridge so the dashboard reaches the server's REST API by container
  # name (http://palworld:8212) instead of publishing 8212 to the host. Same
  # idiom as the opencloud stack.
  systemd.services.podman-network-palworld = {
    description = "Create podman network for palworld stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ${pkgs.podman}/bin/podman network exists palworld-net || \
        ${pkgs.podman}/bin/podman network create palworld-net
    '';
  };

  # SERVER_PASSWORD (join) + ADMIN_PASSWORD (RCON/REST admin) from sops.
  sops.templates."palworld.env".content = ''
    SERVER_PASSWORD=${config.sops.placeholder."palworld/server_pw"}
    ADMIN_PASSWORD=${config.sops.placeholder."palworld/admin_pw"}
  '';
  # Dashboard login (PANEL_*) + the same Palworld admin password it uses to
  # call the REST API.
  sops.templates."palworld-dash.env".content = ''
    PANEL_INITIAL_ADMIN_PASSWORD=${config.sops.placeholder."palworld/panel_pw"}
    PALWORLD_ADMIN_PASSWORD=${config.sops.placeholder."palworld/admin_pw"}
  '';

  virtualisation.oci-containers.containers = {
    palworld = {
      image = "thijsvanloef/palworld-server-docker:latest";
      ports = [
        "8211:8211/udp"   # game — public via Pangolin raw UDP resource (newt tunnel)
        # QUERY_PORT 27015/udp only needed if COMMUNITY_SERVER=true (Steam
        # browser listing). Off here, so not published. cs2 already owns 27015.
      ];
      environment = {
        PUID                       = "5";       # games
        PGID                       = "60";      # games
        PORT                       = "8211";
        PLAYERS                    = "8";
        SERVER_NAME                = "tagp palworld";
        COMMUNITY_SERVER           = "false";
        ENABLE_PERF_THREADING_ARGS = "true";    # replaces deprecated MULTITHREADING
        TZ                         = "Europe/Oslo";

        # World rules.
        HARDCORE                      = "true";       # hardcore: no respawn on player death
        PAL_LOST                      = "true";       # permanently lose pals on player death
        COLLECTION_DROP_RATE          = "3.000000";   # 3x gatherable items
        PAL_EGG_DEFAULT_HATCHING_TIME = "0";          # no egg hatch timer

        # Management surfaces — stay internal (REST reached over palworld-net,
        # RCON not published to the host at all).
        REST_API_ENABLED = "true";
        RCON_ENABLED     = "true";   # required for graceful AUTO_REBOOT

        # Counter the known memory creep: nightly reboot + backup.
        AUTO_REBOOT_ENABLED         = "true";
        AUTO_REBOOT_CRON_EXPRESSION = "0 5 * * *";
        BACKUP_ENABLED              = "true";

        # Sleep the server when empty — frees RAM/CPU on the media VM until
        # someone joins. Needs player logging + REST (both on above).
        ENABLE_PLAYER_LOGGING = "true";
        AUTO_PAUSE_ENABLED    = "true";
      };
      environmentFiles = [ config.sops.templates."palworld.env".path ];
      volumes = [ "${palworldData}:/palworld" ];
      # NET_RAW: AUTO_PAUSE_ENABLED uses raw sockets to detect player connections.
      extraOptions = [ "--network=palworld-net" "--cap-add=NET_RAW" ];
    };

    palworld-dashboard = {
      image = "ghcr.io/rnz01/palworld-server-dashboard:latest";
      dependsOn = [ "palworld" ];
      ports = [ "127.0.0.1:3939:3000" ];   # host 3939 (3000 is immich-public-proxy); loopback, internal via Caddy
      environment = {
        PALWORLD_REST_URL = "http://palworld:8212";   # over palworld-net
      };
      environmentFiles = [ config.sops.templates."palworld-dash.env".path ];
      extraOptions = [ "--network=palworld-net" ];
    };
  };
}
