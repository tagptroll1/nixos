{ modulesPath, ... }: {
	imports = [
		(modulesPath + "/profiles/qemu-guest.nix")
		./hardware-configuration.nix

		# Shared modules
		../../shared/modules/base.nix
		../../shared/modules/overlays.nix
		../../shared/modules/motd.nix
		../../shared/modules/sshd.nix

		# Host-specific modules
		./modules/networking.nix
		./modules/users.nix
		./modules/packages.nix
		./modules/podman.nix
		./modules/apps.nix
		./modules/uptime-kuma.nix
		./modules/filebrowser.nix
		./modules/changedetection.nix
		./modules/homepage.nix
		./modules/home-assistant.nix
		./modules/zigbee2mqtt.nix
		./modules/forgejo.nix
		./modules/restic.nix
		./modules/forgejo-runner.nix
		./modules/financio.nix
	];
	# set with e2label / mkfs.ext4 -L vmdata
	fileSystems."/mnt/data" = {
		device  = "LABEL=vmdata";   # kernel resolves this directly
		fsType  = "ext4";
		options = [ "nofail" "x-systemd.device-timeout=10s" ];
	};

	sops.age.keyFile = "/etc/age/host.key";
	sops.secrets = {
		"motd/secret" = {
			sopsFile = ./secrets/motdSecret.yaml;
			key = "secret";
			owner = "tagp";
		};
		"hello/secret" = {
			sopsFile = ./containers/hello/secret.yaml;
			owner = "podman";
			key = "secret";
		};
		"caddy/domeneshop_token" = {
			sopsFile = ./secrets/caddySecret.yaml;
			key = "token";
			owner = "caddy";
		};
		"restic/password" = {
			sopsFile = ./secrets/resticSecret.yaml;
			key = "password";
		};
		"restic/ssh_key" = {
			sopsFile = ./secrets/resticSecret.yaml;
			key = "ssh_key";
			mode = "0400";
		};
		# A dotenv blob: NORDIGEN_CLIENT_ID, NORDIGEN_CLIENT_KEY and optionally
		# BANK_ACCOUNTS. Owned by financio so the units can read it.
		"financio/env" = {
			sopsFile = ./secrets/financioSecret.yaml;
			key = "env";
			owner = "financio";
		};
		"forgejo/runner_token" = {
			sopsFile = ./secrets/forgejoSecret.yaml;
			key = "runner_token";
		};
		# The private half of the key media authorises for its
		# financio-ocr-deploy user. It can do exactly two things there - rsync
		# into the releases directory, and say a release is ready - because
		# media binds it to a forced command (hosts/media/modules/ocr.nix).
		# Owned by the runner, which is the only thing that uses it.
		"financio-ocr/deploy_key" = {
			sopsFile = ./secrets/financioOcrSecret.yaml;
			key = "deploy_key";
			owner = "forgejo-runner";
			mode = "0400";
		};
	};
}
