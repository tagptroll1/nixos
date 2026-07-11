{ hostConfig, ... }: {
  networking = {
    hostName = hostConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
      # tailscale opens its own port via services.tailscale.openFirewall
      trustedInterfaces = [ "tailscale0" ];
    };
    interfaces.${hostConfig.interface}.ipv4.addresses = [{
      address = hostConfig.ip;
      prefixLength = hostConfig.prefixLength;
    }];
    defaultGateway = hostConfig.gateway;
    nameservers = hostConfig.nameservers;
  };
}
