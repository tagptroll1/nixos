# Pangolin: pangolin + gerbil + traefik as native systemd services. State
# (sqlite db with sites, resources, newt credentials) lives in
# /var/lib/pangolin/config/ — SERVER_SECRET must match the value the db was
# created with or its sessions and tokens are invalid.
{ config, lib, pkgs, ... }:
let
	# nixpkgs still ships 1.21.0. Drop this override once it catches up.
	# npmDeps has to be built by hand: buildNpmPackage resolves it from the
	# original arguments before mkDerivation runs, so overrideAttrs cannot
	# reach npmDepsHash. postPatch is cleared because it rewrites APP_VERSION
	# from the majorMinor.0 form upstream used to leave in consts.ts, and
	# 1.21.1 already sets the real version there - its --replace-fail would
	# abort the build.
	pangolinPkg = pkgs.fosrl-pangolin.overrideAttrs (finalAttrs: _: {
		version = "1.21.1";
		src = pkgs.fetchFromGitHub {
			owner = "fosrl";
			repo  = "pangolin";
			tag   = finalAttrs.version;
			hash  = "sha256-zfXHev0bN3KVkoiSQ+2WQCgmcCtWi3dib6EiaYmthTo=";
		};
		npmDeps = pkgs.fetchNpmDeps {
			inherit (finalAttrs) src;
			name = "pangolin-${finalAttrs.version}-npm-deps";
			# Must equal npmDepsFetcherVersion in the package, or the npm
			# config hook rejects the prefetched tree.
			fetcherVersion = finalAttrs.npmDepsFetcherVersion;
			hash = "sha256-9wPn2nSD9VxMyHywrG52WrChsrJ/ctnKGlMZZEymP6A=";
		};
		postPatch = "";
	});
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
		package = pangolinPkg;
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

	# The launcher refreshes the prebuilt frontend with
	#   test -f .next/.nix_skip_setup || { rm -rf .next && cp -rd <store>/.next .; }
	# and `cp -rd` keeps the store's read-only directory modes. A file cannot be
	# removed without write permission on its parent, so the next start's
	# `rm -rf` fails, `&&` short-circuits, the copy is skipped and the new
	# server code runs against the previous version's .next — which crashes in
	# createNextServer and takes the dashboard down while the API stays up.
	# Restoring the write bit before the launcher runs keeps upgrades working.
	systemd.services.pangolin.preStart = lib.mkAfter ''
		if [ -d /var/lib/pangolin/.next ]; then
			chmod -R u+w /var/lib/pangolin/.next
		fi
	'';

	networking.firewall = {
		allowedTCPPorts = rawTcpPorts;
		allowedUDPPorts = rawUdpPorts;
	};

	# The traefik module only defines web/websecure; raw resources need their
	# ports declared statically.
	services.traefik.staticConfigOptions = {
		entryPoints = lib.listToAttrs
			(map (entryPoint "tcp") rawTcpPorts ++ map (entryPoint "udp") rawUdpPorts);

		# Badger version upstream pairs with pangolin 1.20.x-1.21.x, per
		# config/traefik/traefik_config.yml in the pangolin repo. The nixpkgs
		# module default lags. A version traefik cannot fetch makes every http
		# router 404, so this must track the running pangolin.
		experimental.plugins.badger.version = lib.mkForce "v1.4.1";

		# Proxied targets with self-signed certs (https upstreams) need this.
		serversTransport.insecureSkipVerify = true;
	};
}
