# Factorio Server Setup (media VM)

Public Factorio 2.0 server on the `media` VM (VMID 201, home02), run by
**Factorio Server Manager (FSM)** in podman and exposed via a Pangolin raw UDP
resource, mirroring the CS2 setup.

## Architecture

```
client → factorio.yesbutmaybe.no:34197/udp
           │
         pangolin VPS (Gigahost, 193.200.238.206)
           ↓ traefik `udp-34197` entrypoint → raw UDP resource → newt tunnel
         media (NixOS VM)
           ↓ podman
         ofsm/ofsm container
           ├─ factorio headless (UDP 34197) → public via pangolin raw UDP resource
           └─ FSM web UI (HTTP :80)         → 127.0.0.1:8090 only
                                                ↓ Caddy gated vhost (trusted IPs)
                                              https://factorio.ybmn.no
                                                ↓ volumes
                                              /mnt/games/factorio ← virtiofs ← /hddmirror/games (home02)
```

RCON is internal to the container (FSM ↔ factorio on localhost) and is never exposed.
The FSM container auto-downloads the factorio headless binary on first start
(`FACTORIO_VERSION=stable`) — no factorio.com login needed for the binary.

## Files

- `hosts/media/modules/factorio.nix` — FSM podman container + tmpfiles dirs on `/mnt/games/factorio`.
- `hosts/media/default.nix` — imports `factorio.nix`.
- `hosts/media/modules/caddy.nix` — gated vhost `factorio.ybmn.no → 127.0.0.1:8090`.
- `hosts/pangolin/modules/pangolin.nix` — `rawUdpPorts` declares the traefik
  `udp-34197` entrypoint + firewall opening; the raw UDP resource itself
  (34197 → media site `10.2.10.10:34197`) lives in the Pangolin dashboard/db.

No home02 changes: the `games` virtiofs share (`/mnt/games`) is already wired for CS2.

## Manual steps (after rebuild)

1. Add DNS record `factorio.ybmn.no` in domeneshop (same target as other `*.ybmn.no`).
2. Rebuild both hosts:
   - on media:    `sudo nixos-rebuild switch --flake ~/nixos#media`
   - on pangolin: `sudo nixos-rebuild switch --flake ~/nixos#pangolin`
3. Open `https://factorio.ybmn.no`, log in with the FSM default **`admin` / `factorio`**
   (the image ignores ADMIN_USER/ADMIN_PASS — the account is seeded in
   `fsm-data/sqlite.db` on first start). Change it in the UI (Settings → user)
   afterwards.
4. In FSM, enter your factorio.com username + token, then install mods:
   - **administratorio**
   - **Squeak Through**
   - **Long Reach**
   ⚠️ Do **not** enable space-age or quality — administratorio conflicts with them.
5. In server-settings: set the **game password**, server name, and keep
   `require_user_verification = true`.
6. Create/generate a save and start the server.

## Diagnostics

```bash
ssh media 'sudo podman ps'                 # factorio container running?
ssh media 'sudo podman logs -f factorio'   # headless download + "Hosting game"
ssh media 'ss -ulnp | grep 34197'          # UDP listener up
nc -uvz factorio.yesbutmaybe.no 34197
```

## Notes

- `ADMIN_PASS` / `RCON_PASS` are inline in `factorio.nix` (no sops, by choice) — fine
  behind the gated Caddy vhost. Migrate to a `sops.templates` env file (like `cs2.env`)
  later if you want them out of the nix store.
- The game binary and saves persist on `/mnt/games/factorio/factorio`; FSM config/db on
  `/mnt/games/factorio/fsm-data`.
