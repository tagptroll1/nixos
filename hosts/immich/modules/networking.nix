{ hostConfig, ... }: {
  networking = {
    hostName = hostConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    firewall = {
      enable = true;
      # 22 only. 2283 is opened for the media VM alone in immich.nix - it is
      # the only thing that may reach the API, as Caddy and
      # immich-public-proxy both run there.
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
