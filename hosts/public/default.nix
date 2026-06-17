{ modulesPath, config, ... }: {
	imports = [
		(modulesPath + "/profiles/qemu-guest.nix")
		./hardware-configuration.nix

		# Shared modules
		../../shared/modules/base.nix
		../../shared/modules/overlays.nix
		../../shared/modules/motd.nix
		../../shared/modules/sshd.nix
		(import ../../shared/modules/newt.nix {
			endpoint        = "https://pangolin.yesbutmaybe.no";
			secretIdKey     = "newt-id";
			secretSecretKey = "newt-secret";
		})

		# Host-specific modules
		./modules/networking.nix
		./modules/users.nix
		./modules/packages.nix
		./modules/mailserver.nix
		./modules/roundcube.nix
		./modules/wordpress.nix
		./modules/static-sites.nix
		./modules/peterssoncoffee.nix
		./modules/byggogbedrag.nix
		./modules/exporters.nix
	];

	sops.age.keyFile = "/etc/age/host.key";
	sops.defaultSopsFile = ./secrets/secrets.yaml;
	sops.defaultSopsFormat = "yaml";

	sops.secrets = {
		"motd/secret" = {
			owner = "tagp";
		};
		"newt-id" = {};
		"newt-secret" = {};
		"domeneshop_api_token" = {};
		"domeneshop_api_secret" = {};
		"github_token" = {};
		# Plaintext SMTP password for post@byggogbedrag.no, used by the
		# SvelteKit site to authenticate to the local mailserver. Format: SMTP_PASS=...
		"byggogbedrag_smtp_pass" = {};
		"mail_hashed_password" = {
			neededForUsers = true;
		};
		"mail_grafana_hashed_password" = {
			neededForUsers = true;
		};
		"mail_changes_hashed_password" = {
			neededForUsers = true;
		};
		"mail_byggogbedrag_hashed_password" = {
			neededForUsers = true;
		};
		# Postfix relay SASL creds for the Pangolin VPS smarthost.
		# Format (one line): [91.99.59.171]:587 relay@yesbutmaybe.no:PASSWORD
		"mail_relay_sasl_passwd" = {
			owner = "postfix";
		};
	};
}
