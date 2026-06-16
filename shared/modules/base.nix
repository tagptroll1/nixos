{ pkgs, ... }: {
	# Ghostty terminfo so SSHing in from Ghostty (TERM=xterm-ghostty) works —
	# without it sudo/editors/clear fail with "unknown terminal type".
	environment.systemPackages = [ pkgs.ghostty.terminfo ];

	boot.loader = {
		systemd-boot.enable = true;
		efi.canTouchEfiVariables = true;
	};

	nix.settings = {
		experimental-features = [ "nix-command" "flakes" ];
		auto-optimise-store = true;
	};

	nixpkgs.config.allowUnfree = true;

	system.stateVersion = "25.11";

	time.timeZone = "Europe/Oslo";
	i18n.defaultLocale = "en_GB.UTF-8";
	console.keyMap = "no-latin1";
}
