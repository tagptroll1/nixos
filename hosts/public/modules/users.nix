{ ... }: {
	users.users.tagp = {
		isNormalUser = true;
		description = "Main account";
		extraGroups = [ "wheel" "networkmanager" ];
		openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINiXPaVoHFnjA3wTgXLvWPPMUfpWi+C3hnCFBYtlpMYs thomas@petersson.priv.no" ];
	};

	# System user for pulling and deploying Karoline's static site
	users.users.staticbuilder = {
		isSystemUser = true;
		group = "nginx";
	};

	# System user for the petersson.coffee Node.js app
	users.users.peterssoncoffee = {
		isSystemUser = true;
		group        = "peterssoncoffee";
		home         = "/var/lib/peterssoncoffee";
	};
	users.groups.peterssoncoffee = {};

	# System user for the byggogbedrag.no Node.js app
	users.users.byggogbedrag = {
		isSystemUser = true;
		group        = "byggogbedrag";
		home         = "/var/lib/byggogbedrag";
	};
	users.groups.byggogbedrag = {};
}
