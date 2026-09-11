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
    ./modules/ocr.nix
  ];

  # No sops on this host. financio-ocr holds no credentials: it is reached over
  # one firewalled port from one address, and the images it reads arrive in the
  # request. Adding a key here would be a secret store with nothing in it.
}
