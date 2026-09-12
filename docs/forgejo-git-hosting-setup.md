# Forgejo git hosting + build server — full setup reference

Self-hosted git for projects that should not live on GitHub, doubling as the
build server for them. Runs on the `private` VM. The service itself is
declarative (`hosts/private/modules/forgejo.nix`, `forgejo-runner.nix`,
`restic.nix`); this doc captures the **non-flake prerequisites** — Hetzner
Storage Box subaccount, sops secrets, DNS, the admin user, the runner
registration token — plus why it lives where it does.

---

## Architecture at a glance

```
browser / git client (LAN or tailnet)
    │
    │ https://git.ybmn.no                    git@git.ybmn.no:2222
    ▼                                             │
  Caddy on private (lanOnly guard)                │
    │ reverse_proxy 127.0.0.1:3000               │ Forgejo's built-in ssh
    ▼                                             ▼
  Forgejo (NixOS VM `private`, 10.0.20.5)
    │ state: /mnt/data/forgejo  (2.7T ext4 `vmdata` disk, sqlite + repos + LFS)
    │
    ├── gitea-actions-runner ──► native:host jobs (nix, go, pnpm, node on PATH)
    │
    └── restic (01:30 nightly)
            │ sftp port 23, key from sops
            ▼
        Hetzner Storage Box BX11 "home02-backup"
        subaccount u586986-sub2 → /restic-private-git-forgejo/restic
```

---

## Why private, and not media or an LXC on home02

Measured 2026-08-26:

| | private | media | home02 (Proxmox host) |
|---|---|---|---|
| CPU | 4 vCPU | 12 vCPU | 16 physical cores |
| RAM | 39G total, 37G free | 23G total, 11G available | 31G total, **3G available** |
| root disk free | 355G (+2.6T on `/mnt/data`) | 73G | — |
| load | 0.00 | ~2.0 | 0.56 |

- **media loses on contention, not core count.** Its 12 vCPU are an allocation
  against home02's 16 physical cores, already shared with Jellyfin, immich,
  opencloud and the game servers. A build competing with a Zomboid tick or a
  transcode is worse than a slower build that always runs.
- **An LXC on home02 is worse still.** It inherits exactly the same contention,
  gets ~3G of RAM headroom, falls outside the flake (no sops, no
  `nixos-rebuild`, no rollback by generation), needs `nesting=1` for
  container-based CI jobs, and puts arbitrary build code one namespace away
  from the ZFS pool everything is restored from.
- **private is a different physical machine**, idle, with the right security
  zone: its Caddy already refuses anything outside LAN/tailnet.

The backup argument that originally favoured media does not survive contact
with the details: home02's restic job backs up **ZFS datasets on the Proxmox
host**, not the media VM's `/var/lib`. On media, backup would have been a path
choice; on private it is a second restic repo. Same amount of thinking, and
private wins everything else.

---

## Key choices

- **Forgejo, not Gitea or GitLab.** `services.forgejo` is a first-class NixOS
  module (default package `forgejo-lts`), sqlite needs no external DB, and
  Forgejo Actions gives GitHub-compatible CI without a second system. GitLab CE
  wants Postgres + Redis + Sidekiq + Puma + Gitaly and runs forward-only DB
  migrations that cannot be rolled back by switching generations — the same
  trap documented for pangolin in `flake.nix`.
- **State on `/mnt/data`, not `/var/lib`.** Repos, LFS objects and CI working
  directories go on the 2.7T `vmdata` disk instead of the root filesystem that
  also holds the nix store.
- **Forgejo's built-in ssh server on 2222**, rather than `DISABLE_SSH=false`
  against the host sshd. The alternative needs an `authorized_keys` file
  managed by Forgejo outside nix.
- **`native:host` runner label.** Jobs run directly on the host with an
  explicit `hostPackages` PATH — no docker, no podman in the loop. Anything a
  workflow calls must be listed in `hostPackages`; there is no other PATH.
- **sqlite `.backup` before each restic run.** The live db is excluded from the
  backup set; a consistent copy is written to `/mnt/data/backup` first. Git
  repositories are append-mostly and dedup well as plain files, so they are
  backed up directly rather than through `forgejo dump` — a compressed dump
  archive would not dedup between runs and would grow the remote repo by its
  full size every night.
- **Backup at 01:30.** home02's job runs 03:30 +30m jitter, and the BX11 allows
  10 concurrent connections; restic's sftp backend uses several per repo.

---

## Storage Box account layout

See `encrypted-backup-to-hetzner-storage-box.md` for the per-host subaccount
pattern and its gotchas. Summary of who owns what:

| Account | Base dir | Used by | restic repo path |
|---|---|---|---|
| `u586986` | `/` | nothing — password-only break-glass | — |
| `u586986-sub1` | `/restic-home02` | home02 | `sftp:hetzner-backup:.` |
| `u586986-sub2` | `/restic-private-git-forgejo` | private | `sftp:storagebox:restic` |

---

## Manual setup

### 1. Storage Box subaccount

Console → the box → Subaccounts → Create subaccount. SSH on, base dir
`/restic-private-git-forgejo`, read-only off.

Generate a dedicated key on the desktop and install it — the password is needed
exactly once, and stops mattering afterwards:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/private-restic -C "private-restic" -N ""
cat ~/.ssh/private-restic.pub | ssh -p23 u586986-sub2@u586986-sub2.your-storagebox.de install-ssh-key
ssh -p23 -i ~/.ssh/private-restic u586986-sub2@u586986-sub2.your-storagebox.de ls
```

Empty output from the last command is correct — the directory starts empty.

### 2. restic passphrase

```sh
nix shell nixpkgs#openssl -c openssl rand -base64 32
```

Separate secret from home02's. Into the password manager **and** one offline
copy before continuing: there is no reset path for a restic repository.

Day to day it is never typed — sops-nix decrypts it at activation. It is needed
only to restore from a machine that is not private. It stays recoverable from
this repo as long as the **admin age key** survives, which makes that key the
real single point of failure.

### 3. sops secrets

```sh
nix shell nixpkgs#sops -c sops hosts/private/secrets/resticSecret.yaml
```

```yaml
password: <the passphrase>
ssh_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <contents of ~/.ssh/private-restic>
  -----END OPENSSH PRIVATE KEY-----
```

`.sops.yaml` already matches `hosts/private/secrets/*.yaml` for the `admin` and
`private` keys — no rule changes needed.

### 4. DNS

Domeneshop: CNAME `git` → `private.ybmn.no.`, the same shape as `status` and
`file`. The tailscale split DNS covers off-LAN access with no extra config.

### 5. Rebuild

```sh
sudo nixos-rebuild switch --flake ~/nixos#private
```

### 6. Admin user

`INSTALL_LOCK` is always true under the NixOS module and registration is
disabled, so the first account comes from the CLI:

```sh
sudo -u forgejo env FORGEJO_WORK_DIR=/mnt/data/forgejo FORGEJO_CUSTOM=/mnt/data/forgejo/custom \
  $(systemctl show -p ExecStart --value forgejo | sed -n 's/.*path=\([^ ;]*\).*/\1/p') \
  admin user create --username <name> --email <addr> --admin --random-password
```

It prints the generated password. Log in at `https://git.ybmn.no` and change it.

### 7. First backup

root has never seen the Storage Box's host key. Do it once, deliberately,
rather than letting a timer be the first thing to trust it:

```sh
sudo ssh -p23 -i /run/secrets/restic/ssh_key u586986-sub2@u586986-sub2.your-storagebox.de ls
sudo systemctl start restic-backups-private
sudo restic-private snapshots
```

`restic-private` is the wrapper the restic module installs; it already has the
repository and password set.

Then the step everyone skips, while nothing depends on it yet:

```sh
sudo restic-private restore latest --target /tmp/restoretest
```

### 8. Actions runner

The runner needs a registration token that only exists once Forgejo is running,
so this step comes after the service is up. On a rebuild from scratch, leave
`./modules/forgejo-runner.nix` and the `forgejo/runner_token` secret out of
`hosts/private/default.nix` until Forgejo has started and issued a token.

1. Forgejo → Site Administration → Actions → Runners → Create registration token.
2. Store it — note the value must be a **whole env-file line**, since the module
   takes an environment file, not a bare token:

   ```sh
   nix shell nixpkgs#sops -c sops hosts/private/secrets/forgejoSecret.yaml
   ```
   ```yaml
   runner_token: TOKEN=<the registration token>
   ```
3. Uncomment `./modules/forgejo-runner.nix` and the `forgejo/runner_token`
   secret in `hosts/private/default.nix`.
4. Rebuild, then `systemctl status gitea-runner-private`. The runner should
   report **Idle** in the admin UI.

The runner talks to `http://127.0.0.1:3000` directly, not through Caddy — the
vhost is `remote_ip` restricted and would answer 403 to a request from
localhost.

---

## Mirroring to GitHub

Forgejo has no bidirectional sync. Pull mirrors (remote → Forgejo) can only be
created at repository creation and are read-only afterwards; push mirrors
(Forgejo → remote) **force push** and overwrite the remote. Running both
against one repository means the last job to run wins, and commits are lost.

The workable shape is Forgejo authoritative with a push mirror to a private
GitHub repo, "sync when new commits are pushed" enabled, and GitHub treated as
read-only. Push mirrors carry git refs only — issues, PRs, releases, wiki and
Actions config do not travel, and LFS over SSH is unsupported (use an HTTPS
remote).

One repository that should keep an off-site copy regardless: `tagptroll1/nixos`
itself. Restoring the forge needs the restic passphrase, which lives
sops-encrypted in that repo — making the forge its only home builds a loop that
only breaks with the offline passphrase copy.
