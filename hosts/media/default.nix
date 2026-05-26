{ modulesPath, ... }: {
	imports = [
		(modulesPath + "/profiles/qemu-guest.nix")
		./hardware-configuration.nix

		# Shared modules
		../../shared/modules/base.nix
		../../shared/modules/overlays.nix
		../../shared/modules/sshd.nix
		(import ../../shared/modules/newt.nix {
			endpoint        = "https://pangolin.yesbutmaybe.no";
			secretIdKey     = "newt-id-media";
			secretSecretKey = "newt-secret-media";
		})

		# Host-specific modules
		./modules/networking.nix
		./modules/users.nix
		./modules/packages.nix
		./modules/storage.nix
		./modules/gpu.nix
		./modules/tailscale.nix
		./modules/netbird.nix
		./modules/caddy.nix
		./modules/cockpit.nix
		./modules/podman.nix
		./modules/cs2.nix
		./modules/factorio.nix
		./modules/mealie.nix
		./modules/opencloud.nix
		./modules/immich.nix
		./modules/immich-public-proxy.nix
		./modules/jellyfin.nix
	];

	sops.age.keyFile = "/etc/age/host.key";
	sops.secrets = {
		"opencloud/admin_env" = {
			sopsFile = ./secrets/opencloudSecret.yaml;
			key = "admin_env";
		};
		"opencloud/collabora_env" = {
			sopsFile = ./secrets/opencloudSecret.yaml;
			key = "collabora_env";
		};
		"caddy/domeneshop_token" = {
			sopsFile = ./secrets/caddySecret.yaml;
			key = "token";
			owner = "caddy";
		};
		"newt-id-media" = {
			sopsFile = ./secrets/newtSecret.yaml;
			key = "newt-id-media";
		};
		"newt-secret-media" = {
			sopsFile = ./secrets/newtSecret.yaml;
			key = "newt-secret-media";
		};
		"cs2/rcon_pw" = {
			sopsFile = ./secrets/cs2Secret.yaml;
			key = "rcon_pw";
		};
		"cs2/server_pw" = {
			sopsFile = ./secrets/cs2Secret.yaml;
			key = "server_pw";
		};
		"cs2/api_key" = {
			sopsFile = ./secrets/cs2Secret.yaml;
			key = "api_key";
		};
	};

	services.qemuGuest.enable = true;
}
