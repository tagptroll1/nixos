# Project Zomboid dedicated server, installed natively by steamcmd (no image
# exists that beats just running the shipped launcher under steam-run).
#
# External requirements, none of which this file can create:
#
#   sops — hosts/media/secrets/zomboidSecret.yaml must exist and hold the keys
#     server_pw, admin_pw and rcon_pw. The secrets are wired up in
#     hosts/media/default.nix. Create it before the first rebuild:
#       nix shell nixpkgs#sops -c sops hosts/media/secrets/zomboidSecret.yaml
#
#   Pangolin — the firewall rule below only reaches LAN and Tailscale clients.
#     Public access needs raw UDP resources for 16261 and 16262 on the VPS,
#     forwarded over the newt tunnel, same as factorio's 34197.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Everything lives on the games share (see storage.nix), same as cs2/factorio.
  # HOME points at zomboidRoot so steamcmd keeps its own state
  # (~/.local/share/Steam) inside it; the server is pointed at its data
  # directory with -cachedir instead.
  zomboidRoot = "/mnt/games/zomboid";
  zomboidServer = "${zomboidRoot}/server"; # steamcmd force_install_dir
  zomboidData = "${zomboidRoot}/Zomboid"; # server writes config/saves/db here

  # Picks which config files the server reads:
  #   <zomboidData>/Server/<serverName>.ini
  #   <zomboidData>/Server/<serverName>_SandboxVars.lua
  serverName = "ybmn";

  # Steam app id of the Project Zomboid Dedicated Server (free, anonymous login).
  appId = "380870";

  rconPort = 27015;

  # JVM max heap. The launcher reads it from ProjectZomboid64.json, which is a
  # shipped file steam restores on every app_update, so it is re-patched on each
  # start instead of edited by hand. Stock is 8g; the box has 23 GB total.
  heapSize = "12g";

  # Sandbox rules. Anything omitted keeps its vanilla default, so this file only
  # lists what we deviate on plus the knobs worth knowing about.
  # VERSION = 5 is the build 42 schema marker.
  sandboxVars = pkgs.writeText "${serverName}_SandboxVars.lua" ''
        SandboxVars = {
            VERSION = 5,

            -- In-game minutes spent per page of a book. 1.0 is vanilla; 0.5 reads
            -- twice as fast, 0.1 ten times.
            MinutesPerPage = 0.1,

            -- Skill gain rate. 1.0 vanilla.
            XpMultiplier = 1.0,

            -- One melee swing can hit several zombies. Off in vanilla.
            MultiHitZombies = true,

    				-- Ladderfix makes them into ropes, which doesnt make sense to fail
    				EasyClimbing = true,
        }
  '';

  # Vanilla has no scheduled restart, and the server leaks memory over long
  # uptimes, so warn over RCON and then `quit` — systemd's Restart=always brings
  # it straight back up.
  restartScript = pkgs.writeShellScript "zomboid-restart" ''
    set -eu
    export PATH=${pkgs.coreutils}/bin:$PATH
    rcon() { ${pkgs.rcon-cli}/bin/rcon-cli -a 127.0.0.1:${toString rconPort} -p "$ZOMBOID_RCON_PASSWORD" "$@"; }

    rcon 'servermsg "Server restarting in 5 minutes"'
    sleep 240
    rcon 'servermsg "Server restarting in 1 minute"'
    sleep 60
    rcon 'servermsg "Server restarting now"'
    # quit saves the world before shutting down; save first anyway so a hang
    # during shutdown still loses nothing.
    rcon save
    sleep 5
    rcon quit
  '';
in
{
  options.myServices.zomboid.enable = lib.mkEnableOption "the Project Zomboid dedicated server";

  config = lib.mkIf config.myServices.zomboid.enable {
    systemd.tmpfiles.settings."10-zomboid" = {
      "${zomboidRoot}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${zomboidServer}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${zomboidData}".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${zomboidData}/Server".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      # The server creates files inside these but never the directories
      # themselves: a missing db/ makes it log "failed to create user database"
      # and shut down again immediately.
      "${zomboidData}/db".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${zomboidData}/Saves".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      "${zomboidData}/Logs".d = {
        user = "games";
        group = "games";
        mode = "2770";
      };
      # Where the steamworks game server library looks for steamclient.so.
      # Without it the server falls back to the copy in its install directory
      # and only half initialises steam.
      "${zomboidRoot}/.steam/sdk64".d = {
        user = "games";
        group = "games";
        mode = "0750";
      };
      "${zomboidRoot}/.steam/sdk64/steamclient.so"."L+".argument =
        "${zomboidServer}/linux64/steamclient.so";
    };

    # Join password + RCON password land in the ini, so the whole ini is rendered
    # by sops rather than written to the nix store.
    sops.templates."zomboid.ini" = {
      owner = "games";
      content = ''
                PublicName=Yesbutmaybeno
                PublicDescription=Yes...butmaybe...no?
                # Not advertised in the in-game server browser; join by IP.
                Public=false
                # false would turn the whitelist on and require accounts to be created first.
                Open=true
                Password=${config.sops.placeholder."zomboid/server_pw"}
                MaxPlayers=16

                DefaultPort=16261
                UDPPort=16262

                # Reachable from the host only (firewall drops it) — use rcon-cli locally.
                RCONPort=${toString rconPort}
                RCONPassword=${config.sops.placeholder."zomboid/rcon_pw"}

                # Stop simulating the world while nobody is connected.
                PauseEmpty=true
                PingLimit=400

                PVP=false
                SafetySystem=true
                DisplayUserName=true
                GlobalChat=true

                PlayerSafehouse=false
                AdminSafehouse=false
                SafehouseAllowTrepass=true
        				AnnounceDeath=true
        				ShowFirstAndLastName=true
        				DisplayUserName=false

                # Sleeping only fast-forwards time when every player online is asleep,
                # so allow it but never make it mandatory.
                SleepAllowed=true
                SleepNeeded=false
        				TrashDeleteAll=true
        				ChatMessageSlowModeTime=1
        				VoiceMinDistance=100.0
        				VoiceMaxDistance=1000.0

                # 0 = save only on the game's own schedule/shutdown.
                SaveWorldEveryMinutes=10
                BackupsCount=10
                BackupsOnStart=true
                BackupsOnVersionChange=true

                Map=Muldraugh, KY

                # Workshop mods: numeric ids in WorkshopItems, mod ids in Mods, both
                # semicolon separated, dependencies first. The server downloads
                # WorkshopItems from steam itself on start, so the first start after a
                # change takes a few minutes longer.
                #
                # NeatUI_Framework is a library the three Neat/Clean UI mods require,
                # and it has to load before them. Neat Building is the full variant
                # (UI + buildables + railings); the split SES variants only matter
                # alongside Stairs East & South, which is not installed.
                #
        				#   3629835761  Ladders4220           Ladders?!
                #   3508537032  NeatUI_Framework      NeatUI Framework
                #   3437629766  CleanUI               CleanUI
                #   3536052310  Neat_Building         Neat Building
                #   3502080466  Neat_Crafting         Neat Crafting
                #   3461263912  CleanHotBar           Clean Hot Bar
                #   3774826484  JumboTreeIndoorFix    Jumbo Tree Indoor Fix
                #   3577903007  VanillaFoodsExpanded  Vanilla Foods Expanded
                #   3689524052  LTWB42                Legendary Tactical Weapons
                #   3436537035  UsefulBarrelsMP       Useful Barrels
                #   3739168410  Obvious_Skill_Tapes   Obvious Skill Tapes
                #   3387539308  AutoMechanics         Auto Mechanics
                #   3668370011  LKB42                 Legendary Katana Wakizashi
                #   3538353228  LBB42                 Legendary Backpacks
                #   3552050880  LFB42                 Legendary Fanny Pack
                #   3558839307  LDB42                 Legendary DuffelBag
                #   3560352772  LSB42                 Legendary Satchel
                #   3549294472  LCB42                 Legendary Cap
                WorkshopItems=3508537032;3437629766;3536052310;3502080466;3461263912;3774826484;3577903007;3689524052;3436537035;3739168410;3387539308;3668370011;3538353228;3552050880;3558839307;3560352772;3549294472;3629835761
                Mods=NeatUI_Framework;CleanUI;Neat_Building;Neat_Crafting;CleanHotBar;JumboTreeIndoorFix;VanillaFoodsExpanded;LTWB42;UsefulBarrelsMP;Obvious_Skill_Tapes;AutoMechanics;LKB42;LBB42;LFB42;LDB42;LSB42;LCB42;Ladders4220
      '';
    };

    # -adminpassword goes through the environment so the plaintext is not written
    # to the nix store. It is re-applied on every start.
    sops.templates."zomboid.env" = {
      owner = "games";
      content = ''
        ZOMBOID_ADMIN_PASSWORD=${config.sops.placeholder."zomboid/admin_pw"}
        ZOMBOID_RCON_PASSWORD=${config.sops.placeholder."zomboid/rcon_pw"}
      '';
    };

    systemd.services.zomboid = {
      description = "Project Zomboid dedicated server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "mnt-games.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "mnt-games.mount" ];

      # No SteamAppId here: the install ships steam_appid.txt holding 108600,
      # the game's own id, and that is what the game server has to register
      # with. The environment variable takes precedence over the file, so
      # setting it to the dedicated server tool's id (appId, 380870) is what
      # leaves steam half initialised.
      environment.HOME = zomboidRoot;

      serviceConfig = {
        User = "games";
        Group = "games";
        WorkingDirectory = zomboidServer;
        EnvironmentFile = config.sops.templates."zomboid.env".path;

        # Nothing to start before the game files exist. A failing ExecCondition
        # leaves the unit inactive instead of triggering Restart=, so an empty
        # install waits for zomboid-update rather than looping every 30s.
        ExecCondition = "${pkgs.coreutils}/bin/test -x ${zomboidServer}/start-server.sh";

        ExecStartPre = [
          # Nix owns the config: both files are overwritten on every start, so
          # changes made in-game through the admin panel do not survive a restart.
          "${pkgs.coreutils}/bin/install -m 0640 ${
            config.sops.templates."zomboid.ini".path
          } ${zomboidData}/Server/${serverName}.ini"
          "${pkgs.coreutils}/bin/install -m 0640 ${sandboxVars} ${zomboidData}/Server/${serverName}_SandboxVars.lua"
          # Patch in place rather than rendering the whole file: the rest of
          # vmArgs is upstream's business and changes between builds.
          "${pkgs.gnused}/bin/sed -i -E s/-Xmx[0-9]+[mMgG]/-Xmx${heapSize}/ ${zomboidServer}/ProjectZomboid64.json"
        ];

        # The shipped launcher and its bundled JRE are plain FHS binaries — steam-run
        # supplies the loader and libraries they expect.
        # -cachedir is what points the server at zomboidData. HOME does not: the
        # JVM takes user.home from the games user's passwd entry, /var/empty, so
        # without this the server writes its ini and saves there and exits.
        #
        # Steam stays enabled, which is what lets an ordinary steam client join
        # by IP with no launch options. Adding -nosteam here (the documented
        # spelling of -Dzomboid.steam=0) moves everything onto RakNet instead,
        # at the price of every client needing -nosteam in its own launch
        # options - a non-steam client can only join a non-steam server.
        ExecStart = "${pkgs.steam-run}/bin/steam-run ${zomboidServer}/start-server.sh -cachedir=${zomboidData} -servername ${serverName} -adminusername admin -adminpassword \${ZOMBOID_ADMIN_PASSWORD}";

        Restart = "always";
        RestartSec = 30;
        # The server saves the world on SIGTERM; give it room to finish.
        KillSignal = "SIGTERM";
        TimeoutStopSec = 180;
      };
    };

    # Downloading 7 GB from Steam is not part of starting the game: as an
    # ExecStartPre it makes every `systemctl start` and every nixos-rebuild
    # block until steam is done. Kept in its own unit, the game server starts in
    # seconds and updates are a job that runs, and can be watched, on its own.
    systemd.services.zomboid-update = {
      description = "Install or update the Project Zomboid dedicated server from Steam";
      after = [
        "network-online.target"
        "mnt-games.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "mnt-games.mount" ];

      environment = {
        HOME = zomboidRoot;
        SteamAppId = appId;
      };

      serviceConfig = {
        Type = "oneshot";
        User = "games";
        Group = "games";
        WorkingDirectory = zomboidServer;
        # Public branch — build 42.20.x is the stable release since July 2026,
        # so no -beta flag. `validate` is left off: it rehashes all 7 GB, which
        # is only worth it to repair a broken install, by hand:
        #   steamcmd +force_install_dir <dir> +login anonymous \
        #     +app_update 380870 validate +quit
        ExecStart = "${pkgs.steamcmd}/bin/steamcmd +force_install_dir ${zomboidServer} +login anonymous +app_update ${appId} +quit";
        # The first run downloads the whole game; steam sets no pace for it.
        TimeoutStartSec = "infinity";
      };
    };

    systemd.timers.zomboid-update = {
      description = "Daily Project Zomboid update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Ahead of the 05:00 restart, which is what puts a new build live.
        OnCalendar = "04:45";
        Persistent = true;
      };
    };

    systemd.services.zomboid-restart = {
      description = "Warn players over RCON, then cycle the Project Zomboid server";
      serviceConfig = {
        Type = "oneshot";
        User = "games";
        Group = "games";
        EnvironmentFile = config.sops.templates."zomboid.env".path;
        # Nothing to warn or cycle if the server is not up.
        ExecCondition = "${config.systemd.package}/bin/systemctl --quiet is-active zomboid.service";
        ExecStart = restartScript;
        TimeoutStartSec = 600;
      };
    };

    systemd.timers.zomboid-restart = {
      description = "Nightly Project Zomboid restart to shed the JVM memory creep";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "05:00";
        Persistent = false;
      };
    };

    # Game traffic for LAN/Tailscale clients. 16261 is the main port, 16262 the
    # direct-connect port; both UDP.
    networking.firewall.allowedUDPPorts = [
      16261
      16262
    ];
  };
}
