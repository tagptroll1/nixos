# Factorio Server Setup (media VM)

Public Factorio 2.0 server on the `media` VM (VMID 201, home02), run by
**Factorio Server Manager (FSM)** in podman and exposed via netbird/pangolin, mirroring
the CS2 setup.

## Architecture

```
client → netbird overlay (wt0) OR public internet → <pangolin public>:34197/udp
                                                       │
                                              pangoling (public VM)
                                                ↓ NAT + hairpin DNAT on wt0 → 100.122.55.95:34197
                                              media (NixOS VM)
                                                ↓ podman
                                              ofsm/ofsm container
                                                ├─ factorio headless (UDP 34197) → public via pangoling
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
- `hosts/pangoling/modules/forwarding.nix` — UDP 34197 forward + hairpin DNAT to media.
- `hosts/pangoling/modules/networking.nix` — opens UDP 34197 on pangoling firewall.

No home02 changes: the `games` virtiofs share (`/mnt/games`) is already wired for CS2.

## Manual steps (after rebuild)

1. Add DNS record `factorio.ybmn.no` in domeneshop (same target as other `*.ybmn.no`).
2. Rebuild both hosts:
   - on media:     `sudo nixos-rebuild switch --flake ~/nixos#media`
   - on pangoling: `sudo nixos-rebuild switch --flake ~/nixos#pangoling`
3. Open `https://factorio.ybmn.no`, log in (`tagp` / the `ADMIN_PASS` from factorio.nix).
   Change the password in the UI (Settings) afterwards.
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
# from a netbird client:
nc -uvz <pangolin-host> 34197
```

## Notes

- `ADMIN_PASS` / `RCON_PASS` are inline in `factorio.nix` (no sops, by choice) — fine
  behind gated Caddy + netbird. Migrate to a `sops.templates` env file (like `cs2.env`)
  later if you want them out of the nix store.
- The game binary and saves persist on `/mnt/games/factorio/factorio`; FSM config/db on
  `/mnt/games/factorio/fsm-data`.
