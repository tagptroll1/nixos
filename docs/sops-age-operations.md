# sops + age — common operations

How secrets work in this repo and the recipes for the operations you'll do most often.

## What's in the box

- **Encryption tool**: [sops](https://github.com/getsops/sops) (Arch package: `sops`)
- **Key tool**: `age` / `age-keygen` (Arch package: `age`) — supports post-quantum keys natively via `-pq` flag
- **NixOS integration**: [sops-nix](https://github.com/Mic92/sops-nix) — decrypts secrets at activation time using the host's age key

All keys in this repo are **post-quantum** (`age1pq1...` prefix). Generated with `age-keygen -pq`. No external plugin needed.

## Repo layout

- `.sops.yaml` — root config: anchored age public keys + creation rules per host
- `hosts/<host>/secrets/*.yaml` — encrypted secret files for that host
- `hosts/<host>/containers/<name>/secret.yaml` — per-container secret (private only)

Each host has its own age key. Secrets are encrypted to `&admin` (your laptop) plus the target `&<host>` so only that host can decrypt at activation time. The admin key can decrypt everything for editing.

## Where the host key lives on each NixOS host

```nix
sops.age.keyFile = "/etc/age/host.key";
```

You manually drop the private key file there once, after first NixOS install, before first rebuild.

## Operations

### Add a new host

1. **Generate a key on your laptop**:
   ```bash
   age-keygen -pq -o ~/<host>-host.key
   ```
   The public line `Public key: age1pq1...` prints to stdout. Stash the private file in Proton Pass.

2. **Add the public key to `.sops.yaml`** as a new anchor:
   ```yaml
   keys:
     - &admin age1pq1...
     - &<host> age1pq1<paste-public-line>
   ```

3. **Add a creation rule** under `creation_rules:`:
   ```yaml
   - path_regex: hosts/<host>/secrets/[^/]+\.(yaml|json|env|ini)$
     key_groups:
     - age:
       - *admin
       - *<host>
   ```

4. **Place the private key on the host** after NixOS install, before first rebuild:
   ```bash
   sudo mkdir -p /etc/age && sudo chmod 700 /etc/age
   sudo mv <host>-host.key /etc/age/host.key
   sudo chown root:root /etc/age/host.key
   sudo chmod 600 /etc/age/host.key
   ```

5. **Reference `sops.age.keyFile = "/etc/age/host.key";`** in the host's `default.nix`.

### Create a new encrypted secret

Sops decides recipients from the path's matching `creation_rules` entry — you don't pass keys explicitly.

```bash
cd ~/nixos
mkdir -p hosts/<host>/secrets
sops hosts/<host>/secrets/<name>.yaml   # opens $EDITOR
```

Write plain YAML in the editor:
```yaml
token: <secret-value>
api_key: <another-value>
```
Save and close. The file on disk is now encrypted ciphertext. Commit it.

### Edit an existing secret

```bash
sops hosts/<host>/secrets/<name>.yaml
```
Sops decrypts in memory, opens your editor on plaintext, re-encrypts on save. Same recipients are preserved.

### View a secret without editing

```bash
sops -d hosts/<host>/secrets/<name>.yaml
```
Or extract one key:
```bash
sops -d --extract '["token"]' hosts/<host>/secrets/<name>.yaml
```

### Reuse a secret across hosts

Two ways:

**(a) Re-encrypt the same plaintext in a new file for the other host** — clean separation, recommended when each host should own its copy:
```bash
sops -d hosts/source/secrets/foo.yaml > /tmp/plain.yaml
mkdir -p hosts/target/secrets
sops -e --input-type yaml --output-type yaml /tmp/plain.yaml > hosts/target/secrets/foo.yaml
shred -u /tmp/plain.yaml
```
The output's recipients come from the matching `creation_rule` for `hosts/target/secrets/`.

**(b) Add the other host's key as an additional recipient on the existing file** — couples both hosts to one secret file:

Edit the relevant `creation_rules` entry to include both anchors, then **re-key** existing files:
```bash
sops updatekeys hosts/source/secrets/foo.yaml
```

(a) is what we did for the Gigahost key (private → media).

### Rotate a host's age key (compromised, lost, etc.)

1. Generate replacement: `age-keygen -pq -o ~/<host>-host.key`
2. Replace the public key under the host's anchor in `.sops.yaml`
3. Re-key every file the host can decrypt:
   ```bash
   sops updatekeys hosts/<host>/secrets/*.yaml
   ```
4. Replace `/etc/age/host.key` on the host
5. `nixos-rebuild switch` to confirm decryption still works

### Rotate the admin key

Same as above, but every secret in the repo needs `sops updatekeys`. Easiest:
```bash
find hosts -path '*/secrets/*' -name '*.yaml' -exec sops updatekeys {} \;
```

### Verify a host can decrypt its secrets without rebuilding

On the host:
```bash
SOPS_AGE_KEY_FILE=/etc/age/host.key sops -d /path/to/secret.yaml
```

### Reference a secret from a NixOS module

In `hosts/<host>/default.nix` (or any imported module):
```nix
sops.secrets."caddy/gigahost_env" = {
  sopsFile = ./secrets/caddySecret.yaml;
  key = "gigahost_env";
  owner = "caddy";
};
```
Then in the service:
```nix
services.caddy.serviceConfig.EnvironmentFile =
  config.sops.secrets."caddy/gigahost_env".path;
```
Path resolves at runtime to `/run/secrets/caddy/gigahost_env` (a tmpfs file owned by `caddy`).

## Troubleshooting

- **`Failed to get the data key` on rebuild**: host's `/etc/age/host.key` is missing, wrong, or its public key isn't in `.sops.yaml` recipients for that file. Check with `sops -d` on the host.
- **`No matching creation rule found`**: the path doesn't match any `path_regex` in `.sops.yaml`. Add a rule before creating files in a new directory.
- **Editor opens with binary garbage**: you opened the encrypted file directly instead of via `sops`. Always `sops <file>`, not `vim <file>`.
- **`sops updatekeys` does nothing**: you forgot to update `.sops.yaml` first; updatekeys re-encrypts to whatever `.sops.yaml` currently says.
