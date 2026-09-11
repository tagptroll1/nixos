{ lib, ... }: {
  # State lives under the `tagp` virtiofs share so it gets backed up alongside
  # photos. Upstream's mealie module uses DynamicUser=true, which is
  # incompatible with bind-mounting /var/lib/mealie directly (systemd manages
  # the StateDirectory under /var/lib/private and bind-mounts it back). We
  # pin a static uid/gid instead, and force
  # DynamicUser off below.
  users.users.mealie = {
    isSystemUser = true;
    group = "mealie";
    uid = 992;
    home = "/var/lib/mealie";
  };
  users.groups.mealie.gid = 992;

  fileSystems."/var/lib/mealie" = {
    device = "/mnt/tagp/appdata/mealie";
    fsType = "none";
    options = [ "bind" "x-systemd.requires-mounts-for=/mnt/tagp" ];
  };

  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9925;
    database.createLocally = true;
    settings = {
      ALLOW_SIGNUP = "false";
      BASE_URL = "https://recipe.ybmn.no";
    };
  };

  systemd.services.mealie.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "mealie";
    Group = "mealie";
  };
}
