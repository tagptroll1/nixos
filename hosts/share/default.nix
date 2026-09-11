{ ... }: {
  imports = [
    # Shared modules
    ../../shared/modules/base.nix
    ../../shared/modules/sshd.nix
    ../../shared/modules/dns.nix
    ../../shared/modules/lxc.nix
    (import ../../shared/modules/newt.nix {
      endpoint = "https://pangolin.yesbutmaybe.no";
      secretIdKey = "newt-id-share";
      secretSecretKey = "newt-secret-share";
    })

    # Host-specific modules
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/share.nix
  ];

  sops.age.keyFile = "/etc/age/host.key";
  sops.secrets = {
    "newt-id-share" = {
      sopsFile = ./secrets/newtSecret.yaml;
      key = "newt-id-share";
    };
    "newt-secret-share" = {
      sopsFile = ./secrets/newtSecret.yaml;
      key = "newt-secret-share";
    };
  };
}
