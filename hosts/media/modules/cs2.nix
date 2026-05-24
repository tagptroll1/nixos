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

in {
  virtualisation.podman.enable          = true;
  virtualisation.oci-containers.backend  = "podman";

  systemd.services.podman-cs2.serviceConfig.ExecStartPre = [
	  # Ensure all dirs exists
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2DataDir} ${cs2CustomDir} ${cs2CustomDir}/addons ${cs2CustomDir}/addons/counterstrikesharp ${cs2CustomDir}/addons/counterstrikesharp/configs"
		# Copy over admins.json
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${adminsJson} ${cs2CustomDir}/addons/counterstrikesharp/configs/admins.json"
    # Copy over workshop collection ids list
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${workshopCollections} ${cs2CustomDir}/subscribed_collection_ids.txt"
    # Override gamemodes_server to include our custom maps too
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/gamemodes_server.txt} ${cs2CustomDir}/gamemodes_server.txt"
		# Make sure dirs for the gamemodemanger.json file to be copied
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins/GameModeManager"
		# Copy the GameModeManager.json to override a few settings.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/GameModeManager.json} ${cs2CustomDir}/addons/counterstrikesharp/configs/plugins/GameModeManager/GameModeManager.json"
    # Override custom_all.cfg
    # mp_warmuptime override (default 60 → 30) and other server-wide tweaks.
    # cfg/custom_all.cfg is execed after server.cfg for every gamemode.
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2CustomDir}/cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/custom_all.cfg} ${cs2CustomDir}/cfg/custom_all.cfg"
    # Competitive overrides — exec'd by the kus comp.cfg → comp_settings.cfg
    # chain (after gamemode_competitive.cfg, re-applied after map start).
		"${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/custom_comp.cfg} ${cs2CustomDir}/cfg/custom_comp.cfg"
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
      MAXPLAYERS = "64";
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
