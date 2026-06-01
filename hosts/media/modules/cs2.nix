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
		exmx = {
			identity = "76561197960441548";
			immunity = 90;
			flags = [ "@css/root" ];
		};
  });

  cssDir = "${cs2CustomDir}/addons/counterstrikesharp";

  # --- Prop Hunt --------------------------------------------------------------
  # Server-side prophunt via the exkludera PropHunt plugin (runs on NORMAL maps;
  # no workshop VScript prophunt maps). MultiAddonManager (a PropHunt dep) is
  # already in the kus image.
  #
  # PropHunt is BUILT FROM SOURCE (see pkgs/cs2-prophunt) with a patch that adds
  # bindable console commands (css_phfreeze/decoy/taunt/swap) and disables the
  # on-screen action menu — the upstream release only exposes those actions as
  # chat-driven menu items ("!1".."!4"), which we don't want.
  propHunt = pkgs.callPackage ../../../pkgs/cs2-prophunt { };

  # Drop the PropHunt plugin DLL into custom_files. It's gated to
  # plugins/disabled and loaded only by prophunt.cfg, then unloaded by our
  # unload_plugins.cfg override (its round-start handler would otherwise turn
  # hiders into props in every mode). CounterStrikeSharp.API is provided by the
  # kus image; CS2MenuManager dep was patched out — no longer needed.
  seedPlugins = pkgs.writeShellScript "cs2-seed-plugins" ''
    export PATH=${pkgs.coreutils}/bin:$PATH
    set -eu
    css=${cssDir}
    install -d -o games -g games -m 2770 \
      "$css/plugins" "$css/plugins/disabled" "$css/plugins/disabled/PropHunt" \
      "$css/plugins/disabled/PropHunt/maps" "$css/gamedata" \
      "$css/configs/plugins/PropHunt"
    cp --no-preserve=mode,ownership ${propHunt}/lib/cs2-prophunt/PropHunt.dll "$css/plugins/disabled/PropHunt/PropHunt.dll"
    cp --no-preserve=mode,ownership ${propHunt}/lib/cs2-prophunt/PropHunt.deps.json "$css/plugins/disabled/PropHunt/PropHunt.deps.json"
    chown -R games:games "$css/plugins/disabled/PropHunt"
    chmod -R u+rwX,g+rwX "$css/plugins/disabled/PropHunt"
  '';

in {
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
    # PropHunt plugin binary into custom_files.
    "${seedPlugins}"
    # PropHunt gamedata (offsets) — vendored since we build from source.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/gamedata_prophunt.json} ${cssDir}/gamedata/gamedata_prophunt.json"
    # PropHunt plugin config
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/PropHunt.json} ${cssDir}/configs/plugins/PropHunt/PropHunt.json"
    # Per-map prop-model lists — Premier / Competitive Active Duty pool, generated
    # by pkgs/cs2-prophunt-lists (filters CS2's vmdl index for hideable props).
    # default.txt is the fallback used by patched AddMapModels for any other map.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/default.txt} ${cssDir}/plugins/disabled/PropHunt/maps/default.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_ancient.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_ancient.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_anubis.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_anubis.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_cache.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_cache.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_dust2.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_dust2.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_inferno.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_inferno.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_mirage.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_mirage.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_nuke.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_nuke.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_overpass.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_overpass.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_train.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_train.txt"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt-maps/de_vertigo.txt} ${cssDir}/plugins/disabled/PropHunt/maps/de_vertigo.txt"
    # Prop Hunt mode cfg chain (prophunt.cfg → prophunt_settings.cfg → custom_prophunt.cfg)
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt.cfg} ${cs2CustomDir}/cfg/prophunt.cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/prophunt_settings.cfg} ${cs2CustomDir}/cfg/prophunt_settings.cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/custom_prophunt.cfg} ${cs2CustomDir}/cfg/custom_prophunt.cfg"
    # unload_plugins.cfg override — stock list + "Prop Hunt" so it never leaks
    # into other modes.
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/unload_plugins.cfg} ${cs2CustomDir}/cfg/unload_plugins.cfg"

    # CS2AnnouncementBroadcaster messages.json override — replaces the kus
    # default Hide-and-Seek welcome (which references the old "E in front /
    # E under" controls) with our actual PropHunt controls (E = freeze,
    # R = swap, Mouse2 = taunt, A/D = rotate while frozen).
    "${pkgs.coreutils}/bin/install -d -o games -g games -m 2770 ${cssDir}/plugins/CS2AnnouncementBroadcaster/cfg"
    "${pkgs.coreutils}/bin/install -m 0660 -o games -g games ${./cs2-presets/cs2ab-messages.json} ${cssDir}/plugins/CS2AnnouncementBroadcaster/cfg/messages.json"
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
