{ ... }:
let
  # Bind mounts splice host-owned ZFS datasets into Immich's per-user
  # library directory. The storage template puts user.storageLabel as
  # the first path segment (`library/<label>/<y>/<MM>/<filename>`), so
  # we mirror those label paths to the matching dataset on home02.
  #
  # The datasets themselves arrive as Proxmox mountpoints on the CT
  # (`mp0: /hddmirror/tagp/photos,mp=/mnt/tagp/photos` and friends), which is
  # why they are not declared here: lxc mounts them before systemd starts, and
  # a second declaration would race it. What is declared is the guest-side
  # splice from there into immich's library.
  bind = source: target: {
    ${target} = {
      device = source;
      fsType = "none";
      options = [ "bind" "x-systemd.requires-mounts-for=${source}" ];
    };
  };

  # Storage labels assigned to each Immich user. Adding a user means:
  # set their account's Storage Label to a new entry here, add the CT
  # mountpoint on home02, then add the bind mount + tmpfiles entry below.
  labels = {
    tagp = "tagp";
    karoline = "karoline";
  };
in {
  fileSystems =
    (bind "/mnt/tagp/photos" "/var/lib/immich/library/${labels.tagp}")
    // (bind "/mnt/karoline/photos" "/var/lib/immich/library/${labels.karoline}");

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
