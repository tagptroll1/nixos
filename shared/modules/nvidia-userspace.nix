# The userspace half of the NVIDIA driver, for containers that share home02's
# GTX 1070.
#
# The kernel module belongs to the Proxmox host - a container has no kernel of
# its own - so nothing here may touch `hardware.nvidia`'s config block or
# `boot.kernelModules`. What a container needs is libcuda, the encode/decode
# libraries and nvidia-smi, plus the device nodes, which come from the CT
# config on the host side (`dev0:` .. `dev4:`).
#
# The version is not a preference. libcuda in here speaks a version-locked
# ioctl interface to the host's nvidia.ko: mismatch and every CUDA call fails
# with "Failed to initialize NVML: Driver/library version mismatch". nixpkgs
# decides the version, the host follows it - install that exact .run on home02,
# not Debian's packaged driver. After any nixpkgs bump, compare:
#
#   nix eval --raw path:.#nixosConfigurations.ocr.pkgs.linuxPackages.nvidiaPackages.legacy_580.version
#   ssh home02 nvidia-smi --query-gpu=driver_version --format=csv,noheader
#
# legacy_580 rather than a newer branch because GP104 is Pascal: NVIDIA froze
# Maxwell, Pascal and Volta on the 580 branch, and 595+ does not bind the card.
{ pkgs, ... }:
let
  nvidia = pkgs.linuxPackages.nvidiaPackages.legacy_580;
in {
  hardware.graphics = {
    enable = true;
    enable32Bit = false;

    # Puts the driver's libraries in /run/opengl-driver/lib, which is the path
    # nixpkgs' CUDA setup hook bakes into every CUDA binary's runpath. This is
    # how llama-server finds libcuda.so.1 without an LD_LIBRARY_PATH anywhere.
    extraPackages = [ nvidia.out ];
  };

  # hardware.nvidia's own config only activates when "nvidia" appears in
  # services.xserver.videoDrivers, which it deliberately does not here. Setting
  # the package alone is inert - it exists so that a host enabling
  # hardware.nvidia-container-toolkit (immich, for its CUDA ML container) mounts
  # this exact driver into the container instead of guessing one.
  hardware.nvidia.package = nvidia;

  # nvidia-smi, for "is the card actually here" and for watching encode load.
  environment.systemPackages = [ nvidia.bin ];
}
