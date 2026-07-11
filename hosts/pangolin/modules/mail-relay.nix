# Outbound smarthost for yesbutmaybe.no. Own devices and services (public
# host, home LAN, workstations) authenticate with SASL on 587 and relay to
# the world from this box's IP. Mail addressed to yesbutmaybe.no is handed to
# the traefik raw TCP resource on localhost:25, which tunnels it to the
# public host's mailserver. Port 25 inbound is traefik's, not postfix's.
{ config, ... }:
let
	fqdn = "relay.yesbutmaybe.no";
	certDir = config.security.acme.certs.${fqdn}.directory;
in {
	security.acme = {
		acceptTerms = true;
		defaults.email = "admin@yesbutmaybe.no";

		certs.${fqdn} = {
			dnsProvider = "domeneshop";
			credentialFiles = {
				"DOMENESHOP_API_TOKEN_FILE" = config.sops.secrets."domeneshop_api_token".path;
				"DOMENESHOP_API_SECRET_FILE" = config.sops.secrets."domeneshop_api_secret".path;
			};
		};
	};
	users.users.postfix.extraGroups = [ "acme" ];

	# Cyrus SASL backend for smtpd; accounts live in /etc/sasldb2 (managed
	# with `saslpasswd2 -c -u yesbutmaybe.no <user>`, root:postfix 0640).
	environment.etc."postfix/sasl/smtpd.conf".text = ''
		pwcheck_method: auxprop
		auxprop_plugin: sasldb
		mech_list: PLAIN LOGIN
	'';

	services.postfix = {
		enable = true;

		# No smtpd on port 25 — that port belongs to traefik. Submission (587)
		# is the only listener.
		enableSmtp = false;
		enableSubmission = true;

		submissionOptions = {
			smtpd_sasl_auth_enable = "yes";
			smtpd_sasl_security_options = "noanonymous";
			smtpd_tls_security_level = "encrypt";
			smtpd_client_restrictions = "permit_sasl_authenticated,reject";
			smtpd_relay_restrictions = "permit_sasl_authenticated,reject";
			smtpd_sender_restrictions = "reject_unknown_sender_domain";
		};

		transport = "yesbutmaybe.no    smtp:[127.0.0.1]:25";

		settings = {
			# enableSmtp = false also drops the smtp/relay delivery agents from
			# master.cf; outbound delivery needs them back.
			master = {
				smtp = { };
				relay = {
					command = "smtp";
					args = [ "-o" "smtp_fallback_relay=" ];
				};
			};

			main = {
				myhostname = fqdn;
				smtp_helo_name = fqdn;
				inet_protocols = "ipv4";
				relay_domains = [ "yesbutmaybe.no" ];
				# Only loopback; every remote sender authenticates with SASL.
				# Never add device or LAN IPs here — IP trust with our domain
				# reputation is how open relays happen.
				mynetworks = [ "127.0.0.0/8" ];
				cyrus_sasl_config_path = "/etc/postfix/sasl";
				smtpd_helo_required = true;
				smtpd_helo_restrictions = [
					"permit_mynetworks"
					"reject_invalid_helo_hostname"
					"reject_non_fqdn_helo_hostname"
				];
				smtpd_tls_chain_files = [
					"${certDir}/key.pem"
					"${certDir}/fullchain.pem"
				];
				smtp_tls_security_level = "may";
			};
		};
	};
}
