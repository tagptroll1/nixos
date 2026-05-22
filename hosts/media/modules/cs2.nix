{ config, ... }:
let
  # ~40 GB game install — almost entirely Steam-redownloadable content, so
  # parked on `/mnt/media` (bulk dataset, not in the Tier-A backup set) to
  # avoid burning Hetzner Storage Box space on data SteamCMD can refetch.
  # If you ever want to back up server.cfg / custom maps, snapshot the
  # `game/csgo/cfg/` and `game/csgo/maps/` subdirs only.
  cs2DataDir = "/mnt/media/games/cs2";
in {
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Ports stay on 127.0.0.1; external reachability is via the Pangolin
  # `newt` tunnel (configured in default.nix). The container needs the
  # data dir owned by uid 1000 (the `steam` user inside the image).
  # Create the parent first so the leaf doesn't fail with ENOENT.
  systemd.tmpfiles.settings."10-cs2" = {
    "/mnt/media/games".d        = { user = "root"; group = "root"; mode = "0755"; };
    "${cs2DataDir}".d            = { user = "1000"; group = "1000"; mode = "0770"; };
  };

  sops.templates."cs2.env".content = ''
    SRCDS_TOKEN=
    SRCDS_RCONPW=${config.sops.placeholder."cs2/rcon_pw"}
    SRCDS_PW=${config.sops.placeholder."cs2/server_pw"}
  '';

  virtualisation.oci-containers.containers.cs2 = {
    # joedwards32/cs2 is the de-facto community image; entrypoint runs
    # steamcmd on start so a `podman restart cs2` is the update path.
    # Pin a digest once first deployed (replace :latest with @sha256:...)
    # to control when CS2 game updates land.
    image = "ghcr.io/joedwards32/cs2:latest";
    ports = [
      "127.0.0.1:27015:27015/udp"
      "127.0.0.1:27015:27015/tcp"
      "127.0.0.1:27020:27020/udp"  # SourceTV / RCON over UDP
    ];
    environment = {
      SRCDS_PORT = "27015";
      SRCDS_TV_PORT = "27020";
      SRCDS_HOSTNAME = "ybmn.no";
      SRCDS_MAXPLAYERS = "10";
      SRCDS_GAMETYPE = "0";   # 0 = classic
      SRCDS_GAMEMODE = "1";   # 1 = competitive
      SRCDS_MAP = "de_dust2";
      SRCDS_REGION = "3";     # 3 = europe
      SRCDS_LAN = "0";
    };
    environmentFiles = [
      config.sops.templates."cs2.env".path
    ];
    volumes = [
      "${cs2DataDir}:/home/steam/cs2-dedicated"
    ];
  };
}
