{ lib, buildDotnetModule, fetchFromGitHub, dotnetCorePackages }:

# Builds the tagptroll1/PropHunt CSSharp plugin from source. This fork is the
# source of truth — all gameplay edits live in the fork repo, NOT here. The
# previous setup applied 11 substituteInPlace patches and injected a Commands.cs
# at build time; that's gone. To iterate:
#
#   1. Edit C# in /mnt/bigboi/dev/cs/prophunt, commit & push to
#      git@github.com:tagptroll1/PropHunt.git (branch: main).
#   2. Bump src.rev to the new commit sha below.
#   3. Bump src.hash — easiest path is set hash = lib.fakeHash; build once,
#      copy the real hash from the error.
#   4. If PackageReferences changed, regenerate deps.json:
#        nix build .#cs2-prophunt.fetch-deps
#        (writes a new deps.json next to this file).
#   5. sudo nixos-rebuild switch --flake ~/nixos#media on media.
#   6. In the cs2 console: css_plugins reload PropHunt
#
# The fork targets net9.0 (vs upstream's net8.0) — keep dotnet-sdk/runtime
# pinned to 9.0 here. deps.json is genuinely `[]` — the only PackageReference
# is CounterStrikeSharp.API and it has no transitive nuget deps.
buildDotnetModule (finalAttrs: {
  pname = "cs2-prophunt";
  version = "0.1.0-unstable-2026-06-01";

  src = fetchFromGitHub {
    owner = "tagptroll1";
    repo = "PropHunt";
    # TODO: bump after pushing the patch-fold-in commit. Until then, the rev
    # below is upstream's last commit (will fail because the fork's main has
    # since diverged once you push). Use lib.fakeHash to TOFU the hash.
    rev = "e1c48b5e21693e213272c25ae8d49ad4fb748eb6";
    hash = lib.fakeHash;
  };

  projectFile = "src/PropHunt.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_9_0;
  dotnet-runtime = dotnetCorePackages.runtime_9_0;

  # Class library, not an app.
  executables = [ ];

  meta = {
    description = "Prop Hunt CS2 plugin (tagptroll1 fork)";
    homepage = "https://github.com/tagptroll1/PropHunt";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
