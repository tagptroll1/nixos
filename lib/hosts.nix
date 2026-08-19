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
		nameservers = [ "1.1.1.1" "8.8.8.8" ];

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
