{ ... }: {
  users.groups.media.gid = 9000;

  users.users.tagp.extraGroups = [ "media" ];

  systemd.tmpfiles.settings."10-media-tree" = {
    "/mnt/media/downloads".d              = { user = "qbittorrent"; group = "media"; mode = "2775"; };
    "/mnt/media/downloads/incomplete".d   = { user = "qbittorrent"; group = "media"; mode = "2775"; };
    "/mnt/media/downloads/complete".d     = { user = "qbittorrent"; group = "media"; mode = "2775"; };
    "/mnt/media/tv".d                     = { user = "sonarr";      group = "media"; mode = "2775"; };
    "/mnt/media/movies".d                 = { user = "radarr";      group = "media"; mode = "2775"; };
  };
}
