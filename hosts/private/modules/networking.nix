{ config, pkgs, hostConfig, ... }:
let
  inherit (pkgs) it-tools;
  # Only serve to LAN + tailnet — blocks access from public VM, internet pivots, etc.
  # Even if MikroTik firewall is misconfigured, Caddy won't serve these externally.
  # Tailnet traffic arrives via a subnet router on the Server subnet (10.0.0.0/24).
  lanOnly = upstream: ''
    @lan remote_ip 192.168.0.0/24 192.168.54.0/24 10.0.0.0/24
    handle @lan {
      reverse_proxy ${upstream}
    }
    respond "Access denied" 403
  '';
  # Network hierarchy: VMs (private/public) must NOT reach 10.0.0.x (Server subnet).
  # Grafana (10.0.0.5) and Proxmox (10.0.0.69) are accessed directly from LAN —
  # not proxied through Caddy here.
in {
  networking = {
    hostName = hostConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    firewall = {
      enable = true;
      # 2222 is Forgejo's built-in ssh server, for git clone/push over ssh.
      allowedTCPPorts = [ 80 443 8080 2222 ];
    };
    interfaces.${hostConfig.interface}.ipv4.addresses = [{
      address = hostConfig.ip;
      prefixLength = hostConfig.prefixLength;
    }];
    defaultGateway = hostConfig.gateway;
    nameservers = hostConfig.nameservers;
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/tagptroll1/caddy-dns-domeneshop@v0.1.3"
      ];
      # Leave as "" for first build — it will fail and print:
      #   got: sha256-<hash>
      # Paste that value here and rebuild.
      hash = "sha256-5VQutkG0mvg/eVP/fgZsWdLVSuA4JDnrhJMD4ig8Obc=";
    };

    globalConfig = ''
      acme_dns domeneshop {
        token  {env.DOMENESHOP_API_TOKEN}
        secret {env.DOMENESHOP_API_SECRET}
      }
    '';

    virtualHosts =
      let
        # Generates both the canonical HTTPS host and a www+http redirect
        mkVHost = domain: upstream: {
          "${domain}" = {
            extraConfig = ''
              reverse_proxy ${upstream}
            '';
          };
          "www.${domain}" = {
            extraConfig = ''
              redir https://${domain}{uri} permanent
            '';
          };
        };
      in
        (mkVHost "status.ybmn.no" "127.0.0.1:3001")
        // (mkVHost "file.ybmn.no" "127.0.0.1:3030")
        // (mkVHost "files.ybmn.no" "127.0.0.1:3030")
        // {
          # LAN-restricted services — 403 for anything outside 192.168.x.x
          "home.ybmn.no".extraConfig    = lanOnly "127.0.0.1:8082";
          "www.home.ybmn.no".extraConfig = "redir https://home.ybmn.no{uri} permanent";

          "ass.ybmn.no".extraConfig      = lanOnly "127.0.0.1:8123";
          "www.ass.ybmn.no".extraConfig  = "redir https://ass.ybmn.no{uri} permanent";

          "z2m.ybmn.no".extraConfig      = lanOnly "${hostConfig.ip}:8124";
          "www.z2m.ybmn.no".extraConfig  = "redir https://z2m.ybmn.no{uri} permanent";

          # Web UI only — git-over-ssh goes straight to port 2222, not via Caddy.
          # No www alias: nobody types www.git, and it doubles the certificates
          # to obtain. Domeneshop spreads records across ns1/ns2/ns3.hyp.net
          # slower than Caddy's default zero delay, so Let's Encrypt's secondary
          # validation read a stale challenge TXT and failed. Wait for the record
          # to settle before asking for validation.
          "git.ybmn.no".extraConfig = ''
            ${lanOnly "127.0.0.1:3000"}
            tls {
              dns domeneshop {
                token  {env.DOMENESHOP_API_TOKEN}
                secret {env.DOMENESHOP_API_SECRET}
              }
              propagation_delay   2m
              propagation_timeout 5m
            }
          '';

          "change.ybmn.no".extraConfig    = lanOnly "127.0.0.1:5000";
          "www.change.ybmn.no".extraConfig = "redir https://change.ybmn.no{uri} permanent";

          # IT Tools: static SPA from nix store, LAN only
          "tools.ybmn.no" = {
            extraConfig = ''
              @lan remote_ip 192.168.0.0/24 192.168.54.0/24 10.0.0.50/32
              handle @lan {
                root * ${it-tools}/lib
                file_server
              }
              respond "Access denied" 403
            '';
          };
          "www.tools.ybmn.no".extraConfig = "redir https://tools.ybmn.no{uri} permanent";

        }
      ;
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.sops.secrets."caddy/domeneshop_token".path;
  };
}
