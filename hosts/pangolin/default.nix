{ ... }: {
	imports = [
		./hardware-configuration.nix

		# Shared modules
		../../shared/modules/base.nix
		../../shared/modules/overlays.nix
		../../shared/modules/sshd.nix

		# Host-specific modules
		./modules/bootloader.nix
		./modules/networking.nix
		./modules/users.nix
		./modules/packages.nix
		./modules/pangolin.nix
		./modules/mail-relay.nix
	];

	sops.age.keyFile = "/etc/age/host.key";
	sops.defaultSopsFile = ./secrets/secrets.yaml;
	sops.defaultSopsFormat = "yaml";

	sops.secrets = {
		# Pangolin's server.secret; must match the sqlite db in
		# /var/lib/pangolin/config/.
		"pangolin-server-secret" = {};
		# Domeneshop API credentials for the relay.yesbutmaybe.no ACME cert
		# (DNS-01, since traefik owns port 80).
		"domeneshop_api_token" = {};
		"domeneshop_api_secret" = {};
	};
}
