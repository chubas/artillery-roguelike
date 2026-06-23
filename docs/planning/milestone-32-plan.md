# M32 — Profile-Driven Terrain Generation

**Date:** 2026-06-22
**Status:** Complete — all smoke checks pass

## Problem

The terrain system was a single monolithic `TerrainManager.generate()` call with hardcoded noise parameters and no authoring control over stage layout. Every stage looked structurally similar. M32 introduces a clean separation:

- A `TerrainGenerator` (static class) that reads a `TerrainProfile` + seed and outputs a `MapData` resource
- A `MapData` resource that is serializable, saveable, and hand-authorable — enabling custom maps and stage save/load independent of the generator
- `TerrainManager.load_map()` that hydrates `MapData` into live `Tile` objects

## Design spec

`docs/design/artillery-space-terrain-generation.md` (v0.1)

---

## Locked decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | `MapData extends Resource` — flat `Array` of `null\|Dictionary` cells | Serializable by Godot's ResourceSaver; works with hand-authoring and procedural generation equally |
| 2 | `TerrainGenerator` is a static class, not an autoload | No state to persist; calling `generate()` is a pure function |
| 3 | `gen_origin` field per cell (GenOrigin enum) | Powers the sandbox visualizer without touching Tile class |
| 4 | `TerrainManager` gets instance `map_width`/`map_height` vars; `_idx()` and `_in_bounds()` use them | Required for variable map dimensions; Const values remain as defaults |
| 5 | `TerrainRenderer.setup()` must be called after `load_map()` | Renderer builds chunks from `terrain.chunks_wide/tall()` which reflect the loaded dimensions |
| 6 | `StageDescriptor.terrain_profile = null` selects legacy path | Existing stage .tres files need no changes; backwards compatible |
| 7 | M32 feature types: ridge, pit, pillar, bunker (rectangular only) | Cave/tunnel/chamber/bridge require spatial carving → M33 |
| 8 | Crystal deposit tiles placed with `CRYSTAL` status_tag | Visually distinct and diggable; pickup mechanic deferred to M33 |
| 9 | Debug visualizer added to existing sandbox overlay panel | In-game, no scene switching required |
| 10 | `Features.terrain_profiles_enabled` kill switch | Consistent with project-wide feature flag convention |

---

## Architecture

### Data flow

```
TerrainProfile (Resource, authored data)
    + seed (int)
    → TerrainGenerator.generate(profile, seed)
    → MapData (Resource, serializable)
    → TerrainManager.load_map(data)
    → TerrainRenderer.setup(terrain)   ← must come after load_map
```

For custom/hand-authored maps, skip the generator entirely — author a `MapData` and load it directly.

### `MapData` — `terrain/map_data.gd`

```
enum GenOrigin { NOISE_FILL, SPAWN_PLATFORM, SLOT_LEFT, SLOT_CENTER, SLOT_RIGHT, BACKGROUND, CRYSTAL }

@export var width  : int
@export var height : int
@export var cells  : Array   # null=VOID | Dictionary{type,hp,max_hp,flags,collapsible,status_tags,variant,gen_origin}
```

Helper: `place_solid(col, row, hp, flags, collapsible, tags, origin)` — single-line tile placement.

### `TerrainGenerator` — `terrain/terrain_generator.gd`

Static class. Passes:
1. **`_pass1_features`** — resolve slots, call feature placers, mark cells with `gen_origin=SLOT_*`
2. **`_pass1_spawn_platform`** — indestructible platform at `Const.SPAWN_PLATFORM_COL`
3. **`_pass2_base_and_noise`** — base fill + noise for unclaimed columns; amplitude capped by `profile.noise_max_amplitude`
4. **`_pass3_hp`** — 10% reinforced HP (CONDUCTIVE)
5. **`_pass4_variants`** — visual variant 0-3

Feature placers: `_place_ridge`, `_place_pit`, `_place_pillar`, `_place_bunker`, `_place_crystal_deposit`

Slot center columns: `int(0.25 * width)` / `int(0.50 * width)` / `int(0.75 * width)`

### `TerrainManager` changes

- Added `var map_width/height : int = Const.MAP_WIDTH/HEIGHT`
- Added `chunks_wide()` / `chunks_tall()` instance helpers
- `_idx()` and `_in_bounds()` use instance vars
- Added `load_map(data: MapData)` — sets dimensions, resizes `_grid`, hydrates `Tile` objects
- `generate(seed)` unchanged (legacy path)

### `TerrainRenderer` changes

`_build_chunks()` and `_on_tile_changed()` now call `_terrain.chunks_wide/tall()` instead of `Const.chunks_*()`.

### Sandbox Terrain Visualizer

New "TERRAIN VIZ" section in `debug/sandbox_overlay.gd`. Profile dropdown, seed field, "Preview" button, minimap `_draw()` (inner class `_TerrainMinimap`). Color map:
- NOISE_FILL → grey | SPAWN_PLATFORM → blue | SLOT_LEFT → orange | SLOT_CENTER → yellow | SLOT_RIGHT → green | BACKGROUND/CRYSTAL → cyan

---

## Files changed

| File | Change |
|---|---|
| `terrain/map_data.gd` | NEW |
| `terrain/terrain_profile.gd` | NEW |
| `terrain/feature_definition.gd` | NEW |
| `terrain/terrain_generator.gd` | NEW |
| `terrain/terrain_manager.gd` | Added map_width/height, chunks_wide/tall(), load_map() |
| `rendering/terrain_renderer.gd` | Use terrain.chunks_wide/tall() |
| `data/stages/stage_descriptor.gd` | Added terrain_profile field |
| `data/terrain/profiles/*.tres` | NEW — open_field, ridge_assault, fortress_siege, pit_crossing |
| `data/terrain/features/*.tres` | NEW — ridge_standard, bunker_standard, pit_standard, crystal_vein |
| `autoloads/features.gd` | Added terrain_profiles_enabled |
| `debug/sandbox_overlay.gd` | Added Terrain Visualizer section |
| `scripts/bake_resources.gd` | Added profile + feature baking |
| `world/combat_scene.gd` | _setup_terrain() helper; _m32_smoke() |

---

## Smoke test results

```
[smoke] -- M32 terrain generation --
  map_size=122x106 (expect 100-130 x 90-110)    ✓
  solid_fraction=0.55 (expect 0.3-0.7)           ✓
  ridge_center_tiles=390 (expect >0)             ✓
  bunker_shell_tiles=97 (expect >0)              ✓
```

All M1–M31 prior checks continue to pass.

---

## Deferred to M33

- Cave/tunnel/underground-chamber/bridge spatial carving
- LIQUID/lava tile type + hazard schedule
- COLLAPSIBLE flag on bridge spans
- Crystal pickup drops
- `combat_scene.gd` hardcoded spawn column positions (`Const.MAP_WIDTH - 26` etc.)
- Act-based profile selection at runtime
