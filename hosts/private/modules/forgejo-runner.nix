{ config, pkgs, ... }:
let
	# Identifier shown next to the runner in Forgejo's admin UI when it was
	# created. Not a secret — the paired token is, and comes from sops via
	# systemd credentials.
	connectionUuid = "fbcb4239-66a5-4b28-839f-3f987bb1a700";

	settingsFormat = pkgs.formats.yaml { };

	configFile = settingsFormat.generate "forgejo-runner.yaml" {
		log.level = "info";

		runner = {
			capacity = 1;
			# `native` is the label, `host` the execution scheme — jobs run
			# directly on this host rather than in a container.
			labels = [ "native:host" ];
		};

		host.workdir_parent = "/var/lib/forgejo-runner/workdir";

		server.connections.private = {
			# Caddy's vhost is remote_ip restricted and answers 403 to requests
			# from localhost, so talk to Forgejo directly.
			url = "http://127.0.0.1:3000/";
			uuid = connectionUuid;
			# Substituted by the runner from the systemd credentials directory.
			token_url = "file:$CREDENTIALS_DIRECTORY/token";
		};
	};
in {
	# A static user, not DynamicUser. Two reasons, both from the deploy path in
	# financio.nix: a dynamic uid cannot own /var/lib/financio-releases, and
	# DynamicUser puts the runner's own state under /var/lib/private, which is
	# 0700 root and therefore invisible to the financio service.
	#
	# Migration, once: the existing registration lives in
	# /var/lib/private/forgejo-runner. After the first switch, chown it to this
	# user or the runner comes up unregistered:
	#   sudo chown -R forgejo-runner:forgejo-runner /var/lib/private/forgejo-runner
	users.users.forgejo-runner = {
		isSystemUser = true;
		group        = "forgejo-runner";
		home         = "/var/lib/forgejo-runner";
	};
	users.groups.forgejo-runner = {};

	systemd.services.forgejo-runner = {
		description = "Forgejo Actions runner";
		after = [ "network-online.target" "forgejo.service" ];
		wants = [ "network-online.target" ];
		wantedBy = [ "multi-user.target" ];

		# Native jobs get this PATH and nothing else. Anything a workflow calls
		# has to be listed here.
		path = with pkgs; [
			bash
			coreutils
			curl
			gawk
			gitMinimal
			gnused
			nodejs
			wget
			gnutar
			# cgo: mattn/go-sqlite3 compiles the amalgamation on every build.
			gcc
			gzip
			openssh
			nix
			go
			# The deploy verification step polls /api/health and reads the sha
			# out of it, then falls back to systemctl for the failure message.
			jq
			systemd
			pnpm
		];

		serviceConfig = {
			ExecStart = "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config ${configFile}";
			WorkingDirectory = "/var/lib/forgejo-runner";
			StateDirectory = "forgejo-runner";
			User  = "forgejo-runner";
			Group = "forgejo-runner";
			LoadCredential = [ "token:${config.sops.secrets."forgejo/runner_token".path}" ];
			Restart = "on-failure";
			RestartSec = 2;
		};
	};
}
