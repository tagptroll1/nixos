{ lib, buildDotnetModule, fetchFromGitHub, dotnetCorePackages }:

# exkludera/PropHunt, built from source with our patches:
#   * adds src/Commands.cs — bindable [ConsoleCommand] actions + server-side
#     hotkeys (E freeze / R swap / Mouse2 taunt) via OnPlayerButtonsChanged.
#   * disables the auto-opened on-screen menu (actions come from console
#     commands / hotkeys instead of chat-driven "!1".."!4" menu items).
#   * fixes precache ordering so the current map's prop models are actually
#     sent to clients (was: every prop always showed as a soccer ball).
#   * switches hider props from TRIGGER → INTERACTIVE collision so bullets
#     register hits and seekers can actually kill props.
#   * re-enables footstep sounds on hider pawns (upstream silenced them).
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

    # Don't auto-open the menu on hider spawn; actions come from console commands
    # / server-side hotkeys (E / R / Mouse2). See Commands.cs.
    substituteInPlace src/Events.cs \
      --replace-fail "Menu.Open(player);" "/* menu disabled (NixOS): see Commands.cs */"

    # Bug fix — precache the CURRENT map's model list. OnServerPrecacheResources
    # fires before OnMapStart, so upstream iterates Plugin.models while it still
    # holds the previous map's leftovers (or is empty on first map). Result:
    # this map's vmdls never reach clients, so SetModel falls back to whatever
    # the client happens to have cached — typically the soccer ball. Loading
    # the txt list eagerly here puts the correct models in the precache manifest.
    substituteInPlace src/Events.cs \
      --replace-fail \
        'List<string> resources =' \
        'Utils.AddMapModels(Server.MapName); List<string> resources ='

    # Bug fix — make hider props HITTABLE without blocking the owning player.
    # Upstream uses COLLISION_GROUP_TRIGGER (no bullet hits) → prop immortal.
    # INTERACTIVE makes the prop solid → player gets stuck inside (prop follows
    # player, can't move). COLLISION_GROUP_DEBRIS is the prophunt sweet spot:
    # bullets register, players walk through.
    substituteInPlace src/Utils/Utils.cs src/Menu.cs \
      --replace-fail "COLLISION_GROUP_TRIGGER" "COLLISION_GROUP_DEBRIS"

    # Feature — harvest prop_dynamic models too, not just prop_physics_multiplayer.
    # Most map detail (dust2 barrels/crates/boxes/signs) is prop_dynamic; without
    # this, only the rare prop_physics_multiplayer entries end up in Plugin.models
    # → on dust2 that's literally just the soccer ball → swap always rolls football.
    substituteInPlace src/Events.cs \
      --replace-fail \
        'if (entity.DesignerName == "prop_physics_multiplayer")' \
        'if (entity.DesignerName == "prop_physics_multiplayer" || entity.DesignerName == "prop_dynamic")'
    # The narrow cast assumed prop_physics_multiplayer; broaden to a base type
    # that still exposes CBodyComponent for both designer names.
    substituteInPlace src/Events.cs \
      --replace-fail \
        'var prop = new CPhysicsPropMultiplayer(entity.Handle);' \
        'var prop = new CBaseModelEntity(entity.Handle);'

    # Bug fix — re-enable footsteps. Upstream strips ALL recipients from sound
    # messages (msg 208) emitted by hidden players' pawns to hide their location.
    # Prophunt is more fun when seekers can hunt by ear: prop and player are
    # co-located so the audio origin is already correct.
    substituteInPlace src/Events.cs \
      --replace-fail \
        'Instance.HookUserMessage(208, CMsgSosStartSoundEvent, HookMode.Pre);' \
        '/* footsteps enabled (NixOS): sos hook disabled */' \
      --replace-fail \
        'Instance.UnhookUserMessage(208, CMsgSosStartSoundEvent, HookMode.Pre);' \
        '/* footsteps enabled (NixOS) */'

    # Hook up our server-side hotkey listener (E / R / Mouse2) on plugin load.
    substituteInPlace src/Main.cs \
      --replace-fail "Events.Register();" \
                     "Events.Register(); Plugin.RegisterHotkeys();"
  '';

  meta = {
    description = "Prop Hunt CS2 plugin (exkludera) patched with bindable console commands";
    homepage = "https://github.com/exkludera-cssharp/PropHunt";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
