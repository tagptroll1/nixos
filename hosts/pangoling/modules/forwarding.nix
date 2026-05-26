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
			{
				# Factorio server on media (FSM container)
				proto = "udp";
				sourcePort = 34197;
				destination = "100.122.55.95:34197";
			}
		];

		# Source-NAT forwarded traffic to media so reply packets come back
		# through pangoling instead of media's default gateway (otherwise
		# the client never sees the response and the connection times out).
		#
		# Also hairpin-DNAT for traffic arriving via wt0: a netbird client
		# using pangoling as exit/relay routes traffic to pangoling's public
		# IP through the overlay, so packets land on wt0 not ens18 and the
		# networking.nat-generated -i ens18 PREROUTING rule never fires.
		# `--dst-type LOCAL` scopes it to packets actually destined for
		# pangoling itself (any local IP), so overlay → overlay traffic for
		# other hosts is untouched.
		extraCommands = ''
			iptables -t nat -A POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 27015 -j MASQUERADE
			iptables -t nat -A PREROUTING -i wt0 -p udp --dport 27015 -m addrtype --dst-type LOCAL -j DNAT --to-destination 100.122.55.95:27015
			iptables -t nat -A POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 34197 -j MASQUERADE
			iptables -t nat -A PREROUTING -i wt0 -p udp --dport 34197 -m addrtype --dst-type LOCAL -j DNAT --to-destination 100.122.55.95:34197
		'';
		extraStopCommands = ''
			iptables -t nat -D POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 27015 -j MASQUERADE || true
			iptables -t nat -D PREROUTING -i wt0 -p udp --dport 27015 -m addrtype --dst-type LOCAL -j DNAT --to-destination 100.122.55.95:27015 || true
			iptables -t nat -D POSTROUTING -o wt0 -d 100.122.55.95 -p udp --dport 34197 -j MASQUERADE || true
			iptables -t nat -D PREROUTING -i wt0 -p udp --dport 34197 -m addrtype --dst-type LOCAL -j DNAT --to-destination 100.122.55.95:34197 || true
		'';
	};
}
