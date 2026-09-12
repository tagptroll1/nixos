# Pangolin VPS migration

Move Pangolin + mail relay from the Hetzner Ubuntu box (91.99.59.171) to the
Norwegian VPS (193.200.238.206), reinstalled from the NixOS ISO as the
`pangolin` host in this flake. Both VPSs end up consolidated into this one
machine; the Hetzner box is decommissioned at the end.

## Before touching anything

- [ ] Ask the provider (or test) that **outbound port 25** is open from the
      Norwegian VPS. Without it the relay cannot deliver mail. Test from the
      current pangoling install: `nc -w5 gmail-smtp-in.l.google.com 25`.
- [ ] Lower TTL on all Domeneshop records pointing at `91.99.59.171`
      (audit which: dashboard, MX target, relay, game server names, resource
      subdomains) to 300s, a day before cutover.
- [ ] Check the pangolin version on the Hetzner box is ≤ 1.18.4 (what the
      flake's nixpkgs ships): `grep image: /home/thomas/docker-compose.yml`
      or the dashboard footer. Pangolin migrates its sqlite db forward on
      startup, never backward — a db from a newer version cannot be restored
      into 1.18.4. If newer, bump `services.pangolin.package` first.
- [ ] Verify traefik entrypoint names used by the raw resources:
      `cat /home/thomas/config/traefik/traefik_config.yml` on the Hetzner box.
      They must match `services.traefik.staticConfigOptions.entryPoints` in
      `hosts/pangolin/modules/pangolin.nix` (currently `tcp-25`, `tcp-993`,
      `udp-27015`, `udp-34197`). Fix the nix side if they differ.

## Salvage from the Hetzner box

```bash
# Pangolin state: sqlite db, gerbil key, traefik acme certs
tar czf pangolin-config.tgz -C /home/thomas config
# SASL accounts for the 587 relay
cp /etc/sasldb2 .
# server.secret (goes into sops as pangolin-server-secret)
grep -A1 'secret' /home/thomas/config/config.yml
```

Copy `pangolin-config.tgz` and `sasldb2` somewhere safe off the box.

## Rebuild the Norwegian VPS in place

The machine already runs NixOS (the retired pangoling config), so no ISO or
partitioning — `hosts/pangolin/hardware-configuration.nix` carries the
existing disk layout.

1. Generate the host age key and register it:
   ```bash
   sudo age-keygen -o /etc/age/host.key   # note the public key
   ```
   Add the public key as `&pangolin` in `.sops.yaml` (replacing the TODO),
   then from the repo: `sops updatekeys hosts/pangolin/secrets/secrets.yaml`.
2. Fill real secret values: `sops hosts/pangolin/secrets/secrets.yaml`
   (`pangolin-server-secret` from the salvaged config.yml, Domeneshop
   token/secret same as the public host's).
3. Commit + push, then on the machine:
   `sudo nixos-rebuild switch --flake <repo>#pangolin`
   (hostname changes pangoling → pangolin; netbird is dropped by the new
   config).

## Restore state

From the desktop, copy the salvage onto the box:

```bash
scp ~/Downloads/pangolin-config.tgz ~/Downloads/sasldb2 tagp@193.200.238.206:
```

Then as root on the box:

```bash
# Pangolin db + gerbil key + certs
mkdir -p /var/lib/pangolin
tar xzf /home/tagp/pangolin-config.tgz -C /var/lib/pangolin
chown -R pangolin:fossorial /var/lib/pangolin
# traefik (not pangolin) must own its dataDir and the acme store — otherwise
# the letsencrypt resolver is skipped (default cert, newt refuses TLS) and
# the badger plugin cannot install.
chown -R traefik:fossorial /var/lib/pangolin/config/letsencrypt /var/lib/pangolin/config/traefik
chmod 700 /var/lib/pangolin/config/letsencrypt
chmod 600 /var/lib/pangolin/config/letsencrypt/acme.json
# SASL relay accounts
install -o root -g postfix -m 0640 /home/tagp/sasldb2 /etc/sasldb2
```

Then `systemctl restart pangolin gerbil traefik postfix` and check the
dashboard loads at https://pangolin.yesbutmaybe.no (via hosts-file override
until DNS moves) and that login works — if login fails, SERVER_SECRET does
not match the db.

## Cutover

1. Point the Domeneshop records from `91.99.59.171` to `193.200.238.206`.
   Newt clients (public, media) reconnect on their own since the endpoint is
   `pangolin.yesbutmaybe.no`.
2. Set **PTR** for `193.200.238.206` → `relay.yesbutmaybe.no` in the provider
   panel.
3. Update **SPF** in Domeneshop: replace `ip4:91.99.59.171` with
   `ip4:193.200.238.206`.
4. On the public host: change `relayhost` in
   `hosts/public/modules/mailserver.nix` to `[193.200.238.206]:587` and
   update the first field of the `mail_relay_sasl_passwd` secret to match
   (postfix looks the password up by the relayhost string). Rebuild public.

## Verify

- [ ] Dashboard login, sites green, HTTP resources reachable.
- [ ] Game servers reachable (CS2 27015/udp, Factorio 34197/udp).
- [ ] Inbound mail: send from external → lands on public host (25 + 993
      raw resources).
- [ ] Outbound mail: send via relay from a SASL device; check
      https://www.mail-tester.com score, SPF/PTR alignment.
- [ ] `journalctl -u postfix` clean; no open-relay (test from unauthed IP).

## Decommission

Only after several days of clean mail delivery: cancel the Hetzner server.
Keep the salvaged tarball until then.
