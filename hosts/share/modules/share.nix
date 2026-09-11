{ ... }: {
  /*
    The only public door into the photo library, and the whole reason this host
    exists separately from the one holding the photos.

    The path, end to end:

      internet -> pangolin.yesbutmaybe.no (VPS, traefik)
               -> newt tunnel (outbound from here, nothing inbound)
               -> 127.0.0.1:3000, immich-public-proxy
               -> 10.2.10.21:2283, immich's API, for that share only

    immich-public-proxy serves shared links and nothing else: it holds no API
    key, has no session, and cannot enumerate anything the link does not name.
    So the worst case if this container is taken is an attacker on a machine
    with no photos, no credentials beyond the tunnel's own, and network reach
    to exactly one port on one address - which the router enforces, because
    this host is alone on VLAN 230.

    Turning the share off is `pct stop 207`. Nothing else notices.
  */
  services.immich-public-proxy = {
    enable = true;

    # Across the subnet to the immich container. That hop is the one thing
    # this host is allowed to do internally; immich's own firewall accepts
    # 2283 from this address alone.
    immichUrl = "http://10.2.10.21:2283";

    # The module has no bind-address option, so IPP listens on all interfaces.
    # What keeps it private is the host firewall: 3000 is never opened, and
    # newt reaches it over loopback from this same machine. Leaving
    # openFirewall false is therefore load-bearing, not tidiness.
    port = 3000;
    openFirewall = false;
  };
}
