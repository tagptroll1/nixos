{ ... }: {
  users.groups.tagp = {};
  users.users.tagp = {
    isNormalUser = true;
    group = "tagp";
    description = "Main account";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINiXPaVoHFnjA3wTgXLvWPPMUfpWi+C3hnCFBYtlpMYs thomas@petersson.priv.no"
    ];
  };
}
