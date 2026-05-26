{ ... }: {
  # Single source of truth for the container runtime on this host. Consumed by
  # cs2.nix, factorio.nix, immich.nix and opencloud.nix, which only declare their
  # own `virtualisation.oci-containers.containers.*`.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
}
