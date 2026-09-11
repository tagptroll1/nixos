{ config, pkgs, ... }:
let
  # A Proxmox mountpoint onto hddmirror/appdata/immich. It has to be a ZFS
  # dataset on home02 rather than this container's rootfs, because the cloud
  # backup covers home02's ZFS datasets and nothing else. The photos have
  # always been covered - they live on hddmirror/{tagp,karoline}/photos - but
  # the database never was, and without it a restore gives you a folder of
  # JPEGs with no albums, no faces, no timeline and no shared links.
  dumps = "/mnt/appdata/immich/dumps";

  # Fourteen daily dumps, ~tens of MB each compressed. The point of keeping
  # more than one is that corruption is usually noticed days late.
  keepDays = 14;
in
{
  systemd.services.immich-db-dump = {
    description = "Dump the immich database to the backed-up dataset";
    path = [
      config.services.postgresql.package
      pkgs.gzip
      pkgs.coreutils
      pkgs.findutils
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      UMask = "0077";
    };

    script = ''
      set -euo pipefail

      stamp=$(date +%Y-%m-%d)
      tmp="${dumps}/.immich-$stamp.sql.gz.partial"
      out="${dumps}/immich-$stamp.sql.gz"

      pg_dumpall --clean --if-exists | gzip -6 > "$tmp"
      mv -f "$tmp" "$out"

      find "${dumps}" -maxdepth 1 -name 'immich-*.sql.gz' -mtime +${toString keepDays} -delete
      find "${dumps}" -maxdepth 1 -name '.immich-*.partial' -mtime +1 -delete
    '';
  };

  systemd.timers.immich-db-dump = {
    description = "Nightly immich database dump";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:15";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  systemd.tmpfiles.settings."10-immich-dumps".${dumps}.d = {
    user = "postgres";
    group = "postgres";
    mode = "0750";
  };
}
