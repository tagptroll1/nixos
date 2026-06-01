#!/usr/bin/env python3
"""Generate per-map prophunt prop lists from CS2's VPK directory.

Filters CS2's full model index down to "hideable" props per map: small/medium
objects (crates, bottles, signs, lanterns, tools, etc.). Skips structural pieces
(walls, doors, arches, columns), oversized assemblies, lighting placeholders,
and other non-prop-like models.

Reads /tmp/all_files.txt (produced by vpkdump.py over csgo/pak01_dir.vpk) and
writes per-map .txt files into the destination dir.
"""
import os, re, sys
from collections import defaultdict

ALL_FILES = "/tmp/all_files.txt"
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "/home/tagp/nixos/hosts/media/modules/cs2-presets/prophunt-maps"

# Premier + Competitive Active Duty pool (CS2). de_thera has only 2 vmdl entries
# in the local VPKs, so we exclude it; if it appears later, copy default.txt.
MAPS = {
    "de_dust2":    ["models/props/de_dust/", "models/props/dust_massive/"],
    "de_inferno":  ["models/props/de_inferno/", "models/de_inferno/"],
    "de_mirage":   ["models/props/de_mirage/", "models/de_mirage/"],
    "de_nuke":     ["models/props/de_nuke/"],
    "de_overpass": ["models/props/de_overpass/", "models/de_overpass/"],
    "de_train":    ["models/props/de_train/"],
    "de_vertigo":  ["models/props/de_vertigo/", "models/props/hr_vertigo/", "models/de_vertigo/"],
    "de_ancient":  ["models/props/de_ancient/"],
    "de_anubis":   ["models/anubis/", "models/de_anubis/"],
    # Bonus — not in current Premier rotation, but the coolest map of all time.
    "de_cache":    ["models/de_cache_s2/", "models/props/de_cache/"],
}

# Default / fallback list: cross-map "small object" sources. Used by the patched
# AddMapModels for any map that doesn't ship its own .txt; also bundled INTO
# each per-map list so every map starts with a baseline of universal props.
GENERIC_SOURCES = [
    "models/props/crates/",
    "models/props/cs_office/",
    "models/props/cs_italy/",
]

# Whitelist keywords: filename SUBSTRINGS that mark a model as "good prophunt prop".
# Hideable, recognizable, roughly player-or-smaller.
GOOD = {
    # containers
    "barrel", "crate", "box", "container", "cardboard", "package", "carton",
    # bottles / ceramics
    "bottle", "jar", "jug", "vase", "pot", "kettle", "cup", "plate", "bowl",
    "chianti", "wine", "amphora", "urn",
    # bags / pallets
    "bag", "sack", "pallet", "basket", "bucket", "bin", "duffel", "duffle",
    "backpack", "suitcase", "briefcase",
    # lighting
    "lantern", "lamp", "candle", "flashlight", "spotlight",
    # signage
    "sign", "signpost", "plaque", "banner", "billboard",
    # vehicles / wheels
    "tire", "wheel", "drum", "fueltank", "oildrum", "fuel_can", "jerrycan",
    "fire_extinguisher", "hydrant", "cone",
    # electronics
    "fan", "radio", "computer", "monitor", "keyboard", "tv", "speaker",
    "generator", "phone", "printer", "lap_top", "laptop",
    # food
    "watermelon", "melon", "apple", "banana", "fruit", "fish", "bread", "meat",
    "food", "eggplant", "tomato", "egg", "olives", "lemon", "tangerine",
    "pineapple", "pumpkin",
    # statues / decor
    "statue", "figurine", "idol", "skull", "treasure", "trophy", "vase",
    # furniture
    "chair", "stool", "bench", "tableprop", "table_small",
    # toys / balls
    "soccer", "basketball", "football", "ball_", "_ball", "toy",
    # tools
    "hammer", "shovel", "pick_", "wrench", "axe", "tool",
    # misc small
    "book", "paper", "folder", "document", "briefcase",
    "ammobox", "ammocase", "ammo_box", "ammo_case", "weapon_case",
    "cooler", "icechest", "refridg", "fridge", "stove", "oven", "microwave",
    "dumpster", "rubble", "rock_small", "stone_small", "_rock_", "_pebble",
    "kiosk", "vending",
}

# Blacklist keywords: filename substrings that disqualify even if a good keyword
# matches. Architectural / oversized / technical models.
BAD = {
    # structural
    "arch", "archway", "column", "pillar", "beam", "girder", "truss",
    "wall", "door", "window", "ceiling", "floor", "roof", "awning", "shutter",
    "stair", "ladder", "rail", "fence", "wire", "cable", "trim",
    "shutter", "shingle", "balustrade", "balcony",
    # composite / kits
    "assembly", "kit", "modular", "_frame", "_base", "_section",
    "_overlay", "thatch", "scaffold",
    # giant / area / world
    "skybox", "terrain", "huge", "massive", "_xl", "_giant",
    "_big_", "large_", "_large", "ladder_", "rooftop", "cliff",
    "lightshaft", "lightbeam", "light_volume", "lightvol",
    # technical / placeholder
    "collision", "_clip", "hidden", "_emit", "emitter", "_lod",
    "_cast", "particle", "decal",
    "_tile", "_vent_long",
    # destroyed / broken
    "gib", "broken", "destroyed", "rubble_large", "debris_pile",
    # too small / detail
    "_dust_", "speck", "splat",
    # plants we don't want
    "tree_", "treetrunk", "bush_large",
    # not hide-friendly
    "scope", "weapon_", "character_", "agent_",
    "spawn", "marker", "_emit_",
    "candle_cluster",  # large multi-candle, not great
    "ancient_thatch_roof",
    # _frame / _kit already caught above
}

# Filename size hint regex — values >= this look too big for a hider prop.
SIZE_RE = re.compile(r'_(\d{2,4})(?:[x_]\d+)?')
MAX_SIZE = 160

def is_good(path):
    p = path.lower()
    if not p.endswith(".vmdl_c"):
        return False
    fn = p.rsplit('/', 1)[-1]
    # blacklist check first
    for bad in BAD:
        if bad in p:
            return False
    # whitelist check
    good_hit = any(g in p for g in GOOD)
    if not good_hit:
        return False
    # size sanity: scan numeric size hints
    for m in SIZE_RE.finditer(fn):
        if int(m.group(1)) > MAX_SIZE:
            return False
    return True

def harvest(prefixes, all_paths):
    out = []
    for p in all_paths:
        if any(p.startswith(pref) for pref in prefixes) and is_good(p):
            out.append(p)
    # dedupe preserving order
    seen, deduped = set(), []
    for p in out:
        if p not in seen:
            seen.add(p)
            deduped.append(p)
    return deduped

def strip_c(paths):
    return [p[:-2] if p.endswith(".vmdl_c") else p for p in paths]

def write_list(filename, mapname, paths, source_note):
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, filename)
    header = [
        f"// PropHunt prop-model list for {mapname}.",
        f"// Auto-generated from CS2 pak01_dir.vpk ({source_note}).",
        f"// Filter rules in pkgs/cs2-prophunt — keep small/medium hideable objects,",
        f"// skip walls/arches/columns/doors/assemblies/oversized models.",
        f"// {len(paths)} models below.",
        f"",
    ]
    with open(out, "w") as f:
        f.write("\n".join(header))
        f.write("\n".join(paths))
        f.write("\n")
    print(f"  {out}: {len(paths)} models")

def main():
    all_paths = [l.strip() for l in open(ALL_FILES) if l.strip()]
    print(f"Loaded {len(all_paths)} VPK entries")

    # generic / fallback list
    generic = harvest(GENERIC_SOURCES, all_paths)
    generic_vmdl = strip_c(generic)
    print(f"\nGeneric (fallback): {len(generic_vmdl)} candidates")

    write_list("default.txt", "any map (fallback)", generic_vmdl,
               "GENERIC_SOURCES")

    # per-map
    print("\nPer-map:")
    for mapname, prefixes in MAPS.items():
        per = harvest(prefixes, all_paths)
        # union with generic so every map has at least the universal props
        union = list(dict.fromkeys(per + generic))  # preserve order, dedupe
        union_vmdl = strip_c(union)
        write_list(f"{mapname}.txt", mapname, union_vmdl,
                   ", ".join(prefixes) + " + GENERIC_SOURCES")

if __name__ == "__main__":
    main()
