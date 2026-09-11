{ pkgs, ... }: {
  # Deliberately thin. This host runs two services and exists to be easy to
  # reason about; every package here is one more thing to audit if it is ever
  # taken.
  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
  ];
}
