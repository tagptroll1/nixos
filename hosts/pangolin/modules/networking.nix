{ hostConfig, ... }: {
	networking = {
		hostName = hostConfig.hostname;
		domain = "yesbutmaybe.no";
		useDHCP = false;
		# Raw TCP/UDP resource ports (mail, game servers) are opened in
		# modules/pangolin.nix next to their traefik entryPoints.
		firewall = {
			enable = true;
			allowedTCPPorts = [
				22    # SSH
				80    # HTTP / ACME challenges
				443   # HTTPS / dashboard / proxied resources
				587   # Submission (postfix smarthost for own devices/services)
			];
			allowedUDPPorts = [
				51820 # Gerbil wireguard (newt site tunnels)
				21820 # Gerbil relay port
			];
		};
		interfaces.${hostConfig.interface}.ipv4.addresses = [{
			address = hostConfig.ip;
			prefixLength = hostConfig.prefixLength;
		}];
		defaultGateway = {
			address = hostConfig.gateway;
			interface = hostConfig.interface;
		};
		nameservers = hostConfig.nameservers;
	};
}
