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

  # Bind mounts splice host-owned ZFS datasets into Immich's per-user
  # library directory. The storage template puts user.storageLabel as
  # the first path segment (`library/<label>/<y>/<MM>/<filename>`), so
  # we mirror those label paths to the matching dataset on home02.
  bind = source: target: {
    ${target} = {
      device = source;
      fsType = "none";
      options = [ "bind" "x-systemd.requires-mounts-for=${source}" ];
    };
  };

  # Storage labels assigned to each Immich user. Adding a user means:
  # set their account's Storage Label to a new entry here, then add the
  # bind mount + tmpfiles entry below.
  labels = {
    tagp = "tagp";
    karoline = "karoline";
  };
in {
  fileSystems =
    (virtiofs "tagp"     "/mnt/tagp")
    // (virtiofs "karoline" "/mnt/karoline")
    // (virtiofs "media"  "/mnt/media")
    // (virtiofs "games"  "/mnt/games")
    // (bind "/mnt/tagp/photos" "/var/lib/immich/library/${labels.tagp}")
    // (bind "/mnt/karoline/photos" "/var/lib/immich/library/${labels.karoline}");

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

  systemd.tmpfiles.settings = {
    "10-immich-library" = {
      "/var/lib/immich".d = {
        user = "immich"; group = "immich"; mode = "0750";
      };
      "/var/lib/immich/library".d = {
        user = "immich"; group = "immich"; mode = "0750";
      };
      "/var/lib/immich/library/${labels.tagp}".d = {
        user = "immich"; group = "immich"; mode = "0750";
      };
      "/var/lib/immich/library/${labels.karoline}".d = {
        user = "immich"; group = "immich"; mode = "0750";
      };
    };
  };
}
