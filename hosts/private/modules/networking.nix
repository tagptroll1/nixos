{ config, pkgs, hostConfig, ... }:
let
  inherit (pkgs) it-tools;
  # The LAN allowlist, the DNS-01 tls block and the plugin pin live in
  # lib/caddy.nix so the generated app vhosts in modules/apps.nix and the other
  # Caddy hosts use the same ones. Changing the allowlist there changes it for
  # all of them.
  inherit (import ../../../lib/caddy.nix) lanOnly tlsGigahost acmeDnsGigahost gigahostPlugin;
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
    package = pkgs.caddy.withPlugins gigahostPlugin;

    globalConfig = acmeDnsGigahost;

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
          # to obtain.
          "git.ybmn.no".extraConfig = ''
            ${lanOnly "127.0.0.1:3000"}
            ${tlsGigahost}
          '';


          # The ledger. LAN + tailnet only. financio has its own login now, with
          # one SQLite file per user, so this is the outer fence rather than the
          # only one - /api/health is the sole route it serves unauthenticated.
          #
          # No www alias, for the reason above it: nobody types www.bank, and it
          # doubles the certificates.
          "bank.ybmn.no".extraConfig = ''
            ${lanOnly "127.0.0.1:8086"}
            ${tlsGigahost}
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

          # Workout sheet: one static page from ../sites/mova, LAN + tailnet
          # only. Set ticks live in the browser's localStorage, nothing
          # server-side. No www alias, same reason as git.ybmn.no.
          "mova.ybmn.no".extraConfig = ''
            @lan remote_ip 192.168.0.0/24 192.168.54.0/24 10.0.0.0/24
            handle @lan {
              root * ${../sites/mova}
              file_server
            }
            respond "Access denied" 403
            ${tlsGigahost}
          '';

        }
      ;
  };

  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.sops.secrets."caddy/gigahost_env".path;
  };
}
