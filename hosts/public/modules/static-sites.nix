{ pkgs, ... }:

let
	buildRoot        = "/var/lib/static-build";
	webRoot          = "/var/www";
	karolinePortfolio = "${webRoot}/karoline";
in
{
	services.nginx.enable = true;

	# Karoline's portfolio — served on port 9999.
	# Mirrors the repo's nginx.conf (gzip text-only, cache headers, video
	# byte-range streaming). All directives are scoped to this vhost so the
	# other sites this nginx serves are unaffected.
	services.nginx.virtualHosts."_" = {
		listen  = [{ addr = "0.0.0.0"; port = 9999; }];
		default = true;

		root  = karolinePortfolio;

		extraConfig = ''
			sendfile          on;
			tcp_nopush        on;
			keepalive_timeout 65;

			# gzip for text-ish assets only. Never gzip video: a gzipped
			# response can't be served with byte ranges, which would kill
			# seeking/streaming.
			gzip            on;
			gzip_vary       on;
			gzip_min_length 1024;
			gzip_types      text/css application/javascript image/svg+xml application/json;
		'';

		# HTML: always revalidate so edits show up without a hard refresh.
		locations."/" = {
			index       = "index.html";
			extraConfig = ''
				try_files $uri $uri/ =404;
				add_header Cache-Control "no-cache";
			'';
		};

		# Static media + scripts/styles: long-lived cache.
		locations."/assets/" = {
			extraConfig = ''
				add_header Cache-Control "public, max-age=2592000";
			'';
		};

		# Video: keep gzip off so nginx serves Range requests natively
		# (Accept-Ranges: bytes + 206), which is what makes seeking and
		# lightbox playback-before-full-download work.
		locations."/assets/videos/" = {
			extraConfig = ''
				gzip off;
				add_header Cache-Control "public, max-age=2592000";
			'';
		};
	};

	# Directories for the static builder
	systemd.tmpfiles.rules = [
		"d ${buildRoot}/karoline    0755 staticbuilder staticbuilder - -"
		# Owned by staticbuilder so it can rsync (incl. set dir times); group
		# nginx + world-readable perms let nginx serve it read-only.
		"d ${karolinePortfolio}     0755 staticbuilder nginx          - -"
	];

	# Pull and deploy Karoline's site from GitHub
	systemd.services."pull-karoline" = {
		description = "Build and deploy karolines site from GitHub";
		after       = [ "network-online.target" ];
		wants       = [ "network-online.target" ];

		path = with pkgs; [ git rsync coreutils ];

		serviceConfig = {
			User             = "staticbuilder";
			Group            = "nginx";
			WorkingDirectory = "${buildRoot}/karoline";
			Environment      = "HOME=${buildRoot}/karoline";
			ReadWritePaths   = [ "${buildRoot}/karoline" "${karolinePortfolio}" ];
			ProtectSystem    = "full";
		};

		script = ''
			set -e
			repo="https://github.com/tagptroll1/karoline-portfolio.git"
			if [ ! -d .git ]; then
				git clone "$repo" .
			else
				git remote set-url origin "$repo"
				git fetch origin
				git reset --hard origin/main
			fi
			rsync -av --delete --exclude=".git" ./ ${karolinePortfolio}/
		'';
	};

	systemd.timers."pull-karoline" = {
		wantedBy = [ "timers.target" ];
		timerConfig = {
			OnBootSec        = "1min";
			OnUnitActiveSec  = "10min";
			RandomizeDelaySec = "30s";
		};
	};
}
