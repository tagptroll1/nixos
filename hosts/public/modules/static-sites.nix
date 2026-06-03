{ pkgs, ... }:

let
	buildRoot        = "/var/lib/static-build";
	webRoot          = "/var/www";
	karolinePortfolio = "${webRoot}/karoline";
in
{
	services.nginx.enable = true;

	# Karoline's portfolio — served on port 9999
	services.nginx.virtualHosts."_" = {
		listen  = [{ addr = "0.0.0.0"; port = 9999; }];
		default = true;

		locations."/" = {
			root        = karolinePortfolio;
			index       = "index.html";
			extraConfig = "try_files $uri $uri/ =404;";
		};
	};

	# Directories for the static builder
	systemd.tmpfiles.rules = [
		"d ${buildRoot}/karoline    0755 staticbuilder staticbuilder - -"
		"d ${karolinePortfolio}     0755 nginx          nginx          - -"
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
