{ pkgs, ... }:
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
    "${factorioData}".d                 = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/factorio".d        = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/factorio/mods".d   = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/factorio/saves".d  = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/factorio/config".d = { user = "games"; group = "games"; mode = "2770"; };
    "${factorioData}/fsm-data".d        = { user = "games"; group = "games"; mode = "2770"; };
  };

  virtualisation.oci-containers.containers.factorio = {
    image = "docker.io/ofsm/ofsm:latest";
    ports = [
      "34197:34197/udp"      # factorio game port — public via Pangolin raw UDP resource (newt tunnel)
      "127.0.0.1:8090:80"    # FSM web UI — loopback only, exposed via Caddy
    ];
    environment = {
      FACTORIO_VERSION = "stable";
      # FSM↔factorio RCON, internal to the container only (never exposed).
      RCON_PASS        = "factorio-rcon-internal";
    };
    volumes = [
      "${factorioData}/factorio:/opt/factorio"
      "${factorioData}/factorio/mods:/opt/factorio/mods"
      "${factorioData}/factorio/saves:/opt/factorio/saves"
      "${factorioData}/factorio/config:/opt/factorio/config"
      "${factorioData}/fsm-data:/opt/fsm-data"
    ];
  };
}
