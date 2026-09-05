{
  config,
  lib,
  pkgs,
  inputs,
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

  # The model servers financio-ocr talks to. Loopback only - nothing but
  # financio-ocr ever calls them.
  llamaPort = 8081;
  classifyPort = 8083;

  /*
    The model that names each receipt line's category. An instruct model, on the
    CPU, and it replaced an embedding model doing the same job: a till prints
    brands - YOPLAIT KVARG, FRYDENLUND JUICY - and knowing those are dairy and
    beer is world knowledge the embedding of the words does not carry. Measured
    against financio's real tree, 3 of 9 lines became 9 of 9.

    4B at Q4_K_M, ~2.5 GB. Six threads read an eleven-line receipt in ~50s on
    this box, close enough to the service's deadline to trip it, hence ten
    below. The category list is the same prompt prefix every time, so
    llama-server's cache carries most of the prefill between receipts. The card
    is not involved, which is the point: it must never take VRAM the reader
    needs.
  */
  classifyRepo = "unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M";

  # Qwen2.5-VL 3B at Q8_0, with the Q8_0 projector.
  #
  # The quantisation is not a detail. At Q4_K_M this model collapses two
  # identical adjacent rows into one - two bottles of the same beer come back
  # as a single line - deterministically, in six runs, at 0.82, 1.2 and 2.0 MP
  # alike. Q8_0 of the same model reads both rows every time. Measured on this
  # card against the two fixtures in the service repo.
  #
  # Bigger was tried. Qwen3-VL-8B-Q4_K_M is the only candidate that also
  # prefers the card amount over a rounded printed TOTAL, but it wants
  # 6.3 GB against this model's 4.6 GB, which leaves immich's ML container
  # nothing, and it wobbles on the quantity of a "3 x 24,90" row. Qwen3-VL-4B
  # loses that quantity too. This one keeps it.
  modelRepo = "ggml-org/Qwen2.5-VL-3B-Instruct-GGUF:Q8_0";
  mmprojURL = "https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf";

  # llama.cpp built for this card. The capability list has to be set through a
  # nixpkgs instance, because llama-cpp takes its architectures from
  # cudaPackages rather than from a package argument: nixpkgs' default list for
  # CUDA 12.9 starts at 7.5 and this GTX 1070 (GP104) is 6.1, so the stock
  # package finds the card and cannot use it. Building the one architecture
  # also keeps the compile small, which matters because anything CUDA is
  # unfree and therefore never in the binary cache - this host compiles it.
  llamaCpp =
    (import inputs.nixpkgs {
      inherit (pkgs.stdenv.hostPlatform) system;
      config = {
        allowUnfree = true;
        cudaSupport = true;
        cudaCapabilities = [ "6.1" ];
      };
    }).llama-cpp;

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
  # llama.cpp serves the model. This replaced ollama, which could not put this
  # model on this card at all: ollama reserves a fixed ~4.9 GB for the vision
  # encoder's warmup - sized for a 1288x1288 dummy image unrelated to anything
  # we send - so the encoder had to be pushed onto the CPU sideways, by pinning
  # 28 of 37 layers, and a read took 50-100 seconds per image.
  #
  # llama.cpp sizes the vision graph from the real image. The encoder costs
  # ~400 MB, every layer stays on the card, and the same image reads in ~12
  # seconds. Measured here, not inferred.
  services.llama-cpp = {
    enable = true;
    package = llamaCpp;

    settings = {
      # Loopback only. financio talks to financio-ocr, never to this.
      host = "127.0.0.1";
      port = llamaPort;

      # Weights and projector are fetched on first start into
      # /var/cache/llama-cpp (LLAMA_CACHE, set by the module) and reused after
      # that. The projector is named explicitly because -hf would otherwise
      # pick one for us, and which one it picks is not a detail we want
      # decided elsewhere.
      hf-repo = modelRepo;
      mmproj-url = mmprojURL;

      # Everything on the card, encoder included. This is the whole difference
      # from the ollama arrangement.
      n-gpu-layers = 999;

      # One slot. The default is four, which splits the KV cache four ways for
      # a service that reads one image at a time; financio-ocr serialises on
      # its own side anyway.
      parallel = 1;

      # Prompt and answer together. 8192 rather than something smaller because
      # of a measured receipt: 20 items came to 2111 tokens of image and
      # prompt and 1985 generated, and at 4096 the answer stopped mid-array.
      # The cost is about 150 MB of KV cache.
      ctx-size = 8192;

      # Pascal has no usable fp16 path and llama.cpp's flash attention kernels
      # need sm_80. Off explicitly, so a nixpkgs bump that changes the default
      # cannot quietly turn it on here.
      flash-attn = "off";

      # The warmup decodes a dummy token and buys nothing here - every real
      # request carries an image, and nothing is cached between them anyway.
      no-warmup = true;

      # Give the card back when no one is reading a receipt. This is the one
      # thing ollama did better, through OLLAMA_KEEP_ALIVE, and llama-server
      # has it too: on sleep the model, the KV cache and the vision compute
      # buffer are all released, and the next request reloads them.
      #
      # It matters more here than it did there, because the compute buffer
      # never shrinks on its own - once a read has allocated it, the process
      # holds ~6.1 GB of this 8 GB card for as long as it runs. Receipts arrive
      # a few times a week. immich wants the card the rest of the time.
      #
      # 60s mirrors the old OLLAMA_KEEP_ALIVE, and the cost is a model reload
      # on the first read after an idle spell - seconds, against an extraction
      # that is asynchronous anyway.
      #
      # Verified rather than assumed: /health and /v1/models both answer while
      # the server is asleep and neither wakes it, so financio-ocr's health
      # probe - which financio polls every 30s with the receipts tab open -
      # cannot hold the model resident. Only a real read does.
      sleep-idle-seconds = 60;
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

  /*
    The classifier, written out by hand because `services.llama-cpp` is a
    singleton and the vision model already has it.

    Stock pkgs.llama-cpp, no CUDA, and that is the design rather than a
    limitation - this must never take VRAM the reader needs, and on the CPU it
    is fast enough that there is nothing to gain.
  */
  systemd.services.llama-cpp-classify = {
    description = "llama.cpp instruct server - receipt line categories";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = toString [
        (lib.getExe' pkgs.llama-cpp "llama-server")
        "--hf-repo ${classifyRepo}"
        "--host 127.0.0.1"
        "--port ${toString classifyPort}"

        # The category list, the rules and twenty lines fit in well under half
        # of this; the rest is headroom for a larger tree.
        "--ctx-size 8192"

        # One slot: the whole context belongs to the request in flight, and the
        # prompt cache keeps the category list between receipts.
        "--parallel 1"

        # immich transcodes on this box and a receipt is never urgent, but six
        # threads read an eleven-line receipt in ~50s, which is close enough to
        # the service.s deadline to have tripped it. Ten of twelve.
        "--threads 10"

      ];
      Restart = "on-failure";
      RestartSec = 10;

      DynamicUser = true;
      CacheDirectory = "llama-cpp-classify";
      StateDirectory = "llama-cpp-classify";
      WorkingDirectory = "/var/lib/llama-cpp-classify";
      Environment = [ "LLAMA_CACHE=/var/cache/llama-cpp-classify" ];

      # No GPU here either.
      PrivateDevices = true;
      AmbientCapabilities = [ "" ];
      CapabilityBoundingSet = [ "" ];
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = false;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };
  };

  systemd.services.financio-ocr = {
    description = "financio-ocr - receipt reading for financio";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "llama-cpp.service"

      "llama-cpp-classify.service"
    ];
    wants = [
      "network-online.target"
      "llama-cpp.service"

      "llama-cpp-classify.service"
    ];

    environment = {
      OCR_PORT = toString port;
      # Reachable from private, which is the whole point of it living here. The
      # firewall rule below is what narrows that to one address.
      OCR_BIND_ADDR = "0.0.0.0";
      LLAMA_URL = "http://127.0.0.1:${toString llamaPort}";

      # The categoriser. Unset, /categorise answers 503 and nothing about
      # reading changes: naming a category is an improvement on top of a
      # reading, never a precondition for one.
      #
      # There was a second implementation on port 8082, an embedding model,
      # kept for a while as a fallback. It is gone. It named 3 of 9 lines
      # correctly on a real receipt, and a fallback that answers wrongly is
      # worse than no fallback - financio already handles being told nothing,
      # by storing the receipt with blank categories for the user to fill in.
      CLASSIFY_URL = "http://127.0.0.1:${toString classifyPort}";

      # One image token covers 28x28 pixels, so this is 1097 of them - just
      # above the 1024 the model's own preprocessor floors at.
      #
      # 820000 was the value under ollama, forced by the encoder's fixed
      # reservation, and it is 5% too small. At 820000 the Clas Ohlson fixture
      # comes back with the printed "TOTAL 400,00" instead of the 399,90 the
      # card was actually charged, so its lines do not add up, it is read a
      # second time, and it reaches the user flagged. At 860000 it reads 399,90
      # and balances - three fresh runs, identical, plus the Rema pair still
      # merging to 7 lines and 273,75. Every larger size tested (900k, 1.0 MP,
      # 1.2 MP) also reads the card amount, so this is the cheap end of a
      # threshold rather than a lucky number.
      #
      # It is not free, and the cost is permanent rather than per-request:
      # llama-server keeps the largest vision compute buffer it has ever
      # allocated for the life of the process. Measured on this card, each from
      # a fresh restart - 4.6 GB with the model loaded and nothing read yet,
      # then after one read at
      #
      #   860000 -> 6.1 GB      1.0 MP -> 6.5 GB      1.2 MP -> 7.4 GB
      #
      # and it stays there. That is why this is 860000 rather than the
      # service's own 1.2 MP default: immich needs the rest of the 8 GB, and
      # the only way to hand the buffer back is to restart the unit.
      OCR_MAX_PIXELS = "860000";

      # A receipt in several parts is one model call per part, plus a re-read
      # when the lines do not add up to the total. At ~12s an image that is
      # about five minutes for the twelve-image maximum read twice. The client
      # sets its own deadline; this only has to be longer than a legitimate
      # read.
      OCR_TIMEOUT = "10m";
    };

    unitConfig = {
      # Before the first deploy there is no binary, and without this the unit
      # fail-loops on 203/EXEC and turns `nixos-rebuild switch` red for a state
      # that is entirely normal. With it the unit is simply skipped until CI
      # has put a release in place, and financio-ocr-deploy starts it then.
      ConditionPathExists = binary;
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
