# Pangolin: pangolin + gerbil + traefik as native systemd services. State
# (sqlite db with sites, resources, newt credentials) lives in
# /var/lib/pangolin/config/ — SERVER_SECRET must match the value the db was
# created with or its sessions and tokens are invalid.
{ config, lib, ... }:
let
	# Ports for the raw TCP/UDP resources in the Pangolin database (mail +
	# game servers). Each one becomes a traefik entryPoint named tcp-N/udp-N
	# (the names Pangolin's dynamic traefik config references) and a firewall
	# opening, so a port only ever needs to be added here.
	rawTcpPorts = [
		25    # SMTP in → tunnel → public host
		993   # IMAPS → tunnel → public host
	];
	rawUdpPorts = [
		27015 # CS2 → media
		34197 # Factorio → media
		8211  # Palworld → media
	];
	entryPoint = proto: port:
		lib.nameValuePair "${proto}-${toString port}"
			{ address = ":${toString port}/${proto}"; };
in {
	sops.templates."pangolin.env".content = ''
		SERVER_SECRET=${config.sops.placeholder."pangolin-server-secret"}
	'';

	services.pangolin = {
		enable = true;
		baseDomain = "yesbutmaybe.no";
		dashboardDomain = "pangolin.yesbutmaybe.no";
		# Must stay the email of the ACME account stored in
		# /var/lib/pangolin/config/letsencrypt/acme.json.
		letsEncryptEmail = "thomas@petersson.priv.no";
		environmentFile = config.sops.templates."pangolin.env".path;

		# Merged on top of the module's defaults (ports 3000-3003, dashboard
		# url, disable_signup_without_invite).
		settings = {
			app.log_level = "info";
			domains.domain1.cert_resolver = "letsencrypt";
			server.cors = {
				origins = [ "https://${config.services.pangolin.dashboardDomain}" ];
				methods = [ "GET" "POST" "PUT" "DELETE" "PATCH" ];
				allowed_headers = [ "X-CSRF-Token" "Content-Type" ];
				credentials = false;
			};
			gerbil.start_port = 51820;
			flags = {
				require_email_verification = false;
				disable_user_create_org = false;
				allow_raw_resources = true;
			};
		};
	};

	networking.firewall = {
		allowedTCPPorts = rawTcpPorts;
		allowedUDPPorts = rawUdpPorts;
	};

	# The traefik module only defines web/websecure; raw resources need their
	# ports declared statically.
	services.traefik.staticConfigOptions = {
		entryPoints = lib.listToAttrs
			(map (entryPoint "tcp") rawTcpPorts ++ map (entryPoint "udp") rawUdpPorts);

		# Badger version paired with pangolin 1.18.x (module default lags).
		experimental.plugins.badger.version = lib.mkForce "v1.3.1";

		# Proxied targets with self-signed certs (https upstreams) need this.
		serversTransport.insecureSkipVerify = true;
	};
}
