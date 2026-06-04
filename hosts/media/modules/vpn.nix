{ config, ... }: {
  # The wg.conf is a standard WireGuard config (the kind most VPN providers
  # offer as "WireGuard / OpenVPN-compatible .conf"). To rotate or add it:
  #   sops hosts/media/secrets/vpnSecret.yaml
  # and set the `wg.conf` key to the full file contents using a YAML block
  # scalar so newlines are preserved:
  #
  #   wg.conf: |
  #     [Interface]
  #     PrivateKey = <base64>
  #     Address = 10.2.0.2/32
  #     DNS = 10.2.0.1
  #
  #     [Peer]
  #     PublicKey = <base64>
  #     AllowedIPs = 0.0.0.0/0
  #     Endpoint = vpn.example.com:51820
  #
  # The secret is wired in hosts/media/default.nix and mounted at
  # config.sops.secrets."vpn/wg.conf".path for the wg netns below.
  vpnNamespaces.wg = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."vpn/wg.conf".path;
    accessibleFrom = [
      "127.0.0.1/32"
      "10.2.10.0/24"
      "100.64.0.0/10"
    ];
  };
}
