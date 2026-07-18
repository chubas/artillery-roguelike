# Milestone 46 — Auto-Fill Terrain Durability + Durability Shading

## Why

Hand-authoring per-voxel durability digits for every map is tedious, and uniform durability is
flat to play. Maps can now opt into noise-driven durability for their generic terrain, and the
placeholder rendering shades durability so the result is readable at a glance.

## What shipped

### Map format (extends M44)
```
autoFillTerrain: true
autoFillTerrainValues: [2, 5]
```
- When enabled, every **`1`** in the grid gets a durability sampled from `[N, M]` (inclusive).
  Explicit digits `2`–`9`, `0` (indestructible), and `M` (mineral) remain authorial overrides.
- Sampling uses **FastNoiseLite Simplex** (the engine's perlin-style noise, same family the
  dormant generator uses), frequency 0.08 — durability forms smooth spatial patches instead of
  per-tile speckle. `t = (noise+1)/2 → hp = min(N + int(t·(M−N+1)), M)`.
- Validation (loud): the flag without a valid values array, out-of-range (`<1` / `>9`), or
  reversed bounds are parse errors.
- **Seeding:** `CustomMap.to_map_data(noise_seed)` — combat passes the per-node `stage_seed`
  (same map re-rolls per run, reproducibly within a run); the sandbox Load Map passes the seed
  field; `0` derives `hash(id)` for parse-only callers.

### Durability shading (`rendering/chunk.gd`)
- Destructible SOLID tiles now lerp **light → dark brown** by `max_hp` 1→9
  (`COLOR_SOLID_LIGHT` → `COLOR_SOLID_DARK`), with a small per-variant tint (`VARIANT_TINT`)
  so bands don't go flat. Debug-grade readability until real terrain art (Phase 2).
- The old `max_hp > 3 → gray` rule is replaced by **`status_tags.has("CONDUCTIVE")` → gray**:
  the legacy generator's reinforced-stone sprinkle keeps its look, while auto-filled hp 4–9
  tiles stay on the brown ramp instead of all reading as stone.
- INDESTRUCTIBLE / LAVA / MINERAL rendering unchanged.

## Session QoL riders (same milestone)

- **Middle-mouse pan:** drag with MMB to pan the combat camera — the world follows the mouse,
  moving in discrete whole-voxel steps (sub-voxel drag distance is banked and consumed as it
  crosses each 16 px boundary). Cancels an in-progress unit-focus ease, same as WASD.
- **Map pool cleanup:** `test_flat.txt` removed — only hand-authored maps remain
  (`_m44_smoke` now builds its fixture inline).
- **Run-map debug aids:** combat nodes show their `custom_map_id` (gold) under the node;
  hovering any node shows a tooltip (stage id, objective, threats, enemy/wave counts, map
  id/title/dims, seed) via `MapGraphView._get_tooltip` — extend `_node_tooltip` freely.

## Files

`terrain/custom_map.gd` (keys, validation, seeded noise fill), `world/combat_scene.gd`
(stage-seed pass-through + `_m46_smoke`), `debug/sandbox_overlay.gd` (seed field on Load Map),
`rendering/chunk.gd` (ramp + CONDUCTIVE gray).

## Verification

1. `godot --headless --import` clean (no bake — no `.tres` changes).
2. `_m46_smoke()` (all pass): inline 12×6 map with `[2, 5]` parses clean; every filled cell in
   2..5 with 3 distinct values; literal `3`/`0`/`M` untouched; same seed → identical fill,
   different seed → different; missing values / reversed bounds → parse errors. Earlier smokes
   unchanged (`test_flat` has no auto-fill keys). Pre-existing unrelated failures remain
   (`_m6`, `_m19`).
3. Manual: add the two keys to a map of `1`s → smooth light-to-dark brown patches, HP labels
   match shades; sandbox seed change re-rolls the fill.
