{ ... }: {
  # Manual wiring required after first rebuild (none of this lives in nix —
  # the arr apps own their own SQLite state):
  #
  #   1. Prowlarr → Settings → Apps: add Sonarr (127.0.0.1:8989) and
  #      Radarr (127.0.0.1:7878) with their API keys so indexers sync.
  #   2. Prowlarr → Settings → Indexers → add proxy → FlareSolverr at
  #      http://127.0.0.1:8191, give it a tag, then tag CF-gated indexers.
  #   3. Sonarr & Radarr → Settings → Download Clients → qBittorrent at
  #      192.168.15.1:8080 (the wg netns IP). Set category (tv / movies)
  #      and download folder /mnt/media/downloads/complete.
  #   4. Bazarr → Settings → Sonarr / Radarr: loopback + API keys.
  #   5. Jellyseerr first-run wizard: point at Jellyfin (127.0.0.1:8096)
  #      and Sonarr/Radarr loopback + API keys.
  #   6. DNS: add `seer.ybmn.no` in domeneshop pointing at the media host
  #      (or CNAME to an existing record) — Caddy needs it to resolve.

  services.sonarr = {
    enable = true;
    group = "media";
  };

  services.radarr = {
    enable = true;
    group = "media";
  };

  services.prowlarr.enable = true;

  services.jellyseerr.enable = true;

  # FlareSolverr proxy for Cloudflare-gated indexers. After enabling, in
  # Prowlarr add Settings → Indexers → FlareSolverr proxy at
  # http://127.0.0.1:8191, give it a tag, and tag indexers that need it.
  services.flaresolverr.enable = true;

  services.bazarr = {
    enable = true;
    group = "media";
  };

  services.qbittorrent = {
    enable = true;
    group = "media";
    webuiPort = 8080;
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  users.users.qbittorrent.extraGroups = [ "media" ];
}
