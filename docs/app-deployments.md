# Apps on `private` — deployments, env and secrets

Everything self-hosted on `private` that you wrote or build yourself. Two shapes,
because they are genuinely different problems:

| Shape | Example | Artifact | What moves it forward |
| --- | --- | --- | --- |
| **Container** | anything new | OCI image in the Forgejo registry | `podman auto-update`, hourly |
| **Bare binary** | `financio` | a directory under `/var/lib/financio-releases` | a stamp file and a root path unit |

`financio` is the odd one out on purpose: it is cgo + a pnpm frontend, and
packaging that as a nix derivation means carrying two content hashes in this
repo. Everything after it should be a container, and then it is six lines.

---

## Architecture at a glance

```
you: git push origin master
    │
    ▼
Forgejo (private, 127.0.0.1:3000) ──► forgejo-runner (native:host, same VM)
                                          │
        ┌─────────────────────────────────┴──────────────────────────┐
        │ containerised app                          financio        │
        ▼                                                ▼
  podman build + push                          go build -o financio
  git.ybmn.no/tagp/<app>:master                install -Dm755 → releases/<sha>/
        │                                      ln -sfn <sha> current
        │                                      touch releases/.stamp
        ▼                                                ▼
  podman-auto-update.timer (hourly)            financio-deploy.path
   digest moved? pull, restart,                 → financio-deploy.service (root)
   roll back if it will not start                 → systemctl restart financio
        │                                                ▼
        │                                      CI polls /api/health until the
        │                                      sha matches, then goes green
        ▼                                                ▼
     <app>.service                                 financio.service
     127.0.0.1:<port>                              127.0.0.1:8086
        └───────────────► Caddy (lanOnly) ◄────────────────┘
                          https://<name>.ybmn.no
```

---

## Adding an app

Declare it in `hosts/private/default.nix` (or its own module):

```nix
my.apps.grafana = {
  image  = "git.ybmn.no/tagp/grafana:master";
  port   = 8090;
  domain = "graf.ybmn.no";
  secretFile = ./containers/grafana/secret.yaml;   # optional
};
```

`hosts/private/modules/apps.nix` turns that into: the quadlet container with the
auto-update label, the Caddy vhost behind the LAN allowlist, the sops entry,
`/var/lib/grafana` **and its line in the restic job**, `/var/lib/appenv/grafana.env`
with a watcher that restarts the app when you edit it, and a memory cap.

Options are documented in the module itself. The ones worth knowing:

| Option | Default | Note |
| --- | --- | --- |
| `port` | — | host loopback port; eval fails if two apps collide or you pick one the host already uses |
| `domain` | `null` | `null` means no vhost at all |
| `lanOnly` | `true` | off means the internet, so say it out loud |
| `state` | `true` | creates `/var/lib/<name>`, mounts it at `/data`, **and backs it up** |
| `memory` | `512m` | so one app cannot take the host down with it |
| `extraContainerConfig` | `{}` | escape hatch; option names come from quadlet-nix's `container.nix` |

Then things nix cannot do for you:

1. **DNS.** A record for `<name>.ybmn.no` in domeneshop. Or, once you are tired
   of this, one `*.ybmn.no` wildcard record and a wildcard certificate — that
   also retires the slow-propagation dance below.
2. **The image.** A workflow in the app's repo that builds and pushes to
   `git.ybmn.no/tagp/<app>:master`. The tag must be a **moving** one:
   auto-update compares digests behind a tag, it does not discover new tags.
3. **Registry credentials** — see below. Until they exist, every pull of a
   private image 401s and the app silently never updates.

Then `sudo nixos-rebuild switch --flake ~/nixos#private`.

A rebuild per *app*, never per *deploy*. That is the line: it buys Caddy, sops,
the firewall and the backup staying in one place, and it is the step where this
stops short of being a control plane.

---

## Managing deployments

### Containers

Push an image; within the hour it is live.

```sh
podman auto-update --dry-run          # what would move, and to what
systemctl start podman-auto-update    # do it now instead of waiting
journalctl -u podman-auto-update -n 50
```

Rollback is podman's own: if the new image will not start, auto-update reverts
to the previous one by itself. To go back deliberately, push the old digest to
the tag again, or `podman tag`/`podman run` the previous image and let the next
run reconcile.

### financio

```sh
systemctl status financio
journalctl -u financio-deploy -n 50        # the sha of every deploy, in order
ls -l /var/lib/financio-releases           # current -> the sha that is running
/var/lib/financio-releases/current/financio version
curl -s localhost:8086/api/health          # {"status":"ok","version":"<sha>"}
```

Rollback is a symlink swap, **not** a NixOS generation rollback — the binary is
not in the nix store, so rolling the system back does not roll the app back:

```sh
cd /var/lib/financio-releases
ln -sfn <previous-sha> current.tmp && mv -T current.tmp current
systemctl restart financio
```

The five most recent releases are kept; older ones are pruned on every deploy.

---

## Managing env

Two files per app, read in order, later wins.

| | Where | Changing it |
| --- | --- | --- |
| Secrets | `/run/secrets/<app>/env`, from sops | **rebuild** |
| Everything else | `/var/lib/appenv/<app>.env` | edit, and it restarts itself |

```sh
sudo -e /var/lib/appenv/financio.env     # or any app's file
journalctl -u financio-env -n 20         # confirms the restart happened
```

The file is created empty by tmpfiles and never touched again, so a rebuild
cannot clobber an edit. Deleting the contents is how you go back to the
defaults.

Three things to know:

- **It overrides the nix definition.** Setting `PORT` here without moving the
  Caddy upstream in `networking.nix` takes the site down. That is the price of
  being able to change anything without a rebuild.
- **The watcher is `PathChanged`**, which catches the rename `sudo -e` and vim
  do. A script that writes the file in place with `>` also works.
- **It is invisible to git.** The nix repo no longer fully describes what is
  running. When something behaves unlike the config says it should, this
  directory is the first place to look.

---

## Managing secrets

sops-nix, age, exactly as everything else on this host — `docs/sops-age-operations.md`
has the key handling. Per app:

```
hosts/private/containers/<app>/secret.yaml     # encrypted, one key: env
```

with a dotenv blob as the value:

```yaml
env: |
  API_TOKEN=...
  DATABASE_URL=...
```

Referenced by `my.apps.<app>.secretFile`, decrypted to `/run/secrets/<app>/env`,
mode 0400 root — rootful podman reads it as root and nothing else needs to.

**A secret change needs a rebuild.** sops-nix decrypts from a store path pinned
at switch time; re-encrypting the yaml changes nothing until you switch. This is
the reason for the split above: put anything you expect to tune at 2am in the
mutable env file, and keep sops for credentials, which rotate rarely.

### Registry credentials (not done yet)

`podman auto-update` runs as root on a timer and needs an authfile to pull from
the Forgejo registry. Create a Forgejo token with package read scope, put a
docker config json in a sops secret, and point `my.registryAuthFile` at its
path. Until then, only public images update.

---

## Known gaps

- **`hello` does not auto-update.** It uses `image = "docker-archive:..."`, a
  nix-built local archive, which auto-update cannot reconcile. It is a demo; a
  real app uses a registry reference.
- **Rootful vs rootless.** `hosts/private/modules/users.nix` defines a `podman`
  service account with a home-manager profile, and `hello`'s secret is owned by
  it - but `virtualisation.quadlet.containers` at system level runs containers as
  root, which is how `hello` itself is declared. The generated app secrets are
  `mode = "0400"` root for that reason. Worth settling on one of the two before
  there are ten of them.
- **No failure alerting on `private`.** `shared/modules/unit-failure-mail.nix`
  exists but is not imported here, and delivery is local postfix on `public`.
  For now, uptime-kuma is the thing that notices — add a check per app when you
  add the app.
- **No wildcard certificate.** Every new name is its own DNS record and its own
  slow first issuance.
