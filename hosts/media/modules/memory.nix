{ ... }:
{
  # This VM has a GPU passed through, so QEMU mlocks every page of its RAM on
  # home02: the host can neither swap nor reclaim any of it, and the host's own
  # 8 GB of swap is unreachable for it. Nothing configured in here changes that
  # - the host-side fix is a smaller allocation for the VM.
  #
  # What swap fixes is the guest's own failure mode. With none, a shortage in
  # here has nothing to reclaim: direct reclaim spins, the OOM killer is never
  # reached, and the machine stops answering instead of shedding one process.
  # systemd-oomd says so itself on every boot - "No swap; memory pressure usage
  # will be degraded".
  #
  # A file rather than zram, because zram takes its backing store out of the
  # same RAM that is under pressure. / has ~55 GB free.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192; # MiB
    }
  ];
}
