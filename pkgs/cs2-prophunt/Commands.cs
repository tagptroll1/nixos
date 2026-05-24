// Added by the NixOS config (hosts/media): bindable console commands for the
// prophunt hider actions, so players can `bind` keys instead of using the
// on-screen menu (which is disabled via postPatch). The bodies mirror the menu
// callbacks in src/Menu.cs 1:1 — keep them in sync if upstream changes.
//
// CounterStrikeSharp registers each [ConsoleCommand("css_xxx")] with a "!xxx"
// chat alias. Players bind client-side, e.g.:  bind f1 "css_phfreeze"
// (fallback if direct console commands aren't forwarded: bind f1 "say !phfreeze")
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Entities.Constants;
using CounterStrikeSharp.API.Modules.Utils;

public partial class Plugin
{
    private static PlayerProp? Hider(CCSPlayerController? player)
    {
        if (player == null || !player.IsValid)
            return null;
        return Plugin.HiddenPlayers.TryGetValue(player.Slot, out var data) ? data : null;
    }

    [ConsoleCommand("css_phfreeze", "Prop Hunt: toggle freezing your prop in place")]
    public void OnPhFreeze(CCSPlayerController? player, CommandInfo command)
    {
        var data = Hider(player);
        if (data == null) return;

        data.Frozen = !data.Frozen;

        if (data.Frozen)
        {
            data.entity.AcceptInput("EnableMotion");
            data.entity.CollisionRulesChanged(CollisionGroup.COLLISION_GROUP_DEFAULT);
            player!.Freeze();
        }
        else
        {
            data.entity.AcceptInput("DisableMotion");
            data.entity.CollisionRulesChanged(CollisionGroup.COLLISION_GROUP_TRIGGER);
            player!.UnFreeze();
        }

        data.entity.Teleport(player!.PlayerPawn.Value?.AbsOrigin, player.PlayerPawn.Value?.AbsRotation);
        Utils.PrintToChat(player, $"{ChatColors.Grey}Freeze: {(data.Frozen ? $"{ChatColors.Green}ON" : $"{ChatColors.Red}OFF")}");
    }

    [ConsoleCommand("css_phdecoy", "Prop Hunt: place a decoy prop")]
    public void OnPhDecoy(CCSPlayerController? player, CommandInfo command)
    {
        var data = Hider(player);
        if (data == null) return;

        if (data.Decoys <= 0)
        {
            Utils.PrintToChat(player!, $"{ChatColors.Grey}No decoys left");
            return;
        }

        data.Decoys--;

        var decoy = Utilities.CreateEntityByName<CPhysicsPropOverride>("prop_physics_override")!;
        decoy.CBodyComponent!.SceneNode!.Owner!.Entity!.Flags &= ~(uint)(1 << 2);
        decoy.SetModel(data.entity.CBodyComponent!.SceneNode!.GetSkeletonInstance().ModelState.ModelName);
        decoy.Teleport(data.entity.AbsOrigin, data.entity.AbsRotation);
        decoy.DispatchSpawn();

        Utils.PrintToChat(player!, $"{ChatColors.Grey}Placed decoy. You have {data.Decoys} left");
    }

    [ConsoleCommand("css_phtaunt", "Prop Hunt: play a taunt sound")]
    public void OnPhTaunt(CCSPlayerController? player, CommandInfo command)
    {
        var data = Hider(player);
        if (data == null) return;

        // TauntLimit <= 0 in PropHunt.json => unlimited taunts.
        bool unlimited = Instance.Config.Settings.Hiding.TauntLimit <= 0;
        if (!unlimited)
        {
            if (data.Taunts <= 0)
            {
                Utils.PrintToChat(player!, $"{ChatColors.Grey}No taunts left");
                return;
            }
            data.Taunts--;
        }

        var sounds = Instance.Config.Sounds.Taunt;
        player!.EmitSound(sounds[Random.Shared.Next(sounds.Count)]);
        Utils.PrintToChat(player, unlimited
            ? $"{ChatColors.Grey}Taunt!"
            : $"{ChatColors.Grey}Used taunt. You have {data.Taunts} left");
    }

    [ConsoleCommand("css_phswap", "Prop Hunt: swap to a random prop model")]
    public void OnPhSwap(CCSPlayerController? player, CommandInfo command)
    {
        var data = Hider(player);
        if (data == null) return;

        if (data.Swaps <= 0)
        {
            Utils.PrintToChat(player!, $"{ChatColors.Grey}No swaps left");
            return;
        }

        data.Swaps--;

        var models = Plugin.models;
        if (models.Count == 0) return;
        string model = models[Random.Shared.Next(models.Count)];
        if (data.entity != null && data.entity.IsValid)
            data.entity.SetModel(model);

        Utils.PrintToChat(player!, $"{ChatColors.Grey}Swapped model. You have {data.Swaps} left");
    }
}
