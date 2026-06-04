{ ... }: {
  services.jellyfin.enable = true;

  # NVENC/NVDEC access on the passed-through GTX 1070. The nvidia kernel
  # modules + userspace libs come from gpu.nix; jellyfin-ffmpeg in nixpkgs
  # already ships with NVENC support, so all that's left is letting the
  # jellyfin service touch the device nodes.
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # Manual steps after rebuild:
  #   1. Verify the jellyfin user can see the GPU and ffmpeg has CUDA:
  #        sudo -u jellyfin nvidia-smi
  #        sudo -u jellyfin /run/current-system/sw/bin/jellyfin-ffmpeg \
  #          -hide_banner -hwaccels    # should list `cuda`
  #   2. Jellyfin → Dashboard → Playback → Hardware acceleration:
  #        - Type: Nvidia NVENC
  #        - Enable HW decoding: H264, HEVC, VP9 (Pascal supports 8/10-bit
  #          HEVC decode; skip AV1 — GP104 has no AV1 engine).
  #        - Tone mapping: only if you have HDR sources.
  #   3. Confirm transcoding actually uses the GPU during a forced
  #      transcode by watching `nvidia-smi dmon -s u` — the `enc` /
  #      `dec` columns should move.
  # Pascal has a 3-session NVENC limit on the stock driver; fine for a
  # household, patch with nvidia-patch if you ever hit it.
}
