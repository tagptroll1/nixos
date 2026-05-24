{ lib, buildDotnetModule, fetchFromGitHub, dotnetCorePackages }:

# exkludera/PropHunt, built from source with a small patch:
#   * adds src/Commands.cs — bindable [ConsoleCommand] actions (css_phfreeze etc.)
#   * disables the auto-opened on-screen menu (the actions are otherwise only
#     reachable as chat-driven menu items "!1".."!4", which is what we don't want)
#
# Two hashes are TOFU — generate them on a host with nix (see
# docs/cs2-server-setup.md → "Building the prophunt plugin"):
#   1. src.hash:  build once, nix prints the correct sha256.
#   2. deps.json: `nix build .#cs2-prophunt.fetch-deps && ./result pkgs/cs2-prophunt/deps.json`
buildDotnetModule (finalAttrs: {
  pname = "cs2-prophunt";
  # Unstable: tracks a pinned commit on main (v0.0.1 + later fixes).
  version = "0-unstable-2026-01-03";

  src = fetchFromGitHub {
    owner = "exkludera-cssharp";
    repo = "PropHunt";
    rev = "c9157160dab4c1da1006d86b88659d4a85c39d9d";
    hash = "sha256-qIbP6Y7q0DRxOKpXuWsC2XYC5hSZclqYhvRIY4o74RA=";
  };

  projectFile = "src/PropHunt.csproj";
  nugetDeps = ./deps.json; # TODO: generate (see header); placeholder is `[]`

  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;

  # It's a CounterStrikeSharp plugin (class library), not an app — no wrappers.
  executables = [ ];

  postPatch = ''
    cp ${./Commands.cs} src/Commands.cs
    # Don't auto-open the menu on hider spawn; actions come from console commands.
    substituteInPlace src/Events.cs \
      --replace-fail "Menu.Open(player);" "/* menu disabled (NixOS): see Commands.cs */"
  '';

  meta = {
    description = "Prop Hunt CS2 plugin (exkludera) patched with bindable console commands";
    homepage = "https://github.com/exkludera-cssharp/PropHunt";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
