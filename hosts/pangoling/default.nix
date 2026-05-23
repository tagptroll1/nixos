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
		./modules/netbird.nix
		./modules/forwarding.nix
	];
}
