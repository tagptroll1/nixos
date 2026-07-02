{ config, lib, pkgs, ... }:

# Second Roundcube frontend for yesbutmaybe.no, served on its own hostname
# (webmail.yesbutmaybe.no) with its own nginx vhost and php-fpm pool. The
# services.roundcube module (webmail.byggogbedrag.no) is a singleton, so this
# is hand-rolled — but it reuses that instance's postgres db, /etc/roundcube
# config and des_key instead of spinning up a second database. Consequence:
# both webmail URLs share the same roundcube accounts/contacts/settings. Fine
# for a single user; both point at the same mail.yesbutmaybe.no server anyway.

let
	hostName  = "webmail.yesbutmaybe.no";
	port      = 8082;                       # plain-HTTP backend for Pangolin
	maxAttach = "25M";

	php = pkgs.php84;
	fpm = config.services.phpfpm.pools.roundcube-ybmn;
in
{
	# Plain-HTTP vhost — Pangolin terminates TLS for the public hostname and
	# forwards to this port. Mirrors the byggogbedrag roundcube vhost. Reuses the
	# roundcube package root, so it reads the same /etc/roundcube/config.inc.php.
	services.nginx = {
		enable = true;
		virtualHosts.${hostName} = {
			listen = [{ addr = "0.0.0.0"; inherit port; }];
			root = config.services.roundcube.package + "/public_html";
			locations."/" = {
				index = "index.php";
				priority = 1100;
				extraConfig = ''
					add_header Cache-Control 'public, max-age=604800, must-revalidate';
				'';
			};
			locations."~* \\.php(/|$)" = {
				priority = 3130;
				extraConfig = ''
					fastcgi_pass unix:${fpm.socket};
					fastcgi_param PATH_INFO $fastcgi_path_info;
					fastcgi_split_path_info ^(.+\.php)(/.+)$;
					include ${config.services.nginx.package}/conf/fastcgi.conf;

					client_max_body_size ${maxAttach};
				'';
			};
		};
	};

	# Own php-fpm pool for process/log isolation. Runs as the existing `roundcube`
	# user so postgres peer auth + reading /var/lib/roundcube/des_key both work.
	services.phpfpm.pools.roundcube-ybmn = {
		user = "roundcube";
		phpPackage = php;
		phpOptions = ''
			error_log = '/dev/stderr'
			log_errors = on
			post_max_size = ${maxAttach}
			upload_max_filesize = ${maxAttach}
		'';
		settings = lib.mapAttrs (_: lib.mkDefault) {
			"listen.owner" = config.services.nginx.user;
			"listen.group" = config.services.nginx.group;
			"listen.mode" = "0660";
			"pm" = "dynamic";
			"pm.max_children" = 75;
			"pm.start_servers" = 2;
			"pm.min_spare_servers" = 1;
			"pm.max_spare_servers" = 20;
			"pm.max_requests" = 500;
			"catch_workers_output" = true;
		};
	};

	# Wait for the byggogbedrag instance's setup (db init + des_key) before starting.
	systemd.services.phpfpm-roundcube-ybmn.after = [ "roundcube-setup.service" ];
}
