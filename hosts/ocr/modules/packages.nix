{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    # Watching the card while a receipt is read: the vision server's VRAM
    # comes and goes with sleep-idle, and this is how you see it happen.
    nvtopPackages.nvidia
  ];
}
