{ pkgs, ... }: {
  services.immich = {
    enable = true;

    # All interfaces, because two different callers need it: Caddy on loopback
    # here (caddy.nix, the LAN and tailnet door) and the share container across
    # the subnet (the public shared-link path). The firewall rule at the bottom
    # is what keeps "across the subnet" down to that one address.
    host = "0.0.0.0";
    port = 2283;

    # Managed Postgres + Redis (defaults). Postgres 16 is required while
    # pgvecto.rs is still enabled — VectorChord is also enabled in parallel
    # for the 25.11+ migration path.
    database.enable = true;
    redis.enable = true;

    # The nixpkgs immich-machine-learning is built against CPU-only
    # onnxruntime, so it can't use the GTX 1070. We run the upstream
    # CUDA image in a container instead (see oci-containers below).
    # The immich server already points at http://localhost:3003 by default —
    # which is why all of immich lives here rather than the server staying on
    # the media VM: that URL is hardcoded in the nixpkgs module.
    machine-learning.enable = false;

    # Whitelist NVIDIA device nodes for the immich-server itself (NVENC
    # transcoding). PrivateDevices stays enabled. The nodes are handed to this
    # container by the CT config on home02; the driver userspace comes from
    # shared/modules/nvidia-userspace.nix.
    accelerationDevices = [
      "/dev/nvidia0"
      "/dev/nvidiactl"
      "/dev/nvidia-uvm"
      "/dev/nvidia-uvm-tools"
      "/dev/nvidia-modeset"
    ];

    settings = null;
  };

  # Pin the in-container immich uid/gid to home02's tagp (uid=1001, gid=1001).
  # The photo datasets are bind-mounted from the host with an idmap that maps
  # this uid straight through, so new files written by Immich appear owned by
  # `tagp` on home02 - which is what the ZFS cloud backup and every other tool
  # on the host expect.
  # Multi-user note: when karoline is added, her photos will also be
  # owned by tagp on the host because the idmap maps a single uid per
  # mountpoint. Revisit (per-mount idmap or shared `family` group)
  # once she has her own dataset routing.
  users.users.immich.uid = 1001;
  users.groups.immich.gid = 1001;

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # The ML container has its own network namespace, where the resolved stub at
  # 127.0.0.53 is its own loopback and answers nothing - so it is pointed at
  # the same resolver the host uses. It needs working DNS for exactly one
  # thing: fetching model weights on first run.
  virtualisation.containers.containersConf.settings.network.dns_servers = [
    "9.9.9.9"
    "149.112.112.112"
  ];

  # NVIDIA CDI for GPU access from podman. The container runtime needs the
  # driver libraries mounted into the ML container, and it takes them from
  # hardware.nvidia.package - set in shared/modules/nvidia-userspace.nix, which
  # is also why the assertion below is suppressed: that module deliberately
  # never activates hardware.nvidia's config block, because there is no kernel
  # module to build in here.
  hardware.nvidia-container-toolkit = {
    enable = true;
    suppressNvidiaDriverAssertion = true;
  };

  # Upstream CUDA-enabled ML image, pinned to the same version as the
  # server package so client/server protocol stays in sync.
  virtualisation.oci-containers.containers.immich-machine-learning = {
    image = "ghcr.io/immich-app/immich-machine-learning:v${pkgs.immich.version}-cuda";
    ports = [ "127.0.0.1:3003:3003" ];
    volumes = [ "immich-ml-cache:/cache" ];
    extraOptions = [ "--device=nvidia.com/gpu=all" ];
  };

  # Same shape as the rule in ocr.nix: the port is not opened generally, one
  # source address is let through. 10.2.30.10 is the share container - alone on
  # VLAN 230, holding nothing but immich-public-proxy and its newt tunnel. That
  # is the entire public path into this API, and it is the only host on any
  # network permitted to open 2283.
  #
  # The LAN and tailnet reach immich through Caddy on this host instead, over
  # loopback, so they need no rule here.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 10.2.30.10 -p tcp --dport 2283 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -s 10.2.30.10 -p tcp --dport 2283 -j nixos-fw-accept || true
  '';
}
