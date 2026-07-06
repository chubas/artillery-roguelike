# Milestone 44 — Hand-Authored ASCII Maps (procedural generation deactivated)

## Why

The procedural generator (M32/M43) wasn't producing maps of the desired quality, so we pivoted to
**hand-designed maps**: parseable text files with an ASCII tile grid + metadata. The generator
classes remain in the repo (dormant, still smoke-tested) but combat stages now load custom maps.
Low variety is fine for now; randomness can be layered back later. Player/enemy placement moves
from single columns to **zone boxes**, so units can be placed inside caves and on floating islands
(per the design sketches: cave, peak, canyon, tower, floating islands, extraction, hills).

## Decisions (locked with the user)

- Combat nodes pick a **random map from the pool** at run start (deterministic from the run seed),
  node 0 included. Profiles/legacy remain only as fallback when the library is empty or the flag is off.
- Ambient `scatter_minerals` does **not** run on custom maps — `M` chars are the only minerals.
- Stage deployables and enemy waves ignore their `col` on custom maps: positions are seeded-random
  inside the map's enemy zones (unit type/name/round still come from the StageDescriptor).

## File format (`.txt`)

```
id: test_flat
title: Test Flats
description: ...
notes: ...
width: 120
height: 100
spawn_zones: [[2, 20, 50, 70]]
enemy_zones: [[70, 20, 116, 70]]
data:
<exactly `height` grid rows; row 0 = top>
```

- `key: value` metadata until the `data:` line; zones are JSON arrays of `[x0, y0, x1, y1]`
  (inclusive corners → `Rect2i`).
- Grid chars: `'.'` void · `1`–`9` SOLID with that hp (collapsible, FLAMMABLE) · `0` SOLID
  **indestructible** · `M` MINERAL (hp 2, drops Ore per M42). Short rows are dot-padded; longer
  rows or unknown chars are parse errors.
- Validation: id present, ≥1 spawn + enemy zone, zones in bounds, grid rows = height.

## What shipped

- **`terrain/custom_map.gd`** — `CustomMap.parse(text)` (line-based, `error` field set on any
  problem) + `to_map_data()` producing the exact cell dicts `TerrainManager.load_map` consumes.
- **`terrain/map_library.gd`** — static loader scanning `res://data/maps/*.txt` **and
  `user://maps/*.txt`** (drop a file there and it appears; same id in user:// overrides res://).
  `map_ids()` / `get_map(id)` / `reload()`. Broken files are warned about and skipped.
  *Export note:* if/when an export preset is added, include `*.txt` in the export filters —
  plain text files aren't bundled by default.
- **Assignment** — `MapNode.custom_map_id` (serialized); `Run._assign_terrain_variations` gives
  every combat node a random library id (run-seeded); `RunController._enter_combat` passes it;
  `combat_scene._setup_terrain` loads the map first (skipping mineral scatter) and falls back to
  profile/legacy on a missing/broken map. `Features.custom_maps_enabled` kill switch.
- **Zone placement** (`systems/combat_manager.gd`) — `set_custom_map(map)`;
  `_zone_surface_top(col, zone, w, h)` finds the topmost standable floor *within the zone box*
  (scans the zone's rows top-down; works inside caves / on islands, unlike the global surface
  snap); `_random_zone_drop(w, h)` picks a seeded (StageRng) random standable spot in the enemy
  zones with a never-fail global-surface fallback. `_placement_drop`, `_drain_placement_queue`,
  `_spawn` (enemies only), `_spawn_reinforcement`, and `_spawn_deployables` all route through
  these when a custom map is set; legacy col paths untouched otherwise.
- **Placement UI** — `targeting_ui.set_placement_state(..., zones)`; the overlay draws the spawn
  zone **boxes** (fill + outline) instead of the full-height column band when zones are present.
- **Sandbox** — TERRAIN section gains a "Map:" dropdown (`MapLibrary`, reloaded on Load) + "Load
  Map" button: loads into live terrain + minimap, updates the combat manager's zones, shows
  `map: id (WxH)` or the parse error in the readout label.
- **`data/maps/test_flat.txt`** — 120×100 flat proving ground: hp-3 ground from row 42,
  indestructible `0` floor rows 98–99, 7-voxel `M` cluster around (58–61, 45–47), spawn zone
  `[2,20,50,70]`, enemy zone `[70,20,116,70]`.

## Deviations / notes

- `_m33_smoke`'s "node[1] profile nonempty" expectation was updated: custom maps supersede
  profiles, so combat nodes now carry `custom_map_id` with an empty profile path.
- The M43 generator + smoke stay fully functional (still runs `_m32`/`_m43` checks) — the sandbox
  profile dropdown can still regenerate procedural terrain for comparison.

## Verification

1. `godot --headless --import` clean (text files — no bake).
2. `_m44_smoke()` (all pass): library lists `test_flat`; parse 120×100 with 1+1 zones and no
   error; tile spot-checks (hp 3, indestructible floor, MINERAL with tag, void sky); zone drop at
   col 10 → (10, 39); seeded enemy-zone drop lands in-zone; bad grid char → parse error; run
   assignment gives node 0 `test_flat`; flag off → no map id and legacy profile behavior.
   Pre-existing unrelated failures remain (`_m6` third unit, `_m19` MapState).
3. Manual: run → all combat nodes play `test_flat`; placement shows the left zone box and drops
   inside it; enemies scatter in the right zone; digging the `M` cluster drops collectible Ore;
   sandbox Load Map swaps terrain live; a `.txt` dropped into `user://maps/` appears after Load.
