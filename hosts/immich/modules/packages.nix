{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    # Immich's ML container and its NVENC transcodes both live on the shared
    # card; this is how you see which one is holding VRAM.
    nvtopPackages.nvidia
  ];
}
