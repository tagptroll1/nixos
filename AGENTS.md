# OpenCode Project Instructions

Read `CLAUDE.md` immediately before any work and treat it as mandatory project guidance.

## Imported Memory

Memory snapshot date: 2026-09-06. Before work involving a topic below, read its detailed
file from `@claude-knowledge/projects/nix-nixos/memory/`. Load only relevant files.

- `announce-ssh-commands.md` - describe why and exact command before every SSH call.
- `no-sudo-on-vms.md` - never use sudo over SSH; hand privileged commands to user.
- `ssh-desktop-key.md` - public/private SSH requires `-i ~/.ssh/desktop`.
- `no-history-comments.md` - comments describe current code, never prior versions.
- `no-git-mutations.md` - read-only git; use `path:.` flake refs for untracked eval.
- `pangolin-vps-infra.md` - native NixOS Pangolin ingress, retired infrastructure and
  intentionally inactive domains.
- `sops-via-nix-shell.md` - invoke sops with `nix shell nixpkgs#sops -c`.
- `traefik-badger-plugin-download.md` - Pangolin restart failure mode where badger fetch
  causes HTTP routers to return 404.
- `forgejo-on-private.md` - Forgejo/build host placement and media backup boundary.
- `hetzner-storagebox-subaccounts.md` - BX11 account and per-host subaccount layout.
- `dont-imply-user-skipped-a-step.md` - stale evidence does not prove user skipped prior
  instruction.

If index and detailed file disagree, detailed file wins. Verify time-sensitive state in
current repo or host before relying on snapshot.
