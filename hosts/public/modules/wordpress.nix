{ config, pkgs, ... }:

let
	webRoot       = "/var/www";
	wordpressRoot = "${webRoot}/wordpress";

	# Must-use plugin — always loaded, not disableable from WP admin.
	# Managed by Nix; symlinked into wp-content/mu-plugins/ via tmpfiles.
	hardeningPlugin = pkgs.writeText "sps-security-hardening.php" ''
		<?php
		/**
		 * Security hardening — managed by NixOS, do not edit manually.
		 */

		// Genericise login error messages to prevent username enumeration.
		// WordPress normally says "the password for username X is wrong" which
		// confirms whether a username exists. This replaces all login errors with
		// a single neutral message.
		add_filter( 'login_errors', function() {
			return 'Feil brukernavn eller passord.';
		} );

		// Remove WordPress version from asset query strings (?ver=x.y.z) and
		// from the <meta name="generator"> tag in <head>.
		remove_action( 'wp_head', 'wp_generator' );
		add_filter( 'style_loader_src',  fn( $src ) => remove_query_arg( 'ver', $src ), 9999 );
		add_filter( 'script_loader_src', fn( $src ) => remove_query_arg( 'ver', $src ), 9999 );
	'';

	phpHandler = ''
		fastcgi_pass  unix:${config.services.phpfpm.pools.wordpress.socket};
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_hide_header X-Powered-By;
		include       ${pkgs.nginx}/conf/fastcgi_params;
	'';
in
{
	# ── Database ───────────────────────────────────────────────────────────────
	services.mysql = {
		enable  = true;
		package = pkgs.mariadb;
		# Local sockets and loopback only. WordPress connects as 'localhost',
		# which mysqli resolves to the unix socket, so nothing needs the network
		# listener — and an unbound listener would put the database one firewall
		# rule away from the LAN.
		settings.mysqld.bind-address = "127.0.0.1";
		ensureDatabases = [ "wordpress" ];
		ensureUsers = [{
			name = "wordpress";
			ensurePermissions = {
				"wordpress.*" = "ALL PRIVILEGES";
			};
		}];
	};

	# ── PHP-FPM ────────────────────────────────────────────────────────────────
	# The pool runs as its own user, not as nginx. Sharing the nginx account
	# means any WordPress bug reads whatever nginx can — every other vhost's
	# files, and every group nginx belongs to. The socket stays nginx-owned so
	# the webserver can still talk to it.
	users.users.wordpress = {
		isSystemUser = true;
		group        = "wordpress";
	};
	users.groups.wordpress = { };

	services.phpfpm.pools.wordpress = {
		user  = "wordpress";
		group = "wordpress";
		settings = {
			"listen.owner"         = "nginx";
			"listen.group"         = "nginx";
			"listen.mode"          = "0660";
			"pm"                   = "dynamic";
			"pm.max_children"      = 10;
			"pm.start_servers"     = 2;
			"pm.min_spare_servers" = 1;
			"pm.max_spare_servers"        = 3;
			"php_admin_value[expose_php]" = "Off";
		};
		phpPackage = pkgs.php83.buildEnv {
			extensions = ({ enabled, all }: enabled ++ (with all; [
				mysqli pdo_mysql curl gd mbstring xml zip opcache
			]));
		};
	};

	# ── Nginx virtual hosts ────────────────────────────────────────────────────
	services.nginx.enable = true;

	# Custom log format with request_time for Prometheus nginxlog exporter.
	# $http_x_forwarded_for is logged alongside $remote_addr: the WP vhosts sit
	# behind the Pangolin tunnel, so without it every client reads 10.0.10.10.
	# Keep the format in sync with exporters.nix.
	services.nginx.commonHttpConfig = ''
		log_format wordpress_combined '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_time "$http_x_forwarded_for"';
	'';

	# Internal WordPress interface (exposed via Pangolin tunnel on port 8080)
	services.nginx.virtualHosts."wordpress-pangolin" = {
		listen = [{ addr = "0.0.0.0"; port = 8080; }];
		root   = wordpressRoot;

		extraConfig = ''
			server_tokens off;
			add_header X-Frame-Options "SAMEORIGIN" always;
			add_header X-Content-Type-Options "nosniff" always;
			add_header X-XSS-Protection "0" always;
			add_header Referrer-Policy "strict-origin-when-cross-origin" always;
			add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
			add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
			access_log /var/log/nginx/wordpress_access.log wordpress_combined;

			# Every request arrives from the tunnel, so the connection address is
			# always 10.0.10.10. Trust that one hop's X-Forwarded-For so
			# $remote_addr - and WordPress's own session/IP records - hold the
			# real client.
			set_real_ip_from 10.0.10.10;
			real_ip_header X-Forwarded-For;
			real_ip_recursive on;

			# wp2shell (CVE-2026-63030): the REST batch endpoint runs sub-requests
			# under the wrong handler, which chains into unauthenticated admin
			# creation. Reachable as a path and as a rest_route query arg - block
			# both. Nothing on this site batches REST calls.
			if ($args ~* "batch(/|%2f)v1") { return 403; }
		'';

		locations."/" = {
			index       = "index.php";
			extraConfig = "try_files $uri $uri/ /index.php?$args;";
		};

		locations."~ \\.php$" = {
			extraConfig = phpHandler;
		};

		locations."~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$" = {
			extraConfig = "expires max; log_not_found off;";
		};

		# Administration happens over admin.sletteposten.no from the LAN, so the
		# public side needs neither the login form nor /wp-admin. admin-ajax.php
		# is the exception: themes and plugins call it from the frontend, and an
		# exact-match location outranks the ^~ prefix below.
		locations."= /wp-admin/admin-ajax.php" = { extraConfig = phpHandler; };
		locations."^~ /wp-admin/"                                           = { extraConfig = "deny all;"; };
		locations."= /wp-login.php"                                         = { extraConfig = "deny all;"; };

		locations."~ ^/wp-json/batch/"                                      = { extraConfig = "deny all;"; };
		locations."= /xmlrpc.php"                                           = { extraConfig = "deny all;"; };
		locations."= /wp-cron.php"                                          = { extraConfig = "deny all;"; };
		locations."~ ^/wp-json/wp/v2/users"                                 = { extraConfig = "deny all;"; };
		locations."~* /wp-sitemap-users"                                    = { extraConfig = "deny all;"; };
		locations."~* ^/(readme|license|wp-config-sample)\\.(html|txt|php)$" = { extraConfig = "deny all;"; };
		locations."= /wp-config.php"                                        = { extraConfig = "deny all;"; };
		locations."~ /\\."                                                   = { extraConfig = "deny all;"; };
		locations."~* /wp-content/uploads/.*\\.php$"                        = { extraConfig = "deny all;"; };
		locations."~* ^/wp-includes/.*\\.php$"                              = { extraConfig = "deny all;"; };
	};

	# LAN admin interface — HTTPS direct access via local DNS
	services.nginx.virtualHosts."admin.sletteposten.no" = {
		onlySSL = true;
		listen  = [{ addr = "0.0.0.0"; port = 443; ssl = true; }];
		root    = wordpressRoot;

		useACMEHost = "admin.sletteposten.no";

		extraConfig = ''
			server_tokens off;
			add_header X-Frame-Options "SAMEORIGIN" always;
			add_header X-Content-Type-Options "nosniff" always;
			add_header X-XSS-Protection "0" always;
			add_header Referrer-Policy "strict-origin-when-cross-origin" always;
			add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
			add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

			# wp2shell (CVE-2026-63030) - see the note on the tunnel vhost.
			if ($args ~* "batch(/|%2f)v1") { return 403; }
		'';

		locations."/" = {
			index       = "index.php";
			extraConfig = "try_files $uri $uri/ /index.php?$args;";
		};

		locations."~ \\.php$" = {
			extraConfig = phpHandler;
		};

		locations."~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$" = {
			extraConfig = "expires max; log_not_found off;";
		};

		locations."~ ^/wp-json/batch/"                                      = { extraConfig = "deny all;"; };
		locations."= /xmlrpc.php"                                           = { extraConfig = "deny all;"; };
		locations."~* ^/(readme|license|wp-config-sample)\\.(html|txt|php)$" = { extraConfig = "deny all;"; };
		locations."= /wp-config.php"                                        = { extraConfig = "deny all;"; };
		locations."~ /\\."                                                   = { extraConfig = "deny all;"; };
		locations."~* /wp-content/uploads/.*\\.php$"                        = { extraConfig = "deny all;"; };
		locations."~* ^/wp-includes/.*\\.php$"                              = { extraConfig = "deny all;"; };
	};

	# ACME cert for the WordPress admin panel
	security.acme.certs."admin.sletteposten.no" = {
		domain = "admin.sletteposten.no";
		dnsProvider = "domeneshop";
		credentialFiles = {
			"DOMENESHOP_API_TOKEN_FILE" = config.sops.secrets."domeneshop_api_token".path;
			"DOMENESHOP_API_SECRET_FILE" = config.sops.secrets."domeneshop_api_secret".path;
		};
		# Owned by nginx directly, so nginx needs no membership in the acme group.
		# Group membership there would also grant read on mail.yesbutmaybe.no's
		# private key, which belongs to postfix and dovecot, not the webserver.
		group = "nginx";
	};

	# ── Directory setup ────────────────────────────────────────────────────────
	systemd.tmpfiles.rules = [
		"d  ${wordpressRoot}                              0755 wordpress wordpress - -"
		"d  ${wordpressRoot}/wp-content/mu-plugins        0755 wordpress wordpress - -"
		"L+ ${wordpressRoot}/wp-content/mu-plugins/sps-security-hardening.php - - - - ${hardeningPlugin}"
	];

	# ── One-shot WordPress deploy service ──────────────────────────────────────
	systemd.services."setup-wordpress" = {
		description = "Deploy WordPress core and Daily News Blog theme";
		after       = [ "network-online.target" "mysql.service" ];
		wants       = [ "network-online.target" ];
		wantedBy    = [ "multi-user.target" ];

		# Only runs if wp-config.php doesn't exist yet
		unitConfig.ConditionPathExists = "!${wordpressRoot}/wp-config.php";

		path = with pkgs; [ curl gnutar gzip unzip coreutils gnused gawk ];

		serviceConfig = {
			Type            = "oneshot";
			User            = "wordpress";
			Group           = "wordpress";
			RemainAfterExit = true;
			PrivateTmp      = true;
		};

		script = ''
			set -e
			WP_DIR="${wordpressRoot}"

			echo "Downloading WordPress core..."
			curl -fsSL https://wordpress.org/latest.tar.gz \
				| tar -xz --strip-components=1 -C "$WP_DIR"

			echo "Downloading Minimalistix parent theme..."
			curl -fsSL "https://downloads.wordpress.org/theme/minimalistix.latest-stable.zip" \
				-o /tmp/minimalistix.zip
			unzip -q /tmp/minimalistix.zip -d "$WP_DIR/wp-content/themes/"
			rm /tmp/minimalistix.zip

			echo "Downloading Daily News Blog theme..."
			curl -fsSL "https://downloads.wordpress.org/theme/daily-news-blog.latest-stable.zip" \
				-o /tmp/daily-news-blog.zip
			unzip -q /tmp/daily-news-blog.zip -d "$WP_DIR/wp-content/themes/"
			rm /tmp/daily-news-blog.zip

			cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"
			sed -i "s/database_name_here/wordpress/" "$WP_DIR/wp-config.php"
			sed -i "s/username_here/wordpress/"       "$WP_DIR/wp-config.php"
			sed -i "s/password_here//"                "$WP_DIR/wp-config.php"

			# Replace the sample's placeholder secret keys with real ones — the
			# placeholders are publicly known, which makes auth cookies forgeable.
			SALTS=$(mktemp)
			curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ -o "$SALTS"
			awk -v salts="$SALTS" '
				/put your unique phrase here/ {
					if (!done) { while ((getline l < salts) > 0) print l; done = 1 }
					next
				}
				{ print }
			' "$WP_DIR/wp-config.php" > "$WP_DIR/wp-config.php.new"
			mv "$WP_DIR/wp-config.php.new" "$WP_DIR/wp-config.php"
			rm "$SALTS"

			# Disable built-in HTTP cron (use systemd timer instead)
			sed -i "/require_once.*wp-settings\.php/i\\define( 'DISABLE_WP_CRON', true );" "$WP_DIR/wp-config.php"

			# Multi-domain URL detection (Pangolin + direct LAN access), restricted
			# to known hosts — trusting HTTP_HOST blindly enables password-reset
			# poisoning via a spoofed Host header.
			URLCFG=$(mktemp)
			cat > "$URLCFG" <<-'EOF'

				/* Multi-domain URL detection — whitelisted hosts only */
				$sps_allowed_hosts = array( 'sletteposten.no', 'www.sletteposten.no', 'admin.sletteposten.no' );
				if ( isset( $_SERVER['HTTP_HOST'] ) && in_array( $_SERVER['HTTP_HOST'], $sps_allowed_hosts, true ) ) {
				    $scheme = ( ! empty( $_SERVER['HTTPS'] ) && $_SERVER['HTTPS'] !== 'off' )
				              || ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] )
				                   && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' )
				              ? 'https' : 'http';
				    define( 'WP_HOME',    $scheme . '://' . $_SERVER['HTTP_HOST'] );
				    define( 'WP_SITEURL', $scheme . '://' . $_SERVER['HTTP_HOST'] );
				} else {
				    define( 'WP_HOME',    'https://sletteposten.no' );
				    define( 'WP_SITEURL', 'https://sletteposten.no' );
				}
			EOF
			awk -v cfg="$URLCFG" '
				/require_once.*wp-settings\.php/ && !done {
					while ((getline l < cfg) > 0) print l
					print ""
					done = 1
				}
				{ print }
			' "$WP_DIR/wp-config.php" > "$WP_DIR/wp-config.php.new"
			mv "$WP_DIR/wp-config.php.new" "$WP_DIR/wp-config.php"
			rm "$URLCFG"

			find "$WP_DIR" -type d -exec chmod 755 {} \;
			find "$WP_DIR" -type f -exec chmod 644 {} \;
			# DB creds + secret keys — keep away from other local users
			chmod 640 "$WP_DIR/wp-config.php"

			echo "WordPress setup complete."
		'';
	};

	# ── WordPress cron via systemd timer (replaces wp-cron HTTP access) ────────
	# wp-cli runs the due hooks in-process, so cron does not depend on nginx,
	# php-fpm, DNS or TLS being healthy, and a broken run exits non-zero. Driving
	# it over HTTP hides failures instead: curl reports success for a 502, so the
	# queue can stall indefinitely while the unit stays green.
	systemd.services."wp-cron" = {
		description = "WordPress scheduled tasks";
		after       = [ "mysql.service" ];
		onFailure   = [ "notify-failure@%n.service" ];

		unitConfig.ConditionPathExists = "${wordpressRoot}/wp-config.php";

		serviceConfig = {
			Type    = "oneshot";
			User    = "wordpress";
			Group   = "wordpress";
			ExecStart = "${pkgs.wp-cli}/bin/wp --path=${wordpressRoot} cron event run --due-now";
		};
	};

	# ── Automatic updates ──────────────────────────────────────────────────────
	# setup-wordpress only runs on a fresh install, so without this core stays
	# on whatever version it downloaded that day. Tracks the latest core
	# release, majors included, plus plugins and themes.
	systemd.services."wp-update" = {
		description = "WordPress core, plugin and theme updates";
		after     = [ "network-online.target" "mysql.service" ];
		wants     = [ "network-online.target" ];
		onFailure = [ "notify-failure@%n.service" ];

		unitConfig.ConditionPathExists = "${wordpressRoot}/wp-config.php";

		serviceConfig = {
			Type  = "oneshot";
			User  = "wordpress";
			Group = "wordpress";
		};

		script = ''
			set -e
			WP="${pkgs.wp-cli}/bin/wp --path=${wordpressRoot}"
			$WP core update
			$WP core update-db
			$WP plugin update --all
			$WP theme update --all
		'';
	};

	systemd.timers."wp-update" = {
		description = "Daily WordPress updates";
		wantedBy    = [ "timers.target" ];
		timerConfig = {
			OnCalendar         = "daily";
			RandomizedDelaySec = "1h";
			Persistent         = true;
			Unit               = "wp-update.service";
		};
	};

	systemd.timers."wp-cron" = {
		description = "Run WordPress cron every 5 minutes";
		wantedBy    = [ "timers.target" ];
		timerConfig = {
			OnBootSec      = "5min";
			OnUnitActiveSec = "5min";
			Unit           = "wp-cron.service";
		};
	};
}
