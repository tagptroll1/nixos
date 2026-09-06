# Encrypted off-site backup to a Hetzner Storage Box

A practical walkthrough for backing up a Linux/ZFS machine to a Hetzner
Storage Box with end-to-end encryption — using `sanoid` for snapshots and
`restic` for the encrypted, deduplicated, retention-bounded uploads.

The Storage Box only ever sees ciphertext. The passphrase never leaves your
host. Old backups are pruned automatically so the repository does not grow
without bound.

> Assumes Debian/Proxmox-flavoured host with a ZFS pool. Adapt paths if you
> use ext4/btrfs — drop the sanoid section and point `restic` at whatever
> directories you want to back up.

---

## What you get

```
host (plain ZFS, fast local access)
  ├── sanoid    — automatic local snapshots, pruned by policy
  └── restic    — encrypt + dedup + compress → Hetzner Storage Box (over SSH)
                  retention enforced via `restic forget --prune`
```

- **Snapshots** protect against accidental deletion and ransomware on the
  source. They live on the source pool and cost nothing until data changes.
- **Restic to Hetzner** is the actual off-site backup. Hetzner sees only
  encrypted chunks; even Hetzner staff cannot read them.
- **Retention** is bounded: `--keep-daily`, `--keep-weekly`, etc., so the
  remote repo's size stabilises instead of growing forever.

---

## Setup

### 1. Provision the Storage Box

In the Hetzner panel, create a Storage Box. When prompted for additional
features:

- **SSH Support**: enable. Required for `restic`.
- **External Reachability**: enable if you will connect from outside
  Hetzner's network (i.e. from your home/office). Without it, only Hetzner
  cloud servers can reach the box.
- **SMB / WebDAV**: leave off unless you have another use for them. Less
  surface, fewer credentials.

Note the credentials Hetzner gives you:

- Hostname: `uXXXXXX.your-storagebox.de`
- Username: `uXXXXXX`
- Password: shown once in the panel
- **SSH port: `23`** (not 22 — easy to miss)

### 2. Generate a dedicated SSH key on the source host

Don't reuse a personal key for an unattended service. A dedicated key with
no passphrase is fine because it lives on the host and is single-purpose;
if the host is ever compromised, only this one key needs to be revoked.

As `root` on the source host:

```sh
ssh-keygen -t ed25519 -f /root/.ssh/restic_storagebox -C "host-restic" -N ""
```

### 3. Install the public key on the Storage Box

Hetzner provides a special command, `install-ssh-key`, to do this:

```sh
cat /root/.ssh/restic_storagebox.pub \
  | ssh -p23 uXXXXXX@uXXXXXX.your-storagebox.de install-ssh-key
```

It will ask for the box's password once. Verify key-based auth works:

```sh
ssh -p23 -i /root/.ssh/restic_storagebox uXXXXXX@uXXXXXX.your-storagebox.de ls
```

Should connect without a password prompt.

### 4. Add a host alias in `/root/.ssh/config`

Saves typing and lets `restic` reference the box by a stable short name.

```sshconfig
Host hetzner-backup
    HostName uXXXXXX.your-storagebox.de
    User uXXXXXX
    Port 23
    IdentityFile /root/.ssh/restic_storagebox
    IdentitiesOnly yes
```

```sh
chmod 600 /root/.ssh/config
ssh hetzner-backup ls   # smoke test
```

### 5. Install tools

```sh
apt update && apt install -y restic sanoid
```

### 6. Generate and store the restic passphrase

This is the **single most important secret** in the system. If you lose it,
the backup is unrecoverable garbage. If it leaks, anyone with read access
to the Storage Box can decrypt everything.

Store it in **at least two places**:

1. Your password manager (1Password, Bitwarden, KeePass, etc.).
2. A printed/handwritten copy in a secure physical location, or a second
   independent password manager.

A reasonable passphrase is six diceware words, or 32 random characters from
a CSPRNG. Generate, save, then drop a copy on the host:

```sh
mkdir -p /root/.config/restic
chmod 700 /root/.config/restic

# paste the passphrase into the file with your editor of choice:
$EDITOR /root/.config/restic/password
chmod 600 /root/.config/restic/password
```

### 7. Initialise the restic repository

The repository path is **relative to the SSH user's home directory** on the
Storage Box. Hetzner's SFTP chroots into the user's home, so an absolute
path like `/restic-host` will fail with `SSH_FX_FAILURE`. Use a relative
path:

```sh
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
export RESTIC_REPOSITORY=sftp:hetzner-backup:restic-host
restic init
```

Run once, ever, per repository.

### 8. Create an environment file (optional but handy)

For ad-hoc `restic` commands later:

```sh
cat > /root/.config/restic/env <<'EOF'
export RESTIC_REPOSITORY=sftp:hetzner-backup:restic-host
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
EOF
chmod 600 /root/.config/restic/env
```

Source it when needed:

```sh
. /root/.config/restic/env
restic snapshots
```

Don't put these in `~/.bashrc` — they'll bleed into every shell and you'll
forget where they came from.

### 9. Configure sanoid for ZFS snapshots

The Debian package does **not** create `/etc/sanoid/` — you make it yourself.
The package ships:

- `/usr/share/sanoid/sanoid.defaults.conf` — built-in template defaults that
  sanoid reads automatically. Don't edit; it's overwritten on upgrade.
- `/usr/share/doc/sanoid/examples/sanoid.conf` — a sample user config you
  can crib from.

```sh
mkdir -p /etc/sanoid
```

Create `/etc/sanoid/sanoid.conf`:

```ini
[pool/important-dataset-1]
    use_template = production
[pool/important-dataset-2]
    use_template = production
[pool/bulk-media]
    use_template = bulk

[template_production]
    hourly = 36
    daily = 30
    monthly = 6
    autosnap = yes
    autoprune = yes

[template_bulk]
    daily = 7
    monthly = 2
    autosnap = yes
    autoprune = yes
```

Validate without taking action:

```sh
sanoid --configdir=/etc/sanoid --readonly --verbose
```

Enable the timer (Debian's package ships `sanoid.timer` set to
`OnCalendar=*:0/15`, i.e. every 15 minutes):

```sh
systemctl enable --now sanoid.timer
systemctl list-timers sanoid*
```

### 10. Restic exclude file

Create `/root/.config/restic/excludes`:

```
**/.cache
**/node_modules
**/Trash
**/.Trash-*
**/lost+found
*.iso
*.dmg
```

Add anything else you don't want uploaded — large, replaceable, or
easily-regenerated content.

### 11. Backup wrapper script

Create `/usr/local/sbin/restic-backup.sh`:

```sh
#!/bin/sh
set -eu
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
export RESTIC_REPOSITORY=sftp:hetzner-backup:restic-host

restic backup \
    --exclude-file=/root/.config/restic/excludes \
    --tag scheduled \
    /path/to/back/up/1 /path/to/back/up/2

restic forget --prune \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 24 \
    --keep-yearly 5
```

```sh
chmod +x /usr/local/sbin/restic-backup.sh
```

`forget --prune` is what bounds the repo size. Without it the repository
grows monotonically.

### 12. systemd service

`/etc/systemd/system/restic-backup.service`:

```ini
[Unit]
Description=Encrypted backup to Hetzner Storage Box
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restic-backup.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

`Nice` and `IOSchedulingPriority` keep the backup from starving foreground
work if it runs while you're using the host.

### 13. systemd timer

`/etc/systemd/system/restic-backup.timer`:

```ini
[Unit]
Description=Daily encrypted backup

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
```

`Persistent=true` runs a missed schedule on the next boot. `RandomizedDelaySec`
spreads the load if you have multiple machines pointing at the same target.

### 14. Enable, fire once, verify

```sh
systemctl daemon-reload
systemctl enable --now restic-backup.timer
systemctl list-timers restic-backup*

# Run the first backup now instead of waiting for the timer:
/usr/local/sbin/restic-backup.sh

# Should show one snapshot:
. /root/.config/restic/env
restic snapshots
```

### 15. Test a restore (mandatory)

An untested backup is not a backup. Do this on day one, then again after
any major change to the setup.

```sh
mkdir /tmp/restore-test
restic restore latest \
    --target /tmp/restore-test \
    --include /path/to/some/file
ls /tmp/restore-test/
rm -rf /tmp/restore-test
```

If the file comes back identical, the chain is healthy.

---

## One subaccount per host

Once a second machine backs up to the same box, stop using the main account.
A host authenticating as `uXXXXXX` can read and delete **every** repository on
the box, so any host that gets compromised takes the others' backups with it.
A subaccount is chrooted to its own base directory and cannot see the rest.

Current layout on the BX11 `home02-backup` box:

| Account | Base dir | Used by | Repository |
|---|---|---|---|
| `u586986` | `/` | nothing — password-only break-glass | — |
| `u586986-sub1` | `/restic-home02` | home02 | `sftp:hetzner-backup:.` |
| `u586986-sub2` | `/restic-private-git-forgejo` | private (Forgejo) | `sftp:storagebox:restic` |

Things that are not obvious, each of which cost time:

- **A subaccount gets its own hostname**, not just its own username:
  `uXXXXXX-subN.your-storagebox.de`. Connecting to the main account's hostname
  with a subaccount username fails.
- **`install-ssh-key` works for subaccounts**, run as the subaccount. Its key
  lands in `<base dir>/.ssh/authorized_keys` — inside its own chroot. Pipe the
  public key in and pass `install-ssh-key` as the *remote command*; it is not
  something you can type at a prompt, because the box has no shell.
- **The base dir becomes the account's root**, so repository paths shift. A
  repo at `/restic-home02` addressed as `restic-home02` by the main account
  becomes `.` for a subaccount based there. Verify with a read-only
  `restic snapshots` before changing anything — a wrong path reports "repository
  does not exist", and an unattended job with `restic init` behaviour would
  happily start an empty one.
- **Never set a base dir to `/.ssh/`.** That directory holds the main account's
  `authorized_keys`; an account chrooted there can append its own key and
  escalate to the main account, which defeats the entire point.
- `ls` over SFTP hides dotfiles. Use `ls -a` before concluding `.ssh` is empty.
- Absolute paths do not work in an SFTP session (see step 7) — `mkdir
  /restic-home02/x` fails, `mkdir restic-home02/x` works.

Migrating an existing host onto a subaccount, in order: install its existing
key on the subaccount, repoint the `Host hetzner-backup` block in
`/root/.ssh/config` (`HostName` **and** `User`), test with a read-only
`restic snapshots` against the new path, update `RESTIC_REPOSITORY` in both
`/root/.config/restic/env` and `/usr/local/sbin/restic-backup.sh`, run one real
backup, and only then remove the main account's key from `.ssh/authorized_keys`.

Concurrency is shared across the whole box: a BX11 allows 10 connections and
restic's sftp backend uses several per repository, so stagger the hosts'
timers rather than letting them all fire at 03:30.

---

## Reconnecting from a new machine

If you need to access the repository from another host (recovery,
migration, audit), you need three things:

1. **Network access** to the Storage Box (correct host alias / SSH key, or
   password auth on port 23).
2. **The restic passphrase** — from your password manager.
3. **`restic` installed** on the machine.

Quickest way:

```sh
# Easiest: replicate the ~/.ssh/config alias from the original host
# (Host hetzner-backup ... Port 23 ... IdentityFile ...).
# Then the repo URL is just:
export RESTIC_REPOSITORY=sftp:hetzner-backup:restic-host

# Or, with no SSH config alias, use restic's URL form and set the port
# explicitly:
export RESTIC_REPOSITORY=sftp://uXXXXXX@uXXXXXX.your-storagebox.de:23/./restic-host
# Note: with the URL form, paths after the host are *absolute* by default.
# The `/./` after the port reintroduces a relative-to-home path, which is
# what Hetzner Storage Boxes require.

# Provide the passphrase interactively on a borrowed host — don't drop it
# onto disk:
restic snapshots                       # will prompt for the passphrase
```

Or write the passphrase to a temp file with `chmod 600` and use
`RESTIC_PASSWORD_FILE`. Don't leave it lying around on a non-trusted machine.

---

## Restoring backups

### List what's available

```sh
. /root/.config/restic/env
restic snapshots
restic snapshots --tag scheduled --host my-host
```

### Restore the latest snapshot to a fresh location

```sh
restic restore latest --target /var/restore
```

Restore goes to the absolute path *inside* the target directory. So
`/path/to/data` from the original host ends up at
`/var/restore/path/to/data`.

### Restore a specific path

```sh
restic restore latest \
    --target /var/restore \
    --include /home/alice/Documents
```

### Browse a snapshot like a filesystem

```sh
apt install -y fuse3      # one-time, on Debian/Proxmox 9 (trixie)
mkdir /mnt/restic
restic mount /mnt/restic
# In another shell:
ls /mnt/restic/snapshots/latest/...
fusermount -u /mnt/restic    # when finished
```

`restic mount` uses FUSE. Read-only, safe to poke around in. Great for
fishing out a single file without restoring a whole snapshot.

### Restore an old version of a single file

```sh
restic snapshots                                              # find the snapshot ID
restic restore <snapshot-id> --target /tmp/old --include /etc/foo.conf
```

---

## Maintenance

The system is designed to be hands-off, but a few things are worth doing
periodically.

### Verify repository integrity

Restic's `check` walks the repo and verifies metadata. Run **monthly** at
minimum. Run with `--read-data` quarterly to also re-download and verify
all chunks (slow and bandwidth-intensive but the only way to detect
silent corruption).

```sh
restic check                  # metadata only, fast
restic check --read-data      # full re-verify, slow
```

You can wire this into a separate `restic-check.timer` that fires on the
first of each month. Don't run it concurrently with `backup` runs.

### Inspect repo size and stats

```sh
restic stats                      # logical (sum of file sizes across snapshots)
restic stats --mode raw-data      # actual bytes stored after dedup+compression
restic stats --mode files-by-contents
```

`raw-data` is the number that drives your Hetzner bill.

### Tune retention

If the repo grows too fast, tighten retention in the wrapper script:

```sh
restic forget --prune \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly 3
```

Each `--keep-*` is independent: `--keep-daily 7` keeps the latest 7 *daily-bucketed*
snapshots, even if you take many per day. Run `restic forget --dry-run`
first to see what would go.

### Rotate the SSH key

Annual hygiene. Generate a new key, install it on the Storage Box, then
remove the old one from `~/.ssh/authorized_keys` on the box. Test before
removing.

---

## What this design does NOT protect against

- **Loss of the passphrase.** Your passphrase is the root of the encryption
  chain. Lose it and the backup is rubbish bytes. Multiple copies, in
  different physical/digital locations, are mandatory.
- **Source-side compromise that has time to also reach the Storage Box.**
  An attacker with `root` on the source host has the SSH key and
  passphrase. They could `restic forget --keep-last 1 && restic prune`
  and destroy your history. Mitigations:
  - Enable Storage Box snapshots in the Hetzner panel (a daily cadence
    with 7–10 retained snapshots is a good starting point). They're
    stored on the Storage Box itself (so a total Hetzner account takeover
    can still delete them via the panel), but the `/.zfs` directory is
    **not writable over SFTP/SSH** — meaning an attacker who only has
    your SSH key cannot delete them. That's the threat model snapshots
    actually protect against here.
  - Consider a second backup destination with separate credentials.
  - For higher assurance, run a separate "pull" backup from a third host
    that has read-only access to the source — so a compromise of the
    source can't reach the backup.
- **Bit rot of single-disk source storage.** ZFS scrubs catch this if your
  pool is mirrored or RAIDZ. Don't rely on the backup as your only
  integrity layer.
- **A backup you've never restored.** Tested restores, periodically.

---

## TL;DR cheat sheet

```sh
# Daily, automatic — nothing to do, the timer fires.

# Ad-hoc:
. /root/.config/restic/env
restic snapshots                       # what's there
restic stats --mode raw-data           # how big is the repo really
restic check                           # is it healthy
restic restore latest --target /tmp/r  # get everything back
restic mount /mnt/restic               # browse like a filesystem
```
