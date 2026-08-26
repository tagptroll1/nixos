{ config, pkgs, ... }:
let
	# Dedicated ssh-only subaccount on the BX11 "home02-backup" box, chrooted to
	# /restic-private-git-forgejo. Separate from the main account home02 backs up
	# with, so a compromise of this host cannot reach home02's snapshots.
	# Subaccounts get their own hostname, not just their own username.
	storageBox = "u586986-sub2";

	forgejoDir = config.services.forgejo.stateDir;

	# Consistent copy of the sqlite db, taken by `sqlite3 .backup` right before
	# each run. The live db is excluded below.
	dbSnapshot = "/mnt/data/backup/forgejo-db.sqlite";
in {
	systemd.tmpfiles.rules = [
		"d /mnt/data/backup 0700 root root - -"
	];

	services.restic.backups.private = {
		initialize = true;

		# Paths are relative to the subaccount's home, which is already the
		# dedicated base dir, so this is /restic-private-git-forgejo/restic.
		repository   = "sftp:storagebox:restic";
		passwordFile = config.sops.secrets."restic/password".path;

		# The Storage Box listens on port 23 and the key is a sops secret under
		# /run/secrets, so restic's default `ssh <host> -s sftp` is not enough.
		extraOptions = [
			"sftp.command='ssh ${storageBox}@${storageBox}.your-storagebox.de -p 23 -i ${config.sops.secrets."restic/ssh_key".path} -o IdentitiesOnly=yes -s sftp'"
		];

		paths = [
			forgejoDir
			dbSnapshot
		];

		exclude = [
			# Covered by dbSnapshot; copying these live risks a torn read.
			"${forgejoDir}/data/forgejo.db"
			"${forgejoDir}/data/forgejo.db-wal"
			"${forgejoDir}/data/forgejo.db-shm"
			"${forgejoDir}/log"
			"${forgejoDir}/data/tmp"
		];

		backupPrepareCommand = ''
			${pkgs.sqlite}/bin/sqlite3 ${forgejoDir}/data/forgejo.db ".backup '${dbSnapshot}'"
		'';

		timerConfig = {
			# home02's job runs 03:30 +30m jitter. The box allows 10 concurrent
			# connections and restic's sftp backend uses several, so keep the two
			# jobs from overlapping.
			OnCalendar         = "01:30";
			RandomizedDelaySec = "30m";
			Persistent         = true;
		};

		# Without forget --prune the remote repository grows without bound.
		pruneOpts = [
			"--keep-daily 14"
			"--keep-weekly 8"
			"--keep-monthly 24"
			"--keep-yearly 5"
		];
	};
}
