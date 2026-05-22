{ pkgs, ... }: {
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = false;  # reached via Caddy on cockpit.ybmn.no
    # `allowed-origins` is the list-merging option; the module joins it
    # with its default ("https://localhost:9090") into WebService.Origins.
    allowed-origins = [
      "https://cockpit.ybmn.no"
      "wss://cockpit.ybmn.no"
    ];
    settings = {
      WebService = {
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
