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

  cssDir = "${cs2CustomDir}/addons/counterstrikesharp";

  # --- Prop Hunt --------------------------------------------------------------
  # Server-side prophunt via the exkludera PropHunt plugin (runs on NORMAL maps;
  # no workshop VScript prophunt maps). Two binaries the kus image doesn't ship;
  # MultiAddonManager (also a PropHunt dependency) IS already in the image.
  # Fetched reproducibly (pinned zip hashes) and unpacked at build time.
  unpackZip = name: url: hash:
    pkgs.runCommand name { } ''
      mkdir -p $out
      ${pkgs.unzip}/bin/unzip -q ${pkgs.fetchurl { inherit url hash; }} -d $out
    '';

  # exkludera/PropHunt — the prophunt gamemode plugin (alpha, v0.0.1).
  propHunt = unpackZip "cs2-prophunt-0.0.1"
    "https://github.com/exkludera-cssharp/PropHunt/releases/download/0.0.1/PropHunt_0.0.1.zip"
    "sha256-0TwQeDLyBVxcIpd/WzCddstqulx1ZQ15E868ADY1Itg=";

  # schwarper/CS2MenuManager — PropHunt's menu dependency (kus ships WASDMenuAPI
  # instead, which PropHunt does not use).
  cs2MenuManager = unpackZip "cs2-menumanager-v42"
    "https://github.com/schwarper/CS2MenuManager/releases/download/v1.0.42/CS2MenuManager-v42.zip"
    "sha256-iIjOqXvaEqa8YPctVb25yZKChJAPRtyt6uvjEnDPTD0=";

  # Drop the plugin binaries into custom_files. CS2MenuManager is always-on
  # (plugins/ + shared/); PropHunt is gated to plugins/disabled and loaded only
  # by prophunt.cfg, then unloaded by our unload_plugins.cfg override elsewhere
  # (its round-start handler would turn hiders into props in every mode).
  seedPlugins = pkgs.writeShellScript "cs2-seed-plugins" ''
    export PATH=${pkgs.coreutils}/bin:$PATH
    set -eu
    css=${cssDir}
    install -d -o games -g games -m 2770 \
      "$css/plugins" "$css/plugins/disabled" "$css/shared" "$css/gamedata" \
      "$css/configs/plugins/PropHunt"
    cp -rT --no-preserve=mode,ownership ${cs2MenuManager}/plugins/CS2MenuManager_MenuManager "$css/plugins/CS2MenuManager_MenuManager"
    cp -rT --no-preserve=mode,ownership ${cs2MenuManager}/shared/CS2MenuManager "$css/shared/CS2MenuManager"
    cp -rT --no-preserve=mode,ownership ${propHunt}/plugins/PropHunt "$css/plugins/disabled/PropHunt"
    cp --no-preserve=mode,ownership ${propHunt}/gamedata/gamedata_prophunt.json "$css/gamedata/gamedata_prophunt.json"
    chown -R games:games "$css/plugins/CS2MenuManager_MenuManager" "$css/shared/CS2MenuManager" "$css/plugins/disabled/PropHunt" "$css/gamedata/gamedata_prophunt.json"
    chmod -R u+rwX,g+rwX "$css/plugins/CS2MenuManager_MenuManager" "$css/shared/CS2MenuManager" "$css/plugins/disabled/PropHunt"
  '';

in {
  virtualisation.podman.enable          = true;
  virtualisation.oci-containers.backend  = "podman";

  systemd.services.podman-cs2.serviceConfig.ExecStartPre = [
	  # Ensure all dirs exists
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cs2DataDir} ${cs2CustomDir} ${cs2CustomDir}/addons ${cs2CustomDir}/addons/counterstrikesharp ${cs2CustomDir}/addons/counterstrikesharp/configs"
		# Copy over admins.json
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${adminsJson} ${cs2CustomDir}/addons/counterstrikesharp/configs/admins.json"
    # Override gamemodes_server to include our custom maps too (workshop maps are
    # referenced directly by id here — no subscribed_collection_ids.txt needed).
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/gamemodes_server.txt} ${cs2CustomDir}/gamemodes_server.txt"
    # Drop the old collection-id file so MultiAddonManager stops pulling it.
    "${pkgs.coreutils}/bin/rm -f ${cs2CustomDir}/subscribed_collection_ids.txt"
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

    # --- Prop Hunt ----------------------------------------------------------
    # Plugin binaries (PropHunt + CS2MenuManager) into custom_files.
    "${seedPlugins}"
    # PropHunt plugin config
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/PropHunt.json} ${cssDir}/configs/plugins/PropHunt/PropHunt.json"
    # Per-map prop-model lists (seedPlugins already created the maps/ dir from
    # the zip; these add/overwrite). de_dust2 ships with the plugin.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_dust2.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_dust2.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_inferno.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_inferno.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_mirage.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_mirage.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_nuke.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_nuke.txt"
    # Prop Hunt mode cfg chain (prophunt.cfg → prophunt_settings.cfg → custom_prophunt.cfg)
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt.cfg} ${cs2CustomDir}/cfg/prophunt.cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt_settings.cfg} ${cs2CustomDir}/cfg/prophunt_settings.cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/custom_prophunt.cfg} ${cs2CustomDir}/cfg/custom_prophunt.cfg"
    # unload_plugins.cfg override — stock list + "Prop Hunt" so it never leaks
    # into other modes.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/unload_plugins.cfg} ${cs2CustomDir}/cfg/unload_plugins.cfg"
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
