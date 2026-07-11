{ ... }: {
	users.users.tagp = {
		isNormalUser = true;
		description = "Main account";
		extraGroups = [ "wheel" ];
		openssh.authorizedKeys.keys = [
			"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKb37tlycemJGwbqARSTVSrekdHBnzuMk0cHztVVdZwf thomas@petersson.priv.no"
			# Key used on the other hosts in this flake.
			"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINiXPaVoHFnjA3wTgXLvWPPMUfpWi+C3hnCFBYtlpMYs thomas@petersson.priv.no"
		];
	};
}
