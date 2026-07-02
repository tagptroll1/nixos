{ pkgs, ... }: {
	environment.systemPackages = with pkgs; [
		sops
		vim
		git
		curl
		htop
		btop
		wget
		bind       # DNS utilities (dig, nslookup)
		nixd
	];
}
