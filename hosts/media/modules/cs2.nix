{ config, pkgs, ... }:
let
  # Lives on the dedicated `games` virtiofs share (see storage.nix and
  # docs/private/proxmox-virtiofs-shares.md). Keeping cs2 off /mnt/media
  # avoids the systemd-tmpfiles "unsafe path transition" issue that triggers
  # when crossing the immich-owned /mnt/media into game-server-owned subdirs.
  cs2DataDir   = "/mnt/games/cs2-modded";
  cs2CustomDir = "/mnt/games/cs2-modded-custom";

  # Preseeded admin file dropped into custom_files so tagp is root admin from
  # first boot, before the server even exists to RCON into.
  adminsJson = pkgs.writeText "cs2-admins.json" (builtins.toJSON {
    tagp = {
      identity = "76561198012874054";
      immunity = 100;
      flags    = [ "@css/root" ];
    };
  });

  # Workshop collection 3731836451 (TV2 maps — 9 maps for prophunt / hide-and-seek
  # / movement). MultiAddonManager (bundled with kus image) pulls all maps in the
  # collection. Browse them in-game via the !maps / !nominate vote menus alongside
  # the vanilla active-duty pool.
  workshopCollections = pkgs.writeText "subscribed_collection_ids.txt" ''
    3731836451
  '';

  # Override kus's default subscribed_file_ids (10 surf/bhop/kz/etc. workshop maps
  # we don't want) with an empty file. Our maps come from the collection above.
  workshopFiles = pkgs.writeText "subscribed_file_ids.txt" "";
in {
  virtualisation.podman.enable          = true;
  virtualisation.oci-containers.backend  = "podman";

  # Bind-mounted dirs created at service start instead of via tmpfiles —
  # tmpfiles refuses to chown across ownership transitions, and the games
  # virtiofs root is `games`-owned while parents are root-owned. ExecStartPre
  # runs as root and gets to ignore that check.
  #
  # Mode 2770: setgid so any files podman creates inherit the games group,
  # giving tagp shell access without chmod gymnastics.
  systemd.services.podman-cs2.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2DataDir} ${cs2CustomDir} ${cs2CustomDir}/addons ${cs2CustomDir}/addons/counterstrikesharp ${cs2CustomDir}/addons/counterstrikesharp/configs"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${adminsJson} ${cs2CustomDir}/addons/counterstrikesharp/configs/admins.json"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${workshopCollections} ${cs2CustomDir}/subscribed_collection_ids.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${workshopFiles} ${cs2CustomDir}/subscribed_file_ids.txt"
    # Override gamemodes_server.txt so Casual's mg_comp mapgroup contains only
    # our 9 TV2 workshop maps (kus ships ~22 random community maps in mg_comp
    # which pollute the !rtv / !maps vote pool). mg_active stays as the 7
    # active-duty maps, so Casual = 7 active duty + 9 workshop = 16 total.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/gamemodes_server.txt} ${cs2CustomDir}/gamemodes_server.txt"
    # GameModeManager config — kus default but with OptionsInCoolDown=0 so
    # !nominate / !rtv don't exclude recently-played maps from the menu.
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins/GameModeManager"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/GameModeManager.json} ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins/GameModeManager/GameModeManager.json"
    # mp_warmuptime override (default 60 → 30) and other server-wide tweaks.
    # cfg/custom_all.cfg is execed after server.cfg for every gamemode.
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2CustomDir}/cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/custom_all.cfg} ${cs2CustomDir}/cfg/custom_all.cfg"
  ];

  # kus image env var names. API_KEY required for workshop downloads — get one
  # from https://steamcommunity.com/dev/apikey and store as cs2/api_key in sops.
  sops.templates."cs2.env".content = ''
    RCON_PASSWORD=${config.sops.placeholder."cs2/rcon_pw"}
    SERVER_PASSWORD=${config.sops.placeholder."cs2/server_pw"}
    API_KEY=${config.sops.placeholder."cs2/api_key"}
    STEAM_ACCOUNT=
  '';

  virtualisation.oci-containers.containers.cs2 = {
    image = "ghcr.io/kus/cs2-modded-server:latest";
    ports = [
      "27015:27015/udp"
      "27015:27015/tcp"
      "27020:27020/udp"  # SourceTV
    ];
    environment = {
      PORT       = "27015";
      TICKRATE   = "128";
      MAXPLAYERS = "10";
      LAN        = "0";
    };
    environmentFiles = [
      config.sops.templates."cs2.env".path
    ];
    volumes = [
      "${cs2DataDir}:/home/steam"
      "${cs2CustomDir}:/home/custom_files"
    ];
  };
}
