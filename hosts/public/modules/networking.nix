{ hostConfig, ... }: {
	networking = {
		hostName = hostConfig.hostname;
		domain = "yesbutmaybe.no";
		networkmanager.enable = true;
		firewall = {
			enable = true;
			allowedTCPPorts = [
				25    # SMTP (inbound mail)
				80    # HTTP / ACME challenges
				443   # HTTPS
				587   # SMTP submission (mail clients)
				993   # IMAPS
				8080  # WordPress via Pangolin
				8081  # Roundcube webmail (byggogbedrag.no) via Pangolin
				8082  # Roundcube webmail (yesbutmaybe.no) via Pangolin
				3000  # petersson.coffee via Pangolin
				3001  # byggogbedrag.no via Pangolin
				9999  # Karoline's static site
				9100  # Prometheus node exporter
				4040  # Prometheus nginxlog exporter
			];
		};
		interfaces.${hostConfig.interface}.ipv4.addresses = [{
			address = hostConfig.ip;
			prefixLength = hostConfig.prefixLength;
		}];
		defaultGateway = hostConfig.gateway;
		nameservers = hostConfig.nameservers;
		# Required for local mail delivery (postfix/dovecot resolving own hostname)
		hosts = {
			"${hostConfig.ip}" = [ "mail.yesbutmaybe.no" hostConfig.hostname ];
		};
	};
}
