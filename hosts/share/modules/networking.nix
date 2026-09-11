{ hostConfig, ... }: {
  networking = {
    hostName = hostConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    firewall = {
      enable = true;
      # 22, and nothing else - not even the service port. immich-public-proxy
      # binds all interfaces (the module offers no bind address), but newt
      # reaches it over loopback from this same host, so nothing on any network
      # needs to connect *to* this machine at all. The tunnel dials outward.
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
