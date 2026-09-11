{ ... }:
let
  # virtiofs tags configured on the Proxmox host side as Directory Mappings.
  virtiofs = tag: target: {
    ${target} = {
      device = tag;
      fsType = "virtiofs";
      options = [ "defaults" "nofail" "x-systemd.device-timeout=10s" ];
    };
  };
in {
  # /mnt/media and /mnt/games carry the game servers' data. /mnt/tagp and
  # /mnt/karoline are the household datasets; nothing here writes to them, but
  # they stay mounted because this is the host with an interactive login and a
  # file browser, and dropping them would mean editing the Proxmox side too.
  fileSystems =
    (virtiofs "tagp"     "/mnt/tagp")
    // (virtiofs "karoline" "/mnt/karoline")
    // (virtiofs "media"  "/mnt/media")
    // (virtiofs "games"  "/mnt/games");

  # Mirror the Debian default `games` user (uid 5 / gid 60) so file ownership
  # is consistent between home02 (via virtiofs) and what shows up in /mnt/games
  # on the VM. tagp gets group membership for direct access.
  users.users.games = {
    isSystemUser = true;
    uid = 5;
    group = "games";
    description = "shared owner of game-server data on /mnt/games";
  };
  users.groups.games.gid = 60;
  users.users.tagp.extraGroups = [ "games" ];
}
