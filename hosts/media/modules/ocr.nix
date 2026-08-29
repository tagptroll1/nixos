{
  config,
  lib,
  pkgs,
  ...
}:
let
  # financio-ocr reads a photographed till receipt into its lines. It runs on
  # this host because this is the machine with the GPU; the ledger it serves
  # lives on private, which has none.
  #
  # The binary is built by the Forgejo runner on private and pushed here, the
  # same shape as financio itself (hosts/private/modules/financio.nix). It is
  # deliberately not a nix package even though it could be one - pure Go, no
  # cgo, no frontend. The code lives in Forgejo on private, and media is not
  # allowed to open connections back to private, so media cannot fetch it. The
  # allowed direction is private pushing here, so that is the direction the
  # binary travels.
  #
  # The trade-off, written down because it is not the usual one: a NixOS
  # generation rollback does NOT roll this application back. To undo a bad
  # deploy, point `current` at the previous release and restart:
  #
  #   ln -sfn <sha> /var/lib/financio-ocr-releases/current.tmp
  #   mv -T /var/lib/financio-ocr-releases/current.tmp /var/lib/financio-ocr-releases/current
  #   systemctl restart financio-ocr
  releases = "/var/lib/financio-ocr-releases";
  binary = "${releases}/current/financio-ocr";

  # The one client. financio posts receipt images and waits for the lines back.
  financioHost = "10.0.20.5";
  port = 8099;

  model = "qwen2.5vl:7b";

  # The runner's whole vocabulary on this host. Its key is bound to this script
  # with an authorized_keys `command=`, so nothing else can be run with it - not
  # a shell, not an arbitrary rsync, not a path outside the releases directory.
  #
  # Two verbs, mirroring what CI does: put the binary somewhere, then say so.
  # The say-so is what the path unit below watches, which is why the runner
  # still needs no sudo, no root unit and no credential that executes anything.
  deployShell = pkgs.writeShellApplication {
    name = "financio-ocr-deploy-shell";
    runtimeInputs = with pkgs; [
      coreutils
      rsync
    ];
    text = ''
      cmd=''${SSH_ORIGINAL_COMMAND:-}

      case "$cmd" in
        # rsync's own server side. --server is what the client end invokes; the
        # destination it was given is checked below, because rsync will happily
        # write wherever it is pointed.
        "rsync --server "*)
          case "$cmd" in
            *" ${releases}/"*) ;;
            *) echo "financio-ocr-deploy: rsync outside ${releases} refused" >&2; exit 1 ;;
          esac
          case "$cmd" in
            *..*) echo "financio-ocr-deploy: .. in path refused" >&2; exit 1 ;;
            *) ;;
          esac
          exec $cmd
          ;;

        # publish <sha>: make an uploaded release the current one. The symlink
        # is swapped by rename, so a half-written upload can never be the thing
        # systemd starts.
        "publish "*)
          sha=''${cmd#publish }
          case "$sha" in
            *[!0-9a-f]* | "") echo "financio-ocr-deploy: not a commit sha" >&2; exit 1 ;;
            *) ;;
          esac
          if [ ! -x "${releases}/$sha/financio-ocr" ]; then
            echo "financio-ocr-deploy: no binary at ${releases}/$sha" >&2
            exit 1
          fi
          ln -sfn "$sha" "${releases}/current.tmp"
          mv -T "${releases}/current.tmp" "${releases}/current"
          touch "${releases}/.stamp"
          echo "published $sha"
          ;;

        *)
          echo "financio-ocr-deploy: refused" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  services.ollama = {
    enable = true;

    # Stock ollama-cuda is built for compute capability 7.5 and up - nixpkgs'
    # default capability list for CUDA 12.9 has no Pascal in it, so the
    # unmodified package finds this card and cannot use it. sm_61 is GP104,
    # the GTX 1070 in gpu.nix. Building the one architecture also makes this
    # compile roughly nine times smaller than the default nine-architecture
    # build, which matters because ollama-cuda is unfree and therefore never
    # in the binary cache - this host compiles it itself.
    #
    # (There is no `acceleration` option in this nixpkgs; the package is the
    # option.)
    package = pkgs.ollama-cuda.override { cudaArches = [ "sm_61" ]; };

    # Loopback only. financio talks to financio-ocr, never to Ollama.
    host = "127.0.0.1";
    port = 11434;

    loadModels = [ model ];

    environmentVariables = {
      # Unload the model as soon as a receipt is done. It is about 6 GB and
      # this card has 8, which immich is already using for NVENC transcoding
      # and its ML jobs (immich.nix). Receipts arrive a few times a week and
      # the read is asynchronous, so paying ~15s to load the model each time is
      # much cheaper than holding three quarters of the card between them.
      OLLAMA_KEEP_ALIVE = "60s";
      OLLAMA_MAX_LOADED_MODELS = "1";

      # Pascal has no usable fp16 path, and llama.cpp's flash attention kernels
      # need sm_80. Off explicitly, so a nixpkgs bump that changes the default
      # cannot quietly turn it on here.
      OLLAMA_FLASH_ATTENTION = "false";
    };
  };

  # A static user: it owns the releases directory, which a dynamic uid cannot.
  users.users.financio-ocr-deploy = {
    isSystemUser = true;
    group = "financio-ocr-deploy";
    home = releases;
    # Needs a real shell for sshd to run the forced command through it.
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      # The Forgejo runner on private. `restrict` turns off every forwarding
      # and tty feature; `command=` means the key can do nothing but the two
      # verbs in deployShell above.
      #
      # Replace REPLACE-WITH-RUNNER-PUBLIC-KEY with the public half of the key
      # in hosts/private/secrets/financioOcrSecret.yaml. Generate the pair on
      # any machine, keep the private half in sops:
      #   ssh-keygen -t ed25519 -N "" -C forgejo-runner@private -f /tmp/ocrdeploy
      ''command="${lib.getExe deployShell}",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ64bKvkMWLB2d1VlTM5FtcG0WgpxFzlcpTUvkTnU5l/ forgejo-runner@private''
    ];
  };
  users.groups.financio-ocr-deploy = { };

  # 0755: the runner writes here and root reads it. Nothing secret is in it -
  # it holds built binaries.
  systemd.tmpfiles.rules = [
    "d ${releases} 0755 financio-ocr-deploy financio-ocr-deploy - -"
  ];

  systemd.services.financio-ocr = {
    description = "financio-ocr - receipt reading for financio";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "ollama.service"
    ];
    wants = [
      "network-online.target"
      "ollama.service"
    ];

    environment = {
      OCR_PORT = toString port;
      # Reachable from private, which is the whole point of it living here. The
      # firewall rule below is what narrows that to one address.
      OCR_BIND_ADDR = "0.0.0.0";
      OLLAMA_URL = "http://127.0.0.1:11434";
      OCR_MODEL = model;
      # A 7B vision model on a Pascal card is slow, and a receipt in several
      # parts is one model call per part, plus a re-read when the lines do not
      # add up to the total. The client sets its own deadline; this only has to
      # be longer than a legitimate read.
      OCR_TIMEOUT = "10m";
    };

    serviceConfig = {
      ExecStart = binary;
      Restart = "on-failure";
      RestartSec = 5;

      # Stateless by design: it writes nothing and remembers nothing between
      # requests, because financio owns every image and every result. So it
      # gets no state directory and no writable path at all.
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      # wazero compiles the HEIC decoder to machine code at runtime, so this
      # one cannot be turned on.
      MemoryDenyWriteExecute = false;
      SystemCallFilter = [ "@system-service" ];
      SystemCallErrorNumber = "EPERM";
    };
  };

  # CI touches .stamp as the last thing a green build does. Watching a file the
  # runner writes is what keeps the runner privilege-free: it can put a binary
  # in a directory and say so, and this host decides what that means.
  systemd.paths.financio-ocr-deploy = {
    description = "financio-ocr release watcher";
    wantedBy = [ "multi-user.target" ];

    pathConfig.PathModified = "${releases}/.stamp";
  };

  systemd.services.financio-ocr-deploy = {
    description = "financio-ocr deploy";

    path = with pkgs; [
      coreutils
      systemd
    ];

    serviceConfig.Type = "oneshot";

    script = ''
      set -euo pipefail

      rev=$(readlink ${releases}/current || true)
      if [ -z "$rev" ]; then
        echo "no current release to deploy" >&2
        exit 1
      fi

      # Logged on every deploy so `journalctl -u financio-ocr-deploy` answers
      # "what is running and where did it come from" on its own.
      echo "deploying financio-ocr $rev"
      systemctl restart financio-ocr.service
    '';
  };

  # Same shape as immich-public-proxy.nix: the port is not opened generally,
  # one source address is let through. Receipt photographs are personal, and
  # this host runs plenty else.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s ${financioHost} -p tcp --dport ${toString port} -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -s ${financioHost} -p tcp --dport ${toString port} -j nixos-fw-accept || true
  '';

  # Deliberately not behind this host's Caddy. Its shared trustedMatcher
  # (caddy.nix) does not include private's 10.0.20.0/24, and widening it would
  # open every other gated service here; and private resolves through
  # 8.8.8.8/1.1.1.1, so it cannot resolve a split-DNS *.ybmn.no name anyway.
}
