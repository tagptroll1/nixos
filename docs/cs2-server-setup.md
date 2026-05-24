# CS2 dedicated server — full setup reference

What it takes to bring the CS2 server on the `media` VM up from scratch, or
rebuild it on a fresh host. Most of the config is declarative in the flake;
this doc captures the **non-flake prerequisites** (home02-side virtiofs, sops
secrets, Steam API key) plus the rationale for the design decisions that
aren't obvious from reading the Nix code.

---

## Architecture at a glance

```
laptop (CS2 client)
    │
    │ netbird overlay (wt0)         OR        public internet
    │  → 100.x.x.x                            → tv2.yesbutmaybe.no:27015
    ▼                                            │
    pangoling (public VM)  ◄── DNAT (ens18 OR wt0 hairpin) ──┘
        │                                                     
        │ wt0 overlay → 100.122.55.95
        ▼
    media (NixOS VM, VMID 201 on home02)
        │
        │ podman → cs2 container (kus/cs2-modded-server)
        ▼
    /mnt/games  ←──── virtiofs ────  /hddmirror/games on home02
                                        (40 GB game install + workshop)
```

Key choices:

- **kus/cs2-modded-server** image (not joedwards32/cs2). joedwards32 doesn't
  support MetaMod cleanly on this host's filesystem layout — we spent half a
  day chasing the `[META] Could not open folder /addons/metamod` path-resolution
  bug. kus ships MetaMod + CounterStrikeSharp + plugins as a single tested
  bundle.
- **Dedicated `games` virtiofs share** (not on `/mnt/media`). systemd-tmpfiles
  refuses to chown across the `/mnt/media` (immich-owned) → subdirs ownership
  boundary, which broke the original setup. A separate `/mnt/games` share
  owned by the Debian `games` user (uid 5 / gid 60) avoids the transition.
- **Hairpin DNAT on pangoling's `wt0`** so netbird clients can reach the
  public hostname through the overlay (default NixOS `networking.nat` only
  DNATs on the external interface).

---

## Manual prerequisites (one-time, not in flake)

### 1. Steam Web API key (one-off, mandatory for workshop downloads)

Register at https://steamcommunity.com/dev/apikey (any domain works,
e.g. `ybmn.no`). Save the key.

Add it to sops on the workstation:

```bash
cd ~/nixos
sops hosts/media/secrets/cs2Secret.yaml
# add line:  api_key: <your-key>
```

The sops mapping is already declared in `hosts/media/default.nix` as
`cs2/api_key` → file `cs2Secret.yaml` key `api_key`.

### 2. home02 — games user + virtiofs share

Full how-to (with rationale) is in
[`private/proxmox-virtiofs-shares.md`](./private/proxmox-virtiofs-shares.md). One-shot
summary for the cs2 case:

```bash
# On home02, as root:
usermod -aG games tagp
mkdir /hddmirror/games
chown games:games /hddmirror/games
chmod 2770 /hddmirror/games   # setgid → children inherit `games` group

tee -a /etc/pve/mapping/directory.cfg <<'EOF'

games
    map node=home02,path=/hddmirror/games
    description cs2 + future game server data
EOF

qm set 201 --virtiofs4 games
qm shutdown 201 && sleep 15 && qm start 201   # virtiofs is not hot-pluggable
```

After this, `mount | grep games` on the media VM should show
`games on /mnt/games type virtiofs`.

### 3. Workshop collection ID

The flake hardcodes collection `3731836451` (TV2 maps). If you ever swap
collections, the ID is in
`hosts/media/modules/cs2.nix` as `workshopCollections`, **and** referenced
in the workshop paths inside
`hosts/media/modules/cs2-presets/gamemodes_server.txt` (the `mg_comp` block).

---

## What's in the flake

| File | Purpose |
|------|---------|
| `hosts/media/modules/cs2.nix` | Container, env vars, volumes, ExecStartPre that drops preseeded files into custom_files |
| `hosts/media/modules/cs2-presets/gamemodes_server.txt` | Map pool override — `mg_comp` reduced to just the 9 TV2 workshop maps |
| `hosts/media/modules/storage.nix` | `games` virtiofs mount + matching `games` user/group (uid 5 / gid 60) + `tagp` in games group |
| `hosts/media/default.nix` | sops mapping `cs2/api_key` |
| `hosts/media/secrets/cs2Secret.yaml` | Encrypted secrets: `rcon_pw`, `server_pw`, `api_key` |
| `hosts/pangoling/modules/forwarding.nix` | DNAT for 27015/udp on both `ens18` (public) and `wt0` (overlay hairpin) |

Preseeded into `/mnt/games/cs2-modded-custom/` by ExecStartPre on every
container start (idempotent `install` commands):

- `addons/counterstrikesharp/configs/admins.json` — tagp as root admin
- `subscribed_collection_ids.txt` — `3731836451`
- `subscribed_file_ids.txt` — empty (overrides kus's defaults so we don't
  pull surf/bhop/kz/etc. workshop maps)
- `gamemodes_server.txt` — curated map pool

---

## Bringing it up from scratch

```bash
# 1. Workstation
cd ~/nixos
sops hosts/media/secrets/cs2Secret.yaml   # add api_key
git push                                   # if anything to push

# 2. home02 — do the prerequisites in section 2 above

# 3. media
cd ~/nixos && git pull
sudo nixos-rebuild switch --flake ~/nixos#media

# 4. pangoling (only if forwarding.nix changed)
ssh pangoling 'cd ~/nixos && git pull && sudo nixos-rebuild switch --flake ~/nixos#pangoling'

# 5. Verify
ssh media 'mount | grep games'           # → games on /mnt/games type virtiofs
ssh media 'systemctl is-active podman-cs2'
ssh media 'sudo podman logs --tail 50 cs2 | grep -iE "metamod|cssharp|workshop"'
```

First container start downloads ~40 GB via SteamCMD — give it 10–20 min.

---

## Operational notes

### Adding/changing maps

The map pool is in `hosts/media/modules/cs2-presets/gamemodes_server.txt`,
specifically the `mg_comp` block. Add workshop entries as:

```
"workshop/<numeric_id>/<map_bsp_name>"    ""
```

The `<map_bsp_name>` is the actual map name CS2 uses — **not** the workshop
title. To find it: subscribe + load the map once, check the server log for
`SV: Spawn Server: <name>` or `maplist { ... }`. If you guess wrong, the
map silently won't show up in votes.

After editing, redeploy:
```bash
git push && ssh media 'cd ~/nixos && git pull && sudo nixos-rebuild switch --flake ~/nixos#media && sudo systemctl restart podman-cs2'
```

### Adding/changing admins

Edit the `adminsJson` block in `hosts/media/modules/cs2.nix`. It's a Nix
attrset rendered via `builtins.toJSON`, so adding an admin is just adding
another attribute. Identity is SteamID64 (not SteamID2 — that was an early
mistake in this conversation). Flags `["@css/root"]` = all permissions.

### Diagnosing the container

```bash
# Container service state
ssh media 'systemctl status podman-cs2 --no-pager -l | head -20'

# Live logs (most recent 200 lines, follow)
ssh media 'sudo podman logs --tail 200 -f cs2'

# Plugin load status — should see MetaMod + CounterStrikeSharp + ~10 plugins
ssh media 'sudo podman logs cs2 2>&1 | grep -iE "metamod|cssharp|Loaded.*plugin" | head -20'

# What maps the server actually has for the current mode
ssh media 'sudo podman logs cs2 2>&1 | grep -A20 "maplist {" | tail -30'
```

### Resetting the install

If something gets corrupted:

```bash
ssh media 'sudo systemctl stop podman-cs2'
ssh media 'sudo rm -rf /mnt/games/cs2-modded /mnt/games/cs2-modded-custom'
ssh media 'sudo systemctl start podman-cs2'   # ExecStartPre recreates dirs
```

40 GB re-download follows.

### What the kus image gives us out-of-box (no extra config)

- **MetaMod:Source + CounterStrikeSharp** — plugin runtime
- **CS2-SimpleAdmin** — `!admin` menu (uses SQLite by default, no DB setup needed)
- **CS2-CustomVotes + GameModeManager** — `!rtv`, `!nominate`, `!vote <mode>`,
  end-of-map vote, mode switching via menu
- **MultiAddonManager** — workshop collection support (downloads via SteamCMD,
  changes maps with `host_workshop_changelevel`)
- **InventorySimulator** — players see their loadouts when connected
- ~20 other quality-of-life plugins

In-game commands (default):
- `!rtv` — start a rock-the-vote (players vote next map)
- `!nominate <partial>` — nominate a map for the end-of-map vote
- `!vote changemode` — vote to switch game mode (deathmatch / comp / wingman / etc.)
- `!maps` — list maps in current mode
- `!admin` — admin menu (root admins only)
