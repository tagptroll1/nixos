{ hostConfig, ... }: {
  networking = {
    hostName = hostConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    firewall = {
      enable = true;
      # 22 only. The service port (8099) is opened for exactly one source
      # address in ocr.nix, and nothing else on this host listens.
      allowedTCPPorts = [ 22 ];
    };
    interfaces.${hostConfig.interface}.ipv4.addresses = [{
      address = hostConfig.ip;
      prefixLength = hostConfig.prefixLength;
    }];
    defaultGateway = hostConfig.gateway;
    nameservers = hostConfig.nameservers;
  };
}
