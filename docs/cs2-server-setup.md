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

### 3. Workshop maps (no collection)

There is **no workshop collection** anymore. Every custom map is referenced
directly by id in `gamemodes_server.txt` as `workshop/<id>/<bsp_name>` (the kus
image downloads it on changelevel via the Steam `API_KEY`). To add a map, add
the line to the relevant `mg_*` group — see *Adding/changing maps* below.

---

## What's in the flake

| File | Purpose |
|------|---------|
| `hosts/media/modules/cs2.nix` | Container, env vars, volumes, ExecStartPre that drops preseeded files + plugin binaries into custom_files |
| `hosts/media/modules/cs2-presets/gamemodes_server.txt` | Map pool override — stock kus pool + our `mg_hns` (3 HnS maps) + new `mg_prophunt` (normal maps for the plugin). Workshop maps referenced directly by id — no collection. |
| `hosts/media/modules/cs2-presets/GameModeManager.json` | Stock GMM config + an added **Prop Hunt** mode (`prophunt.cfg`, `mg_prophunt`). `ChangeImmediately`/`EnabledInWarmup` set true. |
| `hosts/media/modules/cs2-presets/prophunt*.cfg`, `unload_plugins.cfg` | Prop Hunt mode cfg chain + the unload override that gates the plugin (see Prop Hunt section). |
| `hosts/media/modules/cs2-presets/PropHunt.json`, `prophunt-maps/*.txt` | PropHunt plugin config + per-map prop-model lists. |
| `hosts/media/modules/storage.nix` | `games` virtiofs mount + matching `games` user/group (uid 5 / gid 60) + `tagp` in games group |
| `hosts/media/default.nix` | sops mapping `cs2/api_key` |
| `hosts/media/secrets/cs2Secret.yaml` | Encrypted secrets: `rcon_pw`, `server_pw`, `api_key` |
| `hosts/pangoling/modules/forwarding.nix` | DNAT for 27015/udp on both `ens18` (public) and `wt0` (overlay hairpin) |

Preseeded into `/mnt/games/cs2-modded-custom/` by ExecStartPre on every
container start (idempotent `install` commands):

- `addons/counterstrikesharp/configs/admins.json` — tagp as root admin
- `gamemodes_server.txt` — curated map pool (workshop maps referenced by id)
- `addons/counterstrikesharp/configs/plugins/GameModeManager/GameModeManager.json`
- `cfg/custom_all.cfg`, `cfg/custom_comp.cfg` — global + competitive overrides
- Prop Hunt: plugin binaries (PropHunt + CS2MenuManager), `PropHunt.json`,
  per-map model lists, and the `prophunt*.cfg` / `unload_plugins.cfg` chain
  (see the **Prop Hunt** section below)

> The old `subscribed_collection_ids.txt` (collection `3731836451`) is **no
> longer used** — maps are referenced directly by workshop id in
> `gamemodes_server.txt`. ExecStartPre removes the stale file on each start.

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
# Prop Hunt deps present (CS2MenuManager auto-loads; PropHunt loads on !mode prophunt)
ssh media 'sudo podman logs cs2 2>&1 | grep -iE "MenuManager|Prop Hunt"'
```

First container start downloads ~40 GB via SteamCMD — give it 10–20 min.

---

## Operational notes

### Adding/changing maps

The map pool is in `hosts/media/modules/cs2-presets/gamemodes_server.txt`.
Each game mode draws from one or more `mg_*` groups (see `GameModeManager.json`
→ `GameModes[].MapGroups`). Add workshop entries to the relevant group as:

```
"workshop/<numeric_id>/<map_bsp_name>"    ""
```

The `<map_bsp_name>` is the actual map name CS2 uses — **not** the workshop
title. To find it: subscribe + load the map once, check the server log for
`SV: Spawn Server: <name>` or `maplist { ... }`. If you guess wrong, the
map silently won't show up in votes.

**Keep a map in exactly one mode's group.** The old setup merged prophunt/HnS
maps into `mg_comp`, so end-of-map RTV could load them under *competitive*
rules. Maps now live in a single group: comp maps in `mg_comp`, hide-n-seek in
`mg_hns`, prop hunt in `mg_prophunt`.

After editing, redeploy:
```bash
git push && ssh media 'cd ~/nixos && git pull && sudo nixos-rebuild switch --flake ~/nixos#media && sudo systemctl restart podman-cs2'
```

### Prop Hunt

Prop Hunt is a **server-side plugin** ([exkludera/PropHunt][ph]), *not* the
workshop VScript prophunt maps (those gate their `!config` menu to the listen
host, which doesn't exist on a dedicated server — that's why they were dropped).
The plugin turns hiders into physics props on **normal** maps.

How it's wired:

- **Binaries** are fetched reproducibly in `cs2.nix` (`unpackZip` → `fetchurl`
  with pinned zip hashes) and dropped into custom_files by the `seedPlugins`
  script: `PropHunt` into `plugins/disabled/` (gated), `CS2MenuManager` (its
  menu dependency, not in the kus image) into active `plugins/` + `shared/`.
  MultiAddonManager (the other dependency) already ships in the image.
- **Gated load:** `prophunt.cfg` does `css_plugins load "plugins/disabled/PropHunt/PropHunt.dll"`
  and registers the mode with `css_gamemode "Prop Hunt"`. Our `unload_plugins.cfg`
  override adds `css_plugins unload "Prop Hunt"`, so switching to any other mode
  unloads it (otherwise its round-start handler turns hiders into props
  everywhere). Chain: `prophunt.cfg` → `prophunt_settings.cfg` →
  `custom_prophunt.cfg` (your tuning point).
- **Gameplay knobs** (hiding team/time, decoy/swap/taunt limits, sounds) live in
  `cs2-presets/PropHunt.json`.

**Prop models per map.** The plugin reads `plugins/PropHunt/maps/<mapname>.txt`
(newline-separated `.vmdl` paths) *and* auto-harvests the map's own
`prop_physics_multiplayer` models at runtime. So:

- Maps in `mg_prophunt` (`de_dust2`, `de_inferno`, `de_mirage`, `de_nuke`) each
  have a seed file in `cs2-presets/prophunt-maps/`. `de_dust2` ships a real
  model; the others seed the same known-valid model + rely on auto-harvest.
- To curate good props for a map: play it, then read the server log for lines
  `(OnEntitySpawned) added: <model>` — those are the real, valid vmdl paths on
  that map. Paste the good ones into the map's `.txt`, redeploy, restart. Wrong
  paths fail safe (skipped / error model), they don't crash.
- To add prophunt on a new map: add it to the `mg_prophunt` group in
  `gamemodes_server.txt`, create `cs2-presets/prophunt-maps/<map>.txt`, and add
  an `install` line for it in `cs2.nix`.

**Bumping plugin versions.** Update the `url` + `hash` in `cs2.nix` for
`propHunt` / `cs2MenuManager`. Compute the SRI hash of the release zip with:
`sha256-$(curl -sL <zip-url> | openssl dgst -sha256 -binary | openssl base64 -A)`.
PropHunt is **alpha (v0.0.1)** — expect rough edges.

[ph]: https://github.com/exkludera-cssharp/PropHunt

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
