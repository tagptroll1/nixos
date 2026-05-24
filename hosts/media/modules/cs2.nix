{ config, pkgs, ... }:
let
  # Switched from joedwards32/cs2 (vanilla dedicated) to kus/cs2-modded-server
  # because joedwards32's metamod folder-enum issue on this host kept blocking
  # CSS#/SimpleAdmin/RTV from loading. kus ships MetaMod + CSS# preinstalled
  # and is purpose-built for the modded workflow we want.
  #
  # Data dir is fresh (not the old /mnt/media/games/cs2 vanilla install) so
  # the kus image gets a clean SteamCMD run on its own expected layout.
  # The old dir is left in place at /mnt/media/games/cs2 as a backup —
  # delete it manually once the new server is working.
  cs2DataDir   = "/mnt/media/games/cs2-modded";
  cs2CustomDir = "/mnt/media/games/cs2-modded-custom";

  # Preseeded admin file dropped into custom_files so tagp is root admin from
  # first boot, before the server even exists to RCON into.
  adminsJson = pkgs.writeText "cs2-admins.json" (builtins.toJSON {
    tagp = {
      identity = "76561198012874054";
      immunity = 100;
      flags    = [ "@css/root" ];
    };
  });
in {
  virtualisation.podman.enable  = true;
  virtualisation.oci-containers.backend = "podman";

  systemd.tmpfiles.settings."10-cs2" = {
    "/mnt/media/games".d = { user = "root"; group = "root"; mode = "0755"; };
    "${cs2DataDir}".d    = { user = "1000"; group = "1000"; mode = "0770"; };
    "${cs2CustomDir}".d  = { user = "1000"; group = "1000"; mode = "0770"; };
    # CSS# admin config — overlays into the container's
    # /home/custom_files/addons/counterstrikesharp/configs/admins.json
    "${cs2CustomDir}/addons".d                                                     = { user = "1000"; group = "1000"; mode = "0770"; };
    "${cs2CustomDir}/addons/counterstrikesharp".d                                  = { user = "1000"; group = "1000"; mode = "0770"; };
    "${cs2CustomDir}/addons/counterstrikesharp/configs".d                          = { user = "1000"; group = "1000"; mode = "0770"; };
    "${cs2CustomDir}/addons/counterstrikesharp/configs/admins.json"."L+".argument  = "${adminsJson}";
  };

  # kus image env var names (NOT CS2_*). API_KEY is required for workshop
  # downloads — register one at https://steamcommunity.com/dev/apikey and
  # add to sops as cs2/api_key.
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
