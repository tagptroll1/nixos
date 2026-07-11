# The VPS boots BIOS/MBR off /dev/sda, so override the EFI/systemd-boot
# defaults set in shared/modules/base.nix.
{ lib, ... }: {
	boot.loader.systemd-boot.enable = lib.mkForce false;
	boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

	boot.loader.grub = {
		enable = true;
		device = "/dev/sda";
		efiSupport = false;
	};
}
