{ lib, buildDotnetModule, fetchFromGitHub, dotnetCorePackages }:

# exkludera/PropHunt, built from source with our patches. The upstream plugin
# is v0.0.1 alpha (single commit) and has several rough edges; the postPatch
# block below addresses each one. See inline comments for the *why* of each.
#
# At a glance, what we change:
#   * adds src/Commands.cs — bindable [ConsoleCommand] actions + server-side
#     hotkeys (E freeze / R swap / Mouse2 taunt) via OnPlayerButtonsChanged.
#   * disables the auto-opened on-screen menu (actions come from console
#     commands / hotkeys instead of chat-driven "!1".."!4" menu items).
#   * precache: load the CURRENT map's model list at precache time (upstream
#     used the prior map's stale list → models never reached clients).
#   * collision: TRIGGER (immortal) → DEBRIS (bullets register, hider walks
#     through their own prop).
#   * model harvest: also pick up `prop_dynamic`, not just
#     `prop_physics_multiplayer` (covers most map detail).
#   * AddMapModels fallback: try `default.txt` if `<map>.txt` is missing, so
#     any map (workshop / surf / kz / casual) gets a usable prop pool.
#   * footsteps: re-enabled (upstream stripped recipients on hider pawn sounds).
#   * self-invisibility: hider's own pawn render alpha → 0 (otherwise visible
#     in third-person / spec to themselves; CheckTransmit hides it from others).
#
# Hashes: `src.hash` is from `fetchFromGitHub` (recompute via TOFU if you bump
# `src.rev`). `deps.json` is `[]` — the only remaining nuget PackageReference
# is CounterStrikeSharp.API (we patch out CS2MenuManager above) and it has no
# transitive nuget deps, so the lockfile is genuinely empty. Regenerate via
# `nix build .#cs2-prophunt.fetch-deps` if a new PackageReference is added.
buildDotnetModule (finalAttrs: {
  pname = "cs2-prophunt";
  # Upstream is exactly one commit (v0.0.1 alpha, never updated). Bumping
  # src.rev would require both a new src.hash and (if PackageReferences change)
  # a regenerated deps.json.
  version = "0-unstable-2026-01-03";

  src = fetchFromGitHub {
    owner = "exkludera-cssharp";
    repo = "PropHunt";
    rev = "c9157160dab4c1da1006d86b88659d4a85c39d9d";
    hash = "sha256-qIbP6Y7q0DRxOKpXuWsC2XYC5hSZclqYhvRIY4o74RA=";
  };

  projectFile = "src/PropHunt.csproj";
  nugetDeps = ./deps.json; # genuinely `[]` — no transitive nuget deps (see header)

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

    # Drop the CS2MenuManager runtime dep entirely. With the menu disabled the
    # only remaining touches are two CloseActiveMenu calls (round start +
    # hider death) which are no-ops in our setup — replace with comments. Then
    # delete the dead Menu.cs file (its sole entry point is the patched-out
    # Menu.Open) and strip the PackageReference so the build doesn't link
    # CS2MenuManager. cs2.nix no longer ships the plugin either.
    # NB on the no-op replacements: the player/target line at Events.cs:171 is
    # the single-statement body of a `foreach (...)` loop with no braces, so
    # replacing it with bare `/* comment */` would silently make the next
    # statement (Instance.AddTimer) the new loop body. Use `{ }` instead so the
    # parser sees a proper empty statement.
    substituteInPlace src/Events.cs \
      --replace-fail \
        "using CS2MenuManager.API.Class;" \
        "/* CS2MenuManager dep removed (NixOS) */" \
      --replace-fail \
        "MenuManager.CloseActiveMenu(player);" \
        "{ /* no menu to close (NixOS) */ }" \
      --replace-fail \
        "MenuManager.CloseActiveMenu(target);" \
        "{ /* no menu to close (NixOS) */ }"
    rm src/Menu.cs
    substituteInPlace src/PropHunt.csproj \
      --replace-fail \
        '<PackageReference Include="CS2MenuManager" Version="1.0.39" />' \
        '<!-- CS2MenuManager removed (NixOS): menu disabled, no runtime calls -->'

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
    # bullets register, players walk through. (Menu.cs is deleted above so it's
    # no longer in this substituteInPlace list.)
    substituteInPlace src/Utils/Utils.cs \
      --replace-fail "COLLISION_GROUP_TRIGGER" "COLLISION_GROUP_DEBRIS"

    # Hide the hider's own pawn for themselves too. Upstream sets render alpha
    # to 254 (basically opaque) on spawn for both teams, and CheckTransmit hides
    # the pawn from OTHERS — but the hider can still see their own character
    # in third-person. Override alpha to 0 in PropSpawner (hider-only path).
    substituteInPlace src/Utils/Utils.cs \
      --replace-fail 'using CounterStrikeSharp.API;' \
                     'using CounterStrikeSharp.API; using System.Drawing;'
    substituteInPlace src/Utils/Utils.cs \
      --replace-fail \
        'Plugin.HiddenPlayers.Add(player.Slot, new PlayerProp(prop, model));' \
        'player.PlayerPawn.Value!.Render = Color.FromArgb(0, 0, 0, 0); Utilities.SetStateChanged(player.PlayerPawn.Value!, "CBaseModelEntity", "m_clrRender"); Plugin.HiddenPlayers.Add(player.Slot, new PlayerProp(prop, model));'

    # Fallback — if <mapname>.txt is missing, try default.txt. With it, ANY map
    # (workshop, casual, surf, kz, ...) gets a usable prop pool instead of an
    # empty Plugin.models. The per-map lists already include the default props
    # via the generator, so this only kicks in for maps with no curated list.
    substituteInPlace src/Utils/Utils.cs \
      --replace-fail \
        'string filePath = Path.Combine(Instance.ModuleDirectory, "maps", $"{mapname}.txt");' \
        'string filePath = Path.Combine(Instance.ModuleDirectory, "maps", $"{mapname}.txt"); if (!File.Exists(filePath)) filePath = Path.Combine(Instance.ModuleDirectory, "maps", "default.txt");'

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
