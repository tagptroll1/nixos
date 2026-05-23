# Public UDP/TCP port-forwards from pangoling's public IP into peers on the
# NetBird overlay (wt0). NetBird's built-in ingress-ports API is cloud-only,
# so we DNAT manually.
{ ... }: {
	networking.nat = {
		enable = true;
		externalInterface = "ens18";
		internalInterfaces = [ "wt0" ];
		forwardPorts = [
			{
				# CS2 / Source game server on media
				proto = "udp";
				sourcePort = 27015;
				destination = "100.122.55.95:27015";
			}
		];

		# Source-NAT forwarded traffic to media so reply packets come back
		# through pangoling instead of media's default gateway (otherwise
		# the client never sees the response and the connection times out).
		extraCommands = ''
			iptables -t nat -A POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 27015 -j MASQUERADE
		'';
		extraStopCommands = ''
			iptables -t nat -D POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 27015 -j MASQUERADE || true
		'';
	};
}
