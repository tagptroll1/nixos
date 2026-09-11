{ ... }:
{
  # What swap fixes is this guest's own failure mode. With none, a shortage in
  # here has nothing to reclaim: direct reclaim spins, the OOM killer is never
  # reached, and the machine stops answering instead of shedding one process.
  # systemd-oomd says so itself on every boot - "No swap; memory pressure usage
  # will be degraded".
  #
  # A file rather than zram, because zram takes its backing store out of the
  # same RAM that is under pressure. / has ~55 GB free.
  #
  # home02 can also swap and reclaim this VM's pages on its own side, because
  # nothing is passed through to it any more - the GPU workloads live in
  # containers. Keep that in mind when sizing the VM: the guest-side pressure
  # this swapfile answers is now the only kind that is hard to see from the
  # host.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192; # MiB
    }
  ];
}
