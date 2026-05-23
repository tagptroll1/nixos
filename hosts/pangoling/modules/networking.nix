{ hostConfig, ... }: {
	networking = {
		hostName = hostConfig.hostname;
		domain = "yesbutmaybe.no";
		useDHCP = false;
		firewall = {
			enable = true;
			allowedTCPPorts = [
				22    # SSH
				80    # HTTP / ACME
				443   # HTTPS
			];
			# Netbird wireguard port; the module also opens this, but listed
			# explicitly here for clarity.
			allowedUDPPorts = [
				51820  # NetBird wireguard
				27015  # CS2 → forwarded to media (see forwarding.nix)
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
