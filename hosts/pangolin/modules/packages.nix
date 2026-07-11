{ pkgs, ... }: {
	environment.systemPackages = with pkgs; [
		sops
		vim
		neovim
		git
		curl
		wget
		htop
		btop
		tree
		bind   # dig, nslookup
		nixd
	];
}
