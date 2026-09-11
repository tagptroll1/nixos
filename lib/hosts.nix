{
  private = {
    hostname = "private";
    interface = "ens18";
    ip = "10.0.20.5";
    gateway = "10.0.20.1";
    prefixLength = 24;
		nameservers = [ "8.8.8.8" "1.1.1.1" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  public = {
    hostname = "public";
    interface = "ens18";
    ip = "10.0.10.10";
    gateway = "10.0.10.1";
    prefixLength = 24;
		nameservers = [ "8.8.8.8" "1.1.1.1" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  media = {
    hostname = "media";
    interface = "ens18";
    ip = "10.2.10.10";
    gateway = "10.2.10.1";
    prefixLength = 24;
		nameservers = [ "9.9.9.9" "149.112.112.112" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  # Containers on home02, on the same Media subnet as the media VM so they
  # inherit its MikroTik isolation. `eth0` rather than `ens18`: Proxmox names
  # an LXC's interface eth0, and the CT's own network config is set to manual
  # so the address below is the only one.
  ocr = {
    hostname = "ocr";
    interface = "eth0";
    ip = "10.2.10.20";
    gateway = "10.2.10.1";
    prefixLength = 24;
		nameservers = [ "9.9.9.9" "149.112.112.112" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  immich = {
    hostname = "immich";
    interface = "eth0";
    ip = "10.2.10.21";
    gateway = "10.2.10.1";
    prefixLength = 24;
		nameservers = [ "9.9.9.9" "149.112.112.112" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  /*
    VLAN 230, alone on it.

    The only host in the estate that terminates a tunnel from the public
    internet. It holds no data: a proxy that serves shared photo links, and the
    tunnel client that publishes it. Its own segment because a tunnel client's
    real risk is not the tunnel - it is what the machine running it can reach
    if it is ever taken. From here that list is two entries, and the router
    enforces both.
  */
  share = {
    hostname = "share";
    interface = "eth0";
    ip = "10.2.30.10";
    gateway = "10.2.30.1";
    prefixLength = 24;
		nameservers = [ "9.9.9.9" "149.112.112.112" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  # Norwegian VPS: yesbutmaybe.no ingress (Pangolin) + outbound mail relay.
  pangolin = {
    hostname = "pangolin";
    interface = "ens18";
    ip = "193.200.238.206";
    gateway = "193.200.238.1";
    prefixLength = 24;
		# Anycast resolvers, both served from Oslo PoPs so answers stay
		# Norwegian. The ISP resolvers this list used to carry are not usable
		# off-net: measured from this VPS, 79.161.9.164 answered 4/8 queries,
		# 85.165.9.222 timed out and 94.127.122.231 was unreachable. glibc
		# walks the list on every miss, so lookups took 3-15s or failed
		# outright - which is what starved traefik's plugin download.
		nameservers = [ "1.1.1.1" "9.9.9.9" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };
}
