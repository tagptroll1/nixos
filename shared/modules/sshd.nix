{ ... }: {
	services.openssh = {
		enable = true;

		# No listenAddresses on purpose. proxmox-lxc.nix sets
		# services.openssh.startWhenNeeded, so sshd is socket-activated: the
		# address is baked into sshd.socket's ListenStream, which ties port 22 to
		# the interface being up before the socket starts. Binding all addresses
		# drops that dependency and costs nothing - the firewall opens 22 and
		# these hosts have one interface each.
		settings = {
			PermitRootLogin = "no";
			PasswordAuthentication = false;
			KbdInteractiveAuthentication = false;
		};
	};
}
