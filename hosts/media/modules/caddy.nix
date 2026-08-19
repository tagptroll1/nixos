{ config, pkgs, ... }: {
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/tagptroll1/caddy-dns-domeneshop@v0.1.8"
      ];
      # v0.1.8: fix returned Record.Name to stay relative to the caller's
      # zone (don't rewrite to FQDN). certmagic's propagation check was
      # AbsoluteName()-ing it again, producing _acme-challenge.X.ybmn.no.ybmn.no
      # and looping with `last error: <nil>` until timeout.
      hash = "sha256-UzaVuw0C9G+J+d/KWbQJYjh/e3ADhIqxmomNUSOtcO8=";
    };

    globalConfig = ''
      acme_dns domeneshop {
        token  {env.DOMENESHOP_API_TOKEN}
        secret {env.DOMENESHOP_API_SECRET}
      }
    '';

    virtualHosts =
      let
        # LAN + Tailscale CGNAT + loopback. Caddy uses these matchers to
        # 403 anything else, since *.ybmn.no resolves on split-DNS only.
        # 10.89.0.0/16 is the podman default bridge subnet — needed because
        # OpenCloud's proxy makes internal HTTPS callbacks to its own OIDC
        # userinfo endpoint via cloud.ybmn.no, and the source IP is the
        # container's bridge address (e.g. 10.89.0.x). Without this the
        # callback gets 403 and login appears to "succeed" but every API
        # call returns 401.
        trustedMatcher = ''
          @trusted client_ip 10.2.0.0/24 10.2.10.0/24 192.168.0.0/24 100.64.0.0/10 127.0.0.1/8 10.89.0.0/16
        '';
        # Query the zone's authoritative nameservers (hyp.net) directly for
        # the DNS-01 propagation check. Public anycast resolvers like
        # 1.1.1.1 have inconsistent cache state across POPs — the TXT
        # appears and disappears between polls, so Caddy never confirms
        # propagation and times out with `last error: <nil>`. Authoritative
        # servers always reflect the source of truth.
        tlsBlock = ''
          tls {
            dns domeneshop {
              token  {env.DOMENESHOP_API_TOKEN}
              secret {env.DOMENESHOP_API_SECRET}
            }
            resolvers 151.249.124.1 192.174.68.10 151.249.126.3
            propagation_delay 30s
            propagation_timeout 5m
          }
        '';
        gated = upstream: ''
          ${tlsBlock}
          ${trustedMatcher}
          handle @trusted {
            reverse_proxy ${upstream}
          }
          respond 403
        '';
      in {
      "immich.ybmn.no".extraConfig = ''
        reverse_proxy 127.0.0.1:2283
      '';
      "jellyfin.ybmn.no".extraConfig = ''
        reverse_proxy 127.0.0.1:8096
      '';
      # TODO: add `seer.ybmn.no` A/CNAME record in domeneshop before this
      # vhost can serve traffic — Caddy will otherwise fail ACME DNS-01.
      "seer.ybmn.no".extraConfig    = gated "127.0.0.1:5055";
      "sonarr.ybmn.no".extraConfig   = gated "127.0.0.1:8989";
      "radarr.ybmn.no".extraConfig   = gated "127.0.0.1:7878";
      "prowlarr.ybmn.no".extraConfig = gated "127.0.0.1:9696";
      "bazarr.ybmn.no".extraConfig   = gated "127.0.0.1:6767";
      # qBittorrent lives in the wg netns; reachable at the namespace IP
      # from the host. Confirm with `ip -n wg a` after first boot if 192.168.15.1
      # ever drifts.
      "qbit.ybmn.no".extraConfig     = gated "192.168.15.1:8080";
      "recipe.ybmn.no".extraConfig = gated "127.0.0.1:9925";
      "factorio.ybmn.no".extraConfig = gated "127.0.0.1:8090";
      "palworld.ybmn.no".extraConfig = gated "127.0.0.1:3939";
      "cloud.ybmn.no".extraConfig     = gated "127.0.0.1:9200";
      "collabora.ybmn.no".extraConfig = gated "127.0.0.1:9980";
      "wopi.ybmn.no".extraConfig      = gated "127.0.0.1:9300";
      # Cockpit needs the upstream to be HTTPS-or-tell-it-it's-encrypted;
      # the AllowUnencrypted=true cockpit setting plus ProtocolHeader handles
      # that on the cockpit side, so a plain reverse_proxy works here.
      # WebSocket upgrade is handled automatically by Caddy's reverse_proxy.
      "cockpit.ybmn.no".extraConfig   = gated "127.0.0.1:9090";
    };
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.sops.secrets."caddy/domeneshop_token".path;
  };
}
