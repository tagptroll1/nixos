{ ... }:
{
  # Stable symlink for the Sonoff ZBDongle-E (EFR32MG21 + CP2102N, VID:PID 10c4:ea60).
  # Without this, the dongle races with other USB-serial devices for /dev/ttyUSB0.
  # Verify on the host with: lsusb | grep 10c4
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="ttyZigbee", MODE="0660", GROUP="dialout"
  '';

  # Create the !include'd files on first boot so HA doesn't enter recovery mode
  systemd.tmpfiles.rules = [
    "f /var/lib/hass/automations.yaml 0600 hass hass - -"
    "f /var/lib/hass/scripts.yaml     0600 hass hass - -"
    "f /var/lib/hass/scenes.yaml      0600 hass hass - -"
  ];

  services.home-assistant = {
    enable = true;

    # Optional C-accelerated compression libs — silences the
    # "zlib_ng and isal are not available" startup warning.
    extraPackages = python3Packages: with python3Packages; [
      isal
      zlib-ng
    ];

    extraComponents = [
      "default_config"  # required for onboarding
      "met"             # weather/sun integration
      "mqtt"            # required for zigbee2mqtt ↔ HA device discovery
      "radio_browser"   # pulled in by default_config; needs 'radios' Python package
      "google_translate" # pulled in by default_config; needs 'gtts' Python package
      "mobile_app"      # required for HA companion app registration
    ];

    config = {
      # default_config bundles mobile_app, frontend, history, etc.
      # Without this line HA installs the components but never loads them.
      default_config = {};

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        latitude = 60.3913;
        longitude = 5.3221;
        elevation = 5;
      };

      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
        # Required when behind Caddy — passes real client IP
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };

      # Keep automations/scripts/scenes UI-editable (HA writes these files at runtime)
      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
    };
  };
}
