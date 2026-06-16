{ config, lib, pkgs, ... }:
{
	services.roundcube = {
		enable = true;
		hostName = "webmail.byggogbedrag.no";
		configureNginx = true;            # builds root + PHP fastcgi locations

		# Module has no imap/smtp option — point Roundcube at the mail server here.
		# mail.yesbutmaybe.no resolves to 10.0.10.10 locally (networking.nix `hosts`),
		# so the TLS cert validates on the loopback connection.
		extraConfig = ''
			$config['imap_host'] = 'ssl://mail.yesbutmaybe.no:993';
			$config['smtp_host'] = 'tls://mail.yesbutmaybe.no:587';
			$config['smtp_user'] = '%u';
			$config['smtp_pass'] = '%p';
		'';
	};

	# Turn the module's vhost into a plain-HTTP backend for Pangolin (Pangolin
	# terminates TLS for the public hostname). Defaults are mkDefault, so mkForce.
	services.nginx.virtualHosts."webmail.byggogbedrag.no" = {
		forceSSL   = lib.mkForce false;
		enableACME = lib.mkForce false;
		listen     = [{ addr = "0.0.0.0"; port = 8081; }];
	};
}
