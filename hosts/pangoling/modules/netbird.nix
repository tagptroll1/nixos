# NetBird overlay client. After first boot, log in once with:
#   sudo netbird up --setup-key <KEY>
# (or `sudo netbird up` for SSO browser flow). Credentials are stored under
# /var/lib/netbird and survive rebuilds.
#
# To use this host as an exit-node / relay for other peers, enable that
# in the NetBird management dashboard once the peer is registered — no
# extra NixOS config is required beyond IP forwarding below.
{ ... }: {
	services.netbird.enable = true;

	# Required if this peer should forward traffic for other peers
	# (exit node / routing peer).
	boot.kernel.sysctl = {
		"net.ipv4.ip_forward" = 1;
		"net.ipv6.conf.all.forwarding" = 1;
	};
}
