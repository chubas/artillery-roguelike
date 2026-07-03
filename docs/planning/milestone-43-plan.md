# Milestone 43 — Terrain Generation v2: Placer Contract, Anchors, Seams, Validation

## Why

The M32 generator stamped features before the noise surface existed, so features anchored against
an empty map, seams between features and terrain were undefined, and nothing guaranteed a generated
map actually served its profile's terrain story. The design doc was updated to **v0.2**
(docs/design/artillery-space-terrain-generation.md) and this milestone implements its generator-side
architecture. Stage-side consumption of anchors (enemy-at-aperture placement, Fortress Assault) is
the next milestone.

## What shipped

### Placer contract
- `terrain/feature_instance.gd` — `FeatureInstance` (RefCounted): `id` ("bunker_1"), `type`,
  `footprint: Rect2i`, `anchors: Dictionary` (name → `Vector2i` exact or `Rect2i` zone),
  `edge_specs` (side → `EdgeType` RAMP/CLIFF/GAP/FLUSH), `gap_rects` (volumes that must stay void).
  Standable anchors point at the OPEN voxel where a unit's base goes.
- `terrain/placers/` — `FeaturePlacer` base (`place(data, slot_col, def, rng, id, origin)` +
  `validate(data, inst) -> String`), with `ridge/bunker/pit/pillar/crystal_placer.gd` holding the
  logic moved out of `terrain_generator.gd`. Placers guarantee internal invariants by construction
  (bunker interior clamped to fit a 2×3 unit + ≥1 aperture; pillar isolation > light max-climb;
  ridge fills each column to the local surface so it never floats).
- Anchors exported: ridge `summit_center`/`reverse_slope`/`foot_left`/`foot_right`; bunker
  `interior` (zone)/`interior_center`/`aperture_1..n`/`core`/`roof_center`; pit
  `rim_left`/`rim_right`/`bottom_center` (zone); pillar `top_center`; crystal `vein_center`.
- Registry `TerrainGenerator.PLACERS` (FeatureType → script): a new construct = one placer script +
  one registry line + a `FeatureDefinition` `.tres`.
- `MapData` gains `features: Array`, `attempts_used`, `validation_failure`, and `GenOrigin.SEAM`.

### Pipeline reorder (A–E)
`_generate_once`: **A** base fill + noise for ALL columns (claimed-column skip removed) → spawn
platform stamped over → **B** features via placers against the real surface → **C** seam pass →
**D** HP sprinkle + variants → **E** validation. The HP sprinkle now only touches
NOISE_FILL/SEAM tiles — previously it could silently downgrade bunker shell tiles to hp 6.

### Seam pass (`terrain/seam_pass.gd`)
- **RAMP**: staircase descending `RAMP_STEP = 2` voxels per column (climbable for medium) from the
  feature edge until the natural surface meets it (deviation from the design doc's "1 per column /
  2–6 columns": 1/column made tall-ridge ramps absurdly long or left them hanging; 2/column stays
  within medium `max_climb`). Normal-durability fill, `SEAM` origin.
- **CLIFF**: no-op. **GAP**: defensively re-carves `gap_rects`. **FLUSH**: foundation columns under
  the footprint down to the local surface (indestructible iff the feature base tile is).

### Validation + reroll (`terrain/map_validator.gd`)
- Reachability: Dijkstra over columns from the spawn platform; adjacent-column rises ≤ 2 free,
  taller rises cost the HP of tiles dug off the target column (indestructible rise = blocked);
  enemy zone must be reachable within `DIG_BUDGET = 40`.
- Zone-anchor clearance (2×3 open block) + each placer's own `validate()`.
- `TerrainGenerator.generate` rerolls with `hash([seed, attempt])` up to `MAX_ATTEMPTS = 5`, then
  `push_warning` and returns the last attempt (never blocks a run).
- `Features.terrain_v2_enabled` gates seams + validation (flag off ⇒ single attempt, no SEAM tiles).

### Visualizer (sandbox)
Anchors overlay on the terrain minimap (footprint outlines, exact anchors as dots + labels, zones
as orange rects) behind a new "Anchors" checkbox; SEAM tiles get their own color (light brown);
a `gen:` label shows `attempt N/5 OK` or the failure reason + seed after Regenerate.

## Verification

1. `godot --headless --import` clean (no bake — no `.tres` changes).
2. `_m43_smoke()` (all pass): 4 baked profiles × seeds {42, 1337, 777} → feature count matches
   occupied slots, validation `''` within ≤5 attempts; ridge anchors present, seam tiles > 0,
   max ramp step = 2; bunker anchors present, min shell hp = 8 (HP pass skips features); pit rims +
   void depth 58; flag off ⇒ attempts 1, seam tiles 0. `_m32_smoke` still passes on the new
   pipeline. (Pre-existing unrelated failures remain: `_m6` third unit, `_m19` MapState.)
3. Manual: sandbox terrain view → regenerate profiles across seeds → anchors land sensibly every
   seed, ramps walkable, bunker on foundation, validation readout shows attempts.
