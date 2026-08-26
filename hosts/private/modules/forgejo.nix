{ ... }: {
	services.forgejo = {
		enable = true;

		# Repositories, the sqlite db and LFS objects live on the 2.7T vmdata
		# disk instead of the root filesystem, which also holds the nix store.
		stateDir = "/mnt/data/forgejo";

		lfs.enable = true;

		settings = {
			server = {
				DOMAIN   = "git.ybmn.no";
				ROOT_URL = "https://git.ybmn.no/";

				# Caddy is the only consumer of the web UI.
				HTTP_ADDR = "127.0.0.1";
				HTTP_PORT = 3000;

				# Built-in ssh server, so git-over-ssh never involves the host
				# sshd or an authorized_keys file managed outside nix.
				START_SSH_SERVER = true;
				SSH_LISTEN_PORT  = 2222;
				SSH_PORT         = 2222;
				SSH_DOMAIN       = "git.ybmn.no";

				# Defaults to RUN_USER, which is `forgejo` here — every client
				# and clone URL expects the conventional `git@`.
				BUILTIN_SSH_SERVER_USER = "git";
			};

			# Served over https only.
			session.COOKIE_SECURE = true;

			# Single-user forge: accounts are created by the admin, never signed up.
			service.DISABLE_REGISTRATION = true;

			actions.ENABLED = true;
		};
	};
}
