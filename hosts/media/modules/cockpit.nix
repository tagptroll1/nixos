{ pkgs, ... }: {
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = false;  # reached via Caddy on cockpit.ybmn.no
    settings = {
      WebService = {
        # Caddy terminates TLS and forwards to localhost:9090; tell cockpit
        # which Host header it should trust as the canonical origin.
        Origins = "https://cockpit.ybmn.no wss://cockpit.ybmn.no";
        ProtocolHeader = "X-Forwarded-Proto";
        AllowUnencrypted = "true";  # safe: only loopback reaches the port
      };
    };
  };

  # The cockpit-podman plugin is shipped as a separate package; cockpit
  # picks it up from /run/current-system/sw/share/cockpit via
  # environment.pathsToLink which the module already sets.
  environment.systemPackages = [ pkgs.cockpit-podman ];
}
