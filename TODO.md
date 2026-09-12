# TODO — Pangolin VPS migration (Hetzner → Gigahost)

Full runbook with commands: `docs/pangolin-vps-migration.md`.
Nix config for the new host is written and dry-run verified (`hosts/pangolin/`).

## Prep (can run while ticket is pending)

- [x] Copy salvage off the Hetzner box to desktop (backup until decommission):
      `scp root@91.99.59.171:/root/pangolin-config.tgz ~/Downloads/`
      `scp root@91.99.59.171:/root/sasldb2 ~/Downloads/`
- [x] Domeneshop: lower TTL to 300 on every record pointing at `91.99.59.171`.
- [x] On Gigahost: `nix shell nixpkgs#age --command sudo age-keygen -o /etc/age/host.key`, note public key.
- [x] Add that public key as `&pangolin` in `.sops.yaml` (replace the TODO),
      then `nix shell nixpkgs#sops --command sops updatekeys hosts/pangolin/secrets/secrets.yaml`.
- [x] Fill secrets: `nix shell nixpkgs#sops --command sops hosts/pangolin/secrets/secrets.yaml`
      — `pangolin-server-secret` = THE_SECRET from the Hetzner config.yml,
      `domeneshop_api_token`/`_secret` = same values as the public host.
- [x] Verify the key on the box matches the repo: on Gigahost,
      `sudo nix shell nixpkgs#age --command age-keygen -y /etc/age/host.key`
      must print the `&pangolin` key in `.sops.yaml`
      (`age1skrk03y8gn2zz3ctnf4v83arvqz09gnxl2xj68ljlprfa0wv75tsgtpmt4`).
      Mismatch → sops-nix can't decrypt at activation (no SERVER_SECRET, no
      ACME creds); fix `.sops.yaml` and rerun `sops updatekeys`.
- [ ] Check pangolin version on Hetzner ≤ 1.18.4 (what nixpkgs ships; db
      migrations only run forward): `grep image: /home/thomas/docker-compose.yml`
      or dashboard footer. Newer → bump `services.pangolin.package` to match
      before restoring state.
- [ ] Review + commit + push the repo changes.

## Rebuild + restore (no mail cutover yet)

- [x] On Gigahost: `sudo nixos-rebuild switch --flake <repo>#pangolin`
      (hostname pangoling → pangolin, netbird removed).
- [x] Copy salvage from the desktop to the box:
      `scp ~/Downloads/pangolin-config.tgz ~/Downloads/sasldb2 tagp@193.200.238.206:`
- [x] Restore state as root:
      `mkdir -p /var/lib/pangolin && tar xzf /home/tagp/pangolin-config.tgz -C /var/lib/pangolin`
      `chown -R pangolin:fossorial /var/lib/pangolin`
      `install -o root -g postfix -m 0640 /home/tagp/sasldb2 /etc/sasldb2`
      `systemctl restart pangolin gerbil traefik postfix`
- [ ] Fix ownership for traefik (blanket pangolin:fossorial chown above broke
      the acme store → letsencrypt resolver skipped → default cert → newt
      refuses TLS; and plugins-storage → badger disabled):
      `chown -R traefik:fossorial /var/lib/pangolin/config/letsencrypt /var/lib/pangolin/config/traefik`
      `chmod 700 /var/lib/pangolin/config/letsencrypt`
      `chmod 600 /var/lib/pangolin/config/letsencrypt/acme.json`
      `systemctl restart traefik`
- [x] Test dashboard via hosts-file override
      (`193.200.238.206 pangolin.yesbutmaybe.no`). Login failure =
      SERVER_SECRET mismatch.
- [ ] In the dashboard: confirm game-server raw UDP resources target media's
      newt site (10.2.10.10), not a netbird address.
- [ ] Test inbound 25 reachable from outside: `nix shell nixpkgs#netcat-openbsd --command nc 193.200.238.206 25`
      (confirms Gigahost does not filter inbound).

## Cutover — only after outbound 25 is open and tested

- [x] Rebuild media right before repointing DNS:
      `sudo nixos-rebuild switch --flake ~/nixos#media` (drops netbird, which
      the old Hetzner box's game-server path uses). Game servers stay down
      from this rebuild until the DNS step below lets media's newt reach the
      new box — keep the gap short.
- [x] Domeneshop: point the `91.99.59.171` records at `193.200.238.206`
      (newt clients on public/media reconnect on their own).
- [ ] PTR broken — Gigahost support ticket. Panel appends an extra `.206`
      label, so the record sits at `206.206.238.200.193.in-addr.arpa` instead
      of the zone apex `206.238.200.193.in-addr.arpa`; empty and `@` host are
      rejected, so the apex record cannot be created in the panel. Ask them to
      place PTR `relay.yesbutmaybe.no` at the zone apex. Blocks clean outbound
      mail (PTR/HELO alignment). Verify with:
      `dig -x 193.200.238.206 @ns1.gigahost.no` → `relay.yesbutmaybe.no.`
- [x] Domeneshop SPF: replace `ip4:91.99.59.171` with `ip4:193.200.238.206`.
- [ ] Public host: `relayhost = [ "[193.200.238.206]:587" ]` in
      `hosts/public/modules/mailserver.nix`, update the address field of the
      `mail_relay_sasl_passwd` secret to match, rebuild public.

## Verify, then decommission

- [ ] Dashboard + sites green, HTTP resources reachable.
- [ ] Game servers reachable (27015/udp, 34197/udp).
- [ ] Inbound mail lands on the public host; IMAPS (993) works.
- [ ] Outbound mail: clean score on mail-tester.com, SPF/PTR aligned.
- [ ] `journalctl -u postfix` clean; relay rejects unauthenticated senders.
- [ ] After several clean days: cancel the Hetzner server. Keep the salvage
      tarball until then.

## Later (post-migration hardening, not blocking)

- [ ] CrowdSec + firewall bouncer + traefik bouncer plugin (replaces fail2ban).
- [ ] ntfy + CrowdSec notifications + pam_exec ssh-login alerts
      (shared module, reusable on all hosts).
- [ ] sslh on 443 for ssh-from-anywhere.
- [ ] Try removing traefik `serversTransport.insecureSkipVerify`.
- [ ] Bump nixpkgs for pangolin 1.18.4 → newer (deliberate, after stable).
