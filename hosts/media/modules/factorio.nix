{ ... }:
let
  factorioData = "/mnt/games/factorio";

  # Factorio Server Manager (FSM) owns the factorio headless process and exposes a
  # web UI for start/stop, saves, mods and server-settings. 
in {
  # /opt/factorio holds the downloaded binary + saves/ mods/ config/; /opt/fsm-data
  # holds conf.json, sqlite.db and logs. Persist both on the games share. Container
  # runs as root (rootful podman → host root) so it can write into these regardless
  # of the games ownership; games:games 2770 keeps tagp able to inspect them.
  systemd.tmpfiles.settings."10-factorio" = {
    "${factorioData}".d          = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/factorio".d = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/fsm-data".d = { user = "games"; group = "games"; mode = "2770"; };
  };

  virtualisation.oci-containers.containers.factorio = {
    image = "docker.io/ofsm/ofsm:latest";
    ports = [
      "34197:34197/udp"      # factorio game port — public via pangoling DNAT
      "127.0.0.1:8090:80"    # FSM web UI — loopback only, exposed via Caddy
    ];
    environment = {
      ADMIN_USER       = "tagp";
      ADMIN_PASS       = "password";
      FACTORIO_VERSION = "stable";
      # FSM↔factorio RCON, internal to the container only (never exposed).
      RCON_PASS        = "factorio-rcon-internal";
    };
    volumes = [
      "${factorioData}/factorio:/opt/factorio"
      "${factorioData}/fsm-data:/opt/fsm-data"
    ];
  };
}
