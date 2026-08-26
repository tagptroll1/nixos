{ config, pkgs, ... }: {
	services.gitea-actions-runner.instances.private = {
		enable = true;
		name   = "private";

		# The Caddy vhost is remote_ip restricted and would answer 403 to a
		# request from 127.0.0.1, so the runner talks to Forgejo directly.
		url = "http://127.0.0.1:3000";

		# An environment file holding TOKEN=<registration token>.
		tokenFile = config.sops.secrets."forgejo/runner_token".path;

		# Jobs execute directly on the host. Swap in a `docker://` label if a
		# job ever needs an isolated image.
		labels = [ "native:host" ];

		# The module default plus what a nix build needs. Anything a workflow
		# calls has to be listed here — native jobs get no other PATH.
		hostPackages = with pkgs; [
			bash
			coreutils
			curl
			gawk
			gitMinimal
			gnused
			nodejs
			wget
			gnutar
			gzip
			openssh
			nix
			go
			pnpm
		];
	};
}
