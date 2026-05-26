{ config, ... }: {
	mailserver = {
		enable = true;
		fqdn = "mail.yesbutmaybe.no";
		sendingFqdn = "mail.yesbutmaybe.no";
		domains = [ "yesbutmaybe.no" ];

		enableSubmission = true;
		enableSubmissionSsl = false; # 587 uses STARTTLS, not SSL

		stateVersion = 3;

		storage.path = "/var/vmail";
		dkim.keyDirectory = "/var/dkim";

		accounts = {
			"thomas@yesbutmaybe.no" = {
				hashedPasswordFile = config.sops.secrets."mail_hashed_password".path;
				aliases = [ "admin@yesbutmaybe.no" ];
				# Catch-all: any address @yesbutmaybe.no that isn't another
				# account or alias is delivered here.
				catchAll = [ "yesbutmaybe.no" ];
			};
			"grafana@yesbutmaybe.no" = {
				hashedPasswordFile = config.sops.secrets."mail_grafana_hashed_password".path;
			};
			"changes@yesbutmaybe.no" = {
				hashedPasswordFile = config.sops.secrets."mail_changes_hashed_password".path;
			};
		};

		x509.useACMEHost = "mail.yesbutmaybe.no";
	};

	# ACME cert for the mail server via Domeneshop DNS-01
	security.acme = {
		acceptTerms = true;
		defaults.email = "admin@yesbutmaybe.no";

		certs."mail.yesbutmaybe.no" = {
			domain = "mail.yesbutmaybe.no";
			dnsProvider = "domeneshop";
			credentialFiles = {
				"DOMENESHOP_API_TOKEN_FILE" = config.sops.secrets."domeneshop_api_token".path;
				"DOMENESHOP_API_SECRET_FILE" = config.sops.secrets."domeneshop_api_secret".path;
			};
		};
	};

	# Give mail services access to the ACME cert
	users.users.dovecot2.extraGroups = [ "acme" ];
	users.users.postfix.extraGroups  = [ "acme" ];

	services.postfix.settings.main = {
		relayhost = [ "[91.99.59.171]:587" ];
		mynetworks = [
			"127.0.0.0/8"
			"10.0.10.0/24"
			"10.0.20.0/24"  # private host — trusted relay, no auth needed
		];
		smtp_sasl_auth_enable = "no";
		myorigin = "yesbutmaybe.no";
		mydomain = "yesbutmaybe.no";
		myhostname = "mail.yesbutmaybe.no";
		masquerade_domains = [ "yesbutmaybe.no" ];
	};
}
