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

	# The ledger holds every transaction ever synced, including a 12-month hole
	# the bank will never return again. There is no other copy.
	financioDir = "/var/lib/financio";

	# One ledger per login, at tenants/<slug>/database.db. There is no single
	# file to back up any more, so the prepare command below loops.
	financioLedgers = "${financioDir}/tenants";

	# Same treatment as forgejo's db: consistent copies taken by sqlite3 .backup
	# right before each run, with the live files excluded. Copying a WAL database
	# file by file gives a silently stale or corrupt ledger.
	#
	# A directory rather than one path, because missing a ledger here would be
	# silent until somebody tried to restore it.
	financioSnapshots = "/mnt/data/backup/financio";
in {
	systemd.tmpfiles.rules = [
		"d /mnt/data/backup 0700 root root - -"
		"d ${financioSnapshots} 0700 root root - -"
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

			# .db-backups/ rides along on purpose: those are the pre-import undo
			# points, and a bad import discovered after the nightly run is exactly
			# when the off-site copy of them matters.
			financioDir
			financioSnapshots
		];

		exclude = [
			# Covered by dbSnapshot; copying these live risks a torn read.
			"${forgejoDir}/data/forgejo.db"
			"${forgejoDir}/data/forgejo.db-wal"
			"${forgejoDir}/data/forgejo.db-shm"
			"${forgejoDir}/log"
			"${forgejoDir}/data/tmp"

			# Live files - covered by financioSnapshots; reading them mid-write
			# risks a torn copy. One glob per user, since each login has its own
			# ledger. The pre-login path is still listed: a host that has not run
			# the move yet has one sitting there.
			"${financioLedgers}/*/database.db"
			"${financioLedgers}/*/database.db-wal"
			"${financioLedgers}/*/database.db-shm"
			"${financioDir}/database.db"
			"${financioDir}/database.db-wal"
			"${financioDir}/database.db-shm"
		];

		backupPrepareCommand = ''
			#!${pkgs.runtimeShell}
			# writeScript adds no shebang and no error handling of its own, so a
			# failed copy would otherwise leave restic backing up yesterday's
			# snapshot and reporting success.
			set -eu

			${pkgs.sqlite}/bin/sqlite3 ${forgejoDir}/data/forgejo.db ".backup '${dbSnapshot}'"

			# One consistent copy per login. A ledger that was silently skipped
			# is the worst outcome here and stays invisible until somebody tries
			# to restore it, so a failure on any one of them stops the run.
			#
			# Ledgers may not exist at all on a host that has not deployed
			# financio, and a missing one must not fail forgejo's backup.
			for db in ${financioLedgers}/*/database.db; do
				[ -f "$db" ] || continue

				slug=$(basename "$(dirname "$db")")
				${pkgs.sqlite}/bin/sqlite3 "$db" ".backup '${financioSnapshots}/$slug.sqlite'"
			done

			# Left behind by a host that has not had its ledger moved into
			# tenants/<slug>/ yet. Still the only copy until it is.
			if [ -f ${financioDir}/database.db ]; then
				${pkgs.sqlite}/bin/sqlite3 ${financioDir}/database.db ".backup '${financioSnapshots}/pre-login.sqlite'"
			fi
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
