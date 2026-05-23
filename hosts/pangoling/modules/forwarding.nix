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
	};
}
