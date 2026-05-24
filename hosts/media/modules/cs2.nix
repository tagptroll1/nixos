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
