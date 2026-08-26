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
		./modules/uptime-kuma.nix
		./modules/filebrowser.nix
		./modules/changedetection.nix
		./modules/homepage.nix
		./modules/home-assistant.nix
		./modules/zigbee2mqtt.nix
		./modules/forgejo.nix
		./modules/restic.nix
		# Needs a runner registration token, which only exists once Forgejo has
		# run. Enable together with the forgejo/runner_token secret below.
		# ./modules/forgejo-runner.nix
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
		# Uncomment together with ./modules/forgejo-runner.nix above.
		# "forgejo/runner_token" = {
		# 	sopsFile = ./secrets/forgejoSecret.yaml;
		# 	key = "runner_token";
		# };
	};
}
