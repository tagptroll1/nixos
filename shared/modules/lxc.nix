# Common guest configuration for the NixOS containers on home02.
#
# A Proxmox LXC has no kernel, no bootloader and no initrd of its own - the
# host execs /sbin/init out of the container rootfs. Everything in here exists
# because some part of the normal NixOS boot assumes otherwise.
{ modulesPath, lib, ... }: {
	imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

	proxmoxLXC = {
		enable = true;

		# Both true so the address and the hostname are declared here rather
		# than in the container's Proxmox config. The upstream default is the
		# other way round - Proxmox writes /etc/hostname and a networkd file -
		# which would leave two sources of truth for the address that
		# hosts/*/modules/networking.nix declares. Set the CT's NIC to `manual`
		# (no IP) so nothing on the host side competes with it.
		manageNetwork = true;
		manageHostName = true;
	};

	# The VMs get this from their generated hardware-configuration.nix. A
	# container has no hardware to generate one from, so it is stated here.
	nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

	# `boot.isContainer` turns this on, which means /etc/resolv.conf comes from
	# whatever the host put in the container's rootfs. These containers resolve
	# through their own systemd-resolved (shared/modules/dns.nix), which asserts
	# against it - and inheriting the host's resolver would silently undo the
	# encrypted path anyway.
	networking.useHostResolvConf = false;

	# base.nix installs systemd-boot, which is right for the VMs and
	# impossible here: activation would try to write an ESP that does not
	# exist and fail the whole switch.
	boot.loader.systemd-boot.enable = lib.mkForce false;
	boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

	# Nix builds use user namespaces for the build sandbox, and an
	# unprivileged container only gets them when the CT has `features:
	# nesting=1`. Without it every build fails with a sandbox error rather
	# than a clear message, so this is a documented prerequisite for all of
	# these hosts, not just the ones running podman.
	nix.settings.sandbox = true;
}
