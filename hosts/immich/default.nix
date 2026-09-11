{ ... }: {
  imports = [
    # Shared modules
    ../../shared/modules/base.nix
    ../../shared/modules/sshd.nix
    ../../shared/modules/dns.nix
    ../../shared/modules/lxc.nix
    ../../shared/modules/nvidia-userspace.nix

    # Host-specific modules
    ./modules/networking.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/storage.nix
    ./modules/immich.nix
    ./modules/caddy.nix
    ./modules/backup.nix
  ];

  # One secret, and it is not immich's: the domeneshop API credentials Caddy
  # needs to prove immich.ybmn.no over DNS-01. Immich's own secrets live in its
  # database, and `settings = null` leaves the rest to its admin UI.
  #
  # Encrypted to this host's key and the admin key only (.sops.yaml), so a
  # compromise here yields nothing that unlocks another machine.
  sops.age.keyFile = "/etc/age/host.key";
  sops.secrets."caddy/domeneshop_token" = {
    sopsFile = ./secrets/caddySecret.yaml;
    key = "token";
    owner = "caddy";
  };
}
