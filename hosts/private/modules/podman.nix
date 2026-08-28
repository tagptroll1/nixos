{ pkgs, ... }: {
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;    # don't alias docker -> podman, be explicit
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.quadlet = {
    enable = true;

    # This is the reconciler: it re-pulls every container labelled
    # io.containers.autoupdate=registry, restarts the ones whose digest moved,
    # and rolls back by itself if the new image fails to start. CI pushing a
    # new image is therefore the whole deploy - no rebuild, no ssh.
    #
    # The timer comes from the podman package via systemd.packages; setting it
    # here goes through quadlet-nix, which applies it as a drop-in. Writing
    # systemd.timers.podman-auto-update by hand instead replaces the packaged
    # unit rather than adjusting it, which is how this host ended up with a
    # podman-auto-update.service that had no ExecStart at all.
    #
    # Hourly, not daily: the gap between a green build and the new version
    # being live is otherwise up to 24 hours, which makes the pipeline feel
    # broken when it is merely asleep.
    autoUpdate = {
      enable   = true;
      calendar = "hourly";
    };
  };

  # allow rootless containers to use low ports if ever needed
  # and ensure cgroup v2 is available for proper resource tracking
  boot.kernelParams = [ "systemd.unified_cgroup_hierarchy=1" ];

  environment.systemPackages = [ pkgs.podman ];
}
