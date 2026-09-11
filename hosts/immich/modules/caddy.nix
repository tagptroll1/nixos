{ config, pkgs, ... }:
let
  snippets = import ../../../lib/caddy.nix;
in {
  /*
    immich serves its own name, rather than being reverse-proxied from the
    media VM. The point is availability: a Zomboid-driven reboot over there
    used to take the photo library's web UI with it, even though immich itself
    was fine. Now the only thing that can take immich down is immich.

    The public share does not come through here at all - that is the `share`
    container's newt tunnel into immich's API on 2283. This vhost is the LAN
    and tailnet door only.
  */
  services.caddy = {
    enable = true;

    # The domeneshop DNS-01 provider, pinned to the version the rest of the
    # estate uses: v0.1.8 keeps the returned Record.Name relative to the
    # caller's zone, where earlier versions rewrote it to an FQDN and certmagic
    # then absolutised it again, producing _acme-challenge.X.ybmn.no.ybmn.no
    # and looping until timeout.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/tagptroll1/caddy-dns-domeneshop@v0.1.8" ];
      hash = "sha256-UzaVuw0C9G+J+d/KWbQJYjh/e3ADhIqxmomNUSOtcO8=";
    };

    globalConfig = ''
      acme_dns domeneshop {
        token  {env.DOMENESHOP_API_TOKEN}
        secret {env.DOMENESHOP_API_SECRET}
      }
    '';

    virtualHosts."immich.ybmn.no".extraConfig = ''
      ${snippets.tlsDomeneshop}
      @trusted client_ip 192.168.0.0/24 192.168.54.0/24 10.0.0.0/24 100.64.0.0/10 127.0.0.1/8
      handle @trusted {
        reverse_proxy 127.0.0.1:2283
      }
      respond "Access denied" 403
    '';
  };

  # A matcher rather than lib/caddy.nix's `lanOnly`, because the phone syncs
  # over the tailnet as well as the LAN and needs 100.64.0.0/10. Deliberately
  # absent: 10.2.10.0/24 and 10.2.30.0/24 - no container has business reaching
  # this UI, and the share container talks to the API on 2283 instead.

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  systemd.services.caddy.serviceConfig.EnvironmentFile =
    config.sops.secrets."caddy/domeneshop_token".path;
}
