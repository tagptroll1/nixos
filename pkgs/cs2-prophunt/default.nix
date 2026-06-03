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
# Targets net8.0 to match CSSharp's runtime host (kus image ships .NET 8 hostfxr
# under csgo/addons/counterstrikesharp/dotnet/host/fxr/8.0.x). Building against
# net9.0 produces a DLL that references System.Runtime 9.0.0.0 → FileNotFoundException
# at load. deps.json is genuinely `[]` — the only PackageReference is
# CounterStrikeSharp.API and it has no transitive nuget deps.
buildDotnetModule (finalAttrs: {
  pname = "cs2-prophunt";
  version = "0.1.0-unstable-2026-06-03";

  src = fetchFromGitHub {
    owner = "tagptroll1";
    repo = "PropHunt";
    # Seeker out-of-world death + "Failed to join game" fixes.
    rev = "8f149e0e37328956e512b85446b9384e532b8910";
    hash = "sha256-W/zqYuqW0nLLgPF3ovwijqnH3tZpqSTeGzrSxQ6BTO4=";
  };

  projectFile = "src/PropHunt.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;

  # Class library, not an app.
  executables = [ ];

  meta = {
    description = "Prop Hunt CS2 plugin (tagptroll1 fork)";
    homepage = "https://github.com/tagptroll1/PropHunt";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
