{ ... }: {
  # Single source of truth for the container runtime on this host. Consumed by
  # cs2.nix, factorio.nix and opencloud.nix, which only declare their own
  # `virtualisation.oci-containers.containers.*`.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Containers get their own network namespace, where the resolved stub at
  # 127.0.0.53 is this container's loopback and answers nothing. Left to
  # inherit the host's resolv.conf they would have no working DNS at all, so
  # they are pointed at the same resolver the host uses.
  #
  # The one thing that does not carry over is the encryption: these queries
  # leave the container on plain port 53. Encrypting them too would mean
  # exposing resolved's stub on each podman bridge address
  # (`DNSStubListenerExtra`) and naming that address here - worth doing if the
  # containers ever resolve anything sensitive, but today it is package pulls
  # and this host's own names.
  virtualisation.containers.containersConf.settings.network.dns_servers = [
    "9.9.9.9"
    "149.112.112.112"
  ];
}
