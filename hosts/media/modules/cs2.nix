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

  # Ports are published on all interfaces so the NetBird DNAT on pangoling
  # can reach them via wt0. Host-level firewall still blocks 27015 on the
  # LAN interface — only wt0 is in trustedInterfaces.
  # The container needs the data dir owned by uid 1000 (the `steam` user
  # inside the image). Create the parent first so the leaf doesn't fail
  # with ENOENT.
  systemd.tmpfiles.settings."10-cs2" = {
    "/mnt/media/games".d        = { user = "root"; group = "root"; mode = "0755"; };
    "${cs2DataDir}".d            = { user = "1000"; group = "1000"; mode = "0770"; };
  };

  # joedwards32/cs2 uses CS2_* env vars (not SRCDS_*) — verified by reading
  # the image's entry.sh. Only SRCDS_TOKEN (the GSLT) kept the old name.
  sops.templates."cs2.env".content = ''
    SRCDS_TOKEN=
    CS2_RCONPW=${config.sops.placeholder."cs2/rcon_pw"}
    CS2_PW=${config.sops.placeholder."cs2/server_pw"}
  '';

  virtualisation.oci-containers.containers.cs2 = {
    image = "ghcr.io/joedwards32/cs2:latest";
    ports = [
      "27015:27015/udp"
      "27015:27015/tcp"
      "27020:27020/udp"  # SourceTV
    ];
    environment = {
      CS2_PORT       = "27015";
      TV_PORT        = "27020";
      CS2_SERVERNAME = "ybmn.no";
      CS2_MAXPLAYERS = "10";
      CS2_GAMETYPE   = "0";          # 0 = classic
      CS2_GAMEMODE   = "1";          # 1 = competitive
      CS2_MAPGROUP   = "mg_active";  # active duty pool; first map = startmap
      CS2_STARTMAP   = "de_dust2";   # must exist in the chosen mapgroup
      CS2_LAN        = "0";
      CS2_CHEATS     = "0";
      # Logging knobs (read by entry.sh, written into server.cfg via sed):
      CS2_LOG        = "on";
      CS2_LOG_FILE   = "1";
      CS2_LOG_ECHO   = "1";
      # Workshop collection 3731836451 — pulled by SteamCMD at container boot
      # so all maps in the collection are available alongside the vanilla pool.
      # Switch to them via the in-game admin menu / RTV vote (CSS# plugins).
      CS2_HOST_WORKSHOP_COLLECTION = "3731836451";
    };
    environmentFiles = [
      config.sops.templates."cs2.env".path
    ];
    volumes = [
      "${cs2DataDir}:/home/steam/cs2-dedicated"
      # Bind preset cfgs in read-only on top of the cfg dir. Inside CS2,
      # switch with: rcon exec competitive.cfg / casual.cfg / dm.cfg /
      # practice.cfg / aim.cfg. Then rcon changelevel <map> to apply.
      "${./cs2-presets/competitive.cfg}:/home/steam/cs2-dedicated/game/csgo/cfg/competitive.cfg:ro"
      "${./cs2-presets/casual.cfg}:/home/steam/cs2-dedicated/game/csgo/cfg/casual.cfg:ro"
      "${./cs2-presets/dm.cfg}:/home/steam/cs2-dedicated/game/csgo/cfg/dm.cfg:ro"
      "${./cs2-presets/practice.cfg}:/home/steam/cs2-dedicated/game/csgo/cfg/practice.cfg:ro"
      "${./cs2-presets/aim.cfg}:/home/steam/cs2-dedicated/game/csgo/cfg/aim.cfg:ro"
    ];
  };
}
