{ lib, ... }: {
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

  # One secret: the Anthropic API key financio-ocr sends long receipts to Claude
  # with (modules/ocr.nix). Encrypted to this host's key and the admin key only
  # (.sops.yaml), so a compromise here yields nothing that unlocks another
  # machine.
  #
  # Optional, and the host builds without it: with no secret file in the repo
  # nothing is declared, the unit starts with no key, and every receipt is read
  # on the card.
  sops.age.keyFile = "/etc/age/host.key";
  sops.secrets = lib.mkIf (builtins.pathExists ./secrets/financioOcrSecret.yaml) {
    # A dotenv blob: ANTHROPIC_API_KEY. Read by PID 1 as the unit's
    # EnvironmentFile, so it stays root-only.
    "financio-ocr/env" = {
      sopsFile = ./secrets/financioOcrSecret.yaml;
      key = "env";
    };
  };
}
