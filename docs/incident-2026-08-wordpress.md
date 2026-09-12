# Incident report - WordPress takeover on public (2026-07-20 → 2026-08-11)

## Summary

`sletteposten.no` (WordPress on the public host) was taken over by an automated
wp2shell campaign exploiting a WordPress **core** vulnerability chain:

- **CVE-2026-63030** - route confusion in the REST batch endpoint
  (`/wp-json/batch/v1`, equivalently `/?rest_route=/batch/v1`). Sub-requests are
  tracked in two parallel arrays; an erroring sub-request shifts them out of
  step, so a request executes under another request's handler and walks past the
  endpoint allow-list unauthenticated.
- **CVE-2026-60137** - `author__not_in` SQL injection, reachable once the batch
  confusion smuggles input past schema validation.

Chained: unauthenticated → forged administrator → remote code execution.
Affected core: 6.9.0-6.9.4 and 7.0.0-7.0.1. Fixed in 6.9.5, 7.0.2, 6.8.6.
The site ran **6.9.4**, installed March 2026 and never updated.

Two independent failures kept it that way. `setup-wordpress` only runs on a
fresh install, so nothing in the config ever updates core. And wp-cron stopped
firing on 2026-04-03 - every hook, `wp_version_check` included, was four months
overdue at detection - so WordPress's own background updates never ran either.
`wp-config.php` sets `DISABLE_WP_CRON`, leaving `wp-cron.service` (curl against
`admin.sletteposten.no`) as the only trigger; its failure was silent.

First compromise **2026-07-20 02:13 CEST**, last observed activity
**2026-08-10 17:46 CEST**. 34 backdoor administrator accounts were created.

Detection was accidental: a bounce message for the WordPress "password changed"
notification. That notification only surfaced because outbound relaying was
*also* broken - see [pangolin-vps-migration.md](pangolin-vps-migration.md).

## Timeline

| When (CEST) | What |
| --- | --- |
| 2026-03-26 | WordPress 6.9.4 deployed by `setup-wordpress`, never updated after |
| 2026-07-11 | Smarthost migrated to Gigahost; SASL auth to the relay starts failing, all outbound mail deferred |
| 2026-07-20 02:13 | First exploit: `POST /?rest_route=/batch/v1` (UA `wp2shell`) creates admin user `wp2_0a5687457866`, immediate login |
| 2026-07-20 → 08-10 | 33 further admin accounts, UA rotated to random Chrome strings with a `_w2s=` cache-buster |
| 2026-08-06 02:56 | Attacker changes the password of the legitimate `karoline` admin account; WordPress notification bounces |
| 2026-08-11 21:4x | Detected. php-fpm pool stopped, site offline |
| 2026-08-11 22:xx | Evidence captured, core updated, accounts evicted, DB password rotated |

## Evidence

- 34 rogue administrators, IDs 2-35, prefixes `wp2_`, `w2s_`, `wpsvc_`, `bunk_`,
  plus `wpadminVUT`, `waflnvXQG`, `yun_11`. `w2s_` is the published IOC.
- Sessions in `wp_usermeta.session_tokens` were live at detection.
- Access log, initial breach:
  `POST /?rest_route=/batch/v1 → 207`, then `GET /wp-login.php`,
  then `POST /wp-login.php → 302`, all within 3 seconds.
- Every recorded client IP is `10.0.10.10` - the Pangolin tunnel address. No
  attacker IP exists anywhere in the logs; the log format did not capture
  `X-Forwarded-For`.

## Did they get code execution?

The chain ends in RCE by design, so the capability was there. No artifact of it
was found. Against the pre-update web root snapshot:

- `core verify-checksums --version=6.9.4` clean - no core file modified.
- `wp-content/plugins` holds only `akismet` and `superb-blocks`; `mu-plugins`
  only the nix-managed hardening symlink. wp2shell's documented payload is a
  fake plugin - absent.
- No PHP under `wp-content/uploads`.
- No `plugin-install`, `theme-install`, `plugin-editor` or `theme-editor` POSTs
  anywhere in the retained logs.

- `active_plugins` lists only `superb-blocks`; `wp cron event list` shows 12
  hooks, all stock WordPress plus one from that plugin; no `base64_decode` or
  `eval(` anywhere in the database dump.
- The 34 `oembed_cache` posts created alongside the accounts hold ordinary embed
  markup for an existing post, a side effect of the exploit querying
  `/wp/v2/posts`.

Assessment: the attacker used the vulnerability to mint administrator accounts
and stopped there. No code execution artifact and no persistence, on disk or in
the database.

Note two local evidence sources were destroyed during response and cannot be
recovered: `core update --force` rewrote every core file, and
`chown -R nginx:nginx` reset ctime across the tree. The pre-update tarball
predates both, which is why it carries the verdict.

## Blast radius

WordPress PHP runs as the **`nginx`** user. Anything that user could read was
readable to the attacker.

Reachable:

- `wp-config.php` - database credentials (password was `wordpress`). Rotated.
- The whole nginx web root, all vhosts served by nginx.
- **ACME certificate material**: `users.users.nginx.extraGroups = [ "acme" ]`,
  so every private key under `/var/lib/acme` was group-readable - including
  `mail.yesbutmaybe.no`. Assume disclosed; renew.
- **Local mail submission**: postfix `mynetworks` contains `127.0.0.0/8`, so
  anything on the box can send as any `@yesbutmaybe.no` address without
  authentication. Domain reputation risk.
- **Outbound network**: the firewall filters inbound only. From the box the
  attacker could reach any routed subnet - private (10.0.20.0/24), media
  (10.2.10.0/24), server (10.0.0.0/24, Proxmox and Grafana). Nothing records
  outbound flows, so this cannot be confirmed or excluded from local data.

Not reachable as `nginx`:

- sops secrets in `/run/secrets` - root-owned, mode 0400 (`newt` tunnel
  credentials, Domeneshop API keys, GitHub token, mail account hashes).
- SSH private keys under `/home/tagp` (0600, owner `tagp`).
- Other service accounts: `byggogbedrag`, `postfix`, `dovecot2`, `vmail`.
- SSH itself: `PermitRootLogin no`, `PasswordAuthentication false`, key-only.

## Actions taken

1. `phpfpm-wordpress` stopped and masked in `/run/systemd/system`.
2. Evidence captured to `/root`: DB dump, web root tarball, nginx logs.
3. Core updated to a patched release, `--force` rewriting all core files;
   `core verify-checksums` clean.
4. Rogue accounts deleted, salts shuffled (invalidates every session),
   `karoline` password reset, MariaDB `wordpress` user password rotated.

## Config changes

| File | Change |
| --- | --- |
| `hosts/public/modules/wordpress.nix` | Block the batch endpoint in both spellings (`if ($args ~* "batch(/\|%2f)v1")` + `location ~ ^/wp-json/batch/`) |
| `hosts/public/modules/wordpress.nix` | `set_real_ip_from 10.0.10.10` + `real_ip_header X-Forwarded-For` on the tunnel vhost, so client IPs are real |
| `hosts/public/modules/wordpress.nix` | `$http_x_forwarded_for` added to `log_format wordpress_combined` |
| `hosts/public/modules/wordpress.nix` | `wp-update` service + daily timer: core, plugin and theme updates via wp-cli |
| `hosts/public/modules/wordpress.nix` | `wp-cron` runs `wp cron event run --due-now` instead of curling `wp-cron.php`; the curl form exits 0 on a 502, which is how the queue stalled from 2026-04-03 unnoticed |
| `hosts/public/modules/exporters.nix` | nginxlog exporter format kept in sync with the new log format |
| `hosts/public/modules/mailserver.nix` | `postfix-queue-check` service + hourly timer, alerts on mail deferred over an hour |
| `shared/modules/unit-failure-mail.nix` | New: `notify-failure@.service` template, mails a journal excerpt on unit failure. Wired to `wp-update` |
| `hosts/public/modules/wordpress.nix` | php-fpm pool runs as a dedicated `wordpress` user instead of `nginx`; nginx dropped from the `acme` group, which is what exposed the mail certificate key |
| `hosts/public/modules/wordpress.nix` | `/wp-admin` and `wp-login.php` denied on the public tunnel vhost (admin-ajax.php excepted); administration goes through `admin.sletteposten.no` |
| `hosts/public/modules/wordpress.nix` | MariaDB bound to 127.0.0.1 |
| `flake.lock` | All inputs updated (nixpkgs 2026-06-16 → 2026-08-10) |

Alerts deliver **locally** via `sendmail`, not through the smarthost, so a
broken relay cannot silence them.

## TODO

Ordered. Nothing here is done.

### Done and verified on public

- [x] Pre-update tarball scanned; plugin and mu-plugin inventory clean; DB dump
      free of `eval(` / `base64_decode`; no plugin/theme install POSTs.
- [x] Rebuilt. php-fpm unmasked and running as `wordpress`, webroot owned by it,
      `nginx` out of the `acme` group, MariaDB on 127.0.0.1, no failed units.
- [x] Core on 7.0.3. wp-cron drains cleanly (`0 cron events` due).
- [x] Blocking verified: `batch/v1` (both spellings) 403 on both vhosts,
      `/wp-admin/` and `/wp-login.php` 403 on the public vhost and reachable on
      `admin.sletteposten.no`, `admin-ajax.php` still executing, site root 200.
- [x] Failure alerting proven end to end - a real `wp-cron` failure produced a
      mail with the journal excerpt attached.

### Mail relay

Root cause: `smtpd_sasl_local_domain` was unset on the relay, so cyrus-sasl
derived the lookup realm from the machine's own hostname and searched for
`relay@pangolin`. The account is stored as `relay@yesbutmaybe.no`
(`saslpasswd2 -u yesbutmaybe.no`) and the client sends a bare `relay`, so every
attempt failed with `535`. The hostname changing during the migration is what
turned a working setup into a broken one. Fixed by pinning the realm in
`hosts/pangolin/modules/mail-relay.nix`.

- [x] Fixed. The stored password was correct all along; pinning the realm was
      the whole fix. Queue flushed and drained - four messages delivered
      `status=sent`, the oldest after 4.4 days deferred.

### Migration leftovers

- [ ] Fix traefik ownership under `/var/lib/pangolin/config` (letsencrypt +
      traefik dirs), restart traefik.
- [ ] PTR record for 193.200.238.206 → `relay.yesbutmaybe.no` (Gigahost ticket).
- [ ] Confirm game-server raw UDP resources target media's newt site.
- [ ] Test inbound 25 from outside.
- [ ] Verify outbound mail scores clean (SPF/DKIM/PTR) before decommissioning
      the Hetzner box.

### Credentials

- [ ] Replace the interim WordPress and MariaDB passwords with generated ones -
      the interim values reuse a system login password, which lives in
      `wp-config.php` (0640, readable by `nginx`).
- [ ] Change that system login password itself, on every host where it is used.

### Hardening

- [ ] Renew every ACME certificate on public and treat the old keys as
      disclosed. Not yet done - `systemctl start` on the acme units is a no-op
      because they are `RemainAfterExit` oneshots still showing the July run.
      Use `systemctl restart`, clear the lego cache under
      `/var/lib/acme/.lego/<domain>`, then restart nginx, postfix and dovecot
      and confirm a fresh `notBefore`.
- [x] `nginx` removed from the `acme` group; WordPress has its own php-fpm user.
- [x] `wp-login.php` and `/wp-admin` denied on the public vhost.
- [ ] CrowdSec + firewall bouncer (already on the migration list).
- [ ] Alert on failed systemd units generally, not only `wp-update` - a
      Prometheus rule over the node exporter's systemd collector covers all of
      them at once.
