# Milestone 42 — Mineral Terrain + Ore Drops + Currency Rename

## Why

We want an in-stage economy: pockets of breakable **mineral** terrain the player mines for currency.
Terrain was uniform SOLID, and the run currency was stored as `RunState.resources["shards"]` — the
word "shards" now collides with the crystal-mineral theme, so the currency is also renamed to a
generic `currency` (UI still shows "◆ Shards").

## What shipped

### Currency rename
- `RunState.currency : int` + `add_currency` / `spend_currency` (guards ≥0) / `can_afford`.
  Serialized; `from_dict` migrates legacy `resources["shards"]`. The `resources` dict stays as an
  unused seam (gold/scrap/intel).
- All ~15 read/write sites moved off `resources["shards"]`: `run.gd` (start 25), `run_controller`
  (+20 on clear), `squad_ops` (repair/retire/fuse), `shop_screen`, `map_screen`, `event_blood_price`,
  `sandbox_overlay`, and the combat_scene smoke prints. **UI labels keep "◆ Shards".**

### Mineral terrain
- `Tile.TileType.MINERAL` (durability 2, `collapsible`, `status_tags=["MINERAL"]`). Renders **pink**
  (`chunk.gd` `COLOR_MINERAL`). `TerrainManager.is_solid` treats MINERAL as standable ground.
- `TerrainManager.scatter_minerals(seed)` — deterministic post-build pass (called in
  `combat_scene._setup_terrain`, covering both generation paths) that converts small clustered blobs
  (2–4 tiles) of destructible SOLID into MINERAL, ~40% anchored on the surface. Gated by
  `Features.minerals_enabled`.

### Ore drops
- `world/ore.gd` — `Ore` node (vox + `value`), drawn as a **floating pink circle** with a high
  `z_index` (above units/deployables) under a new `OreLayer` added last in `combat_scene`.
- `systems/ore_system.gd` — `OreSystem` owns spawn/settle/merge/collect/snapshot:
  - Listens on `EventBus.mineral_destroyed` (emitted by `TerrainManager._destroy_tile` when a MINERAL
    breaks) → `spawn_at`. Listens on `EventBus.aoe_resolved` (post-collapse) → `settle_all()`, which
    applies **gravity**: each Ore falls straight down one voxel at a time until it rests on a blocking
    terrain tile (or the map floor). An Ore that lands on a voxel already occupied by another Ore
    **merges** into it (values sum). Buried Ore with terrain below stays in place — it never rises to
    the surface. `ORE_CURRENCY = 2` per source voxel.
  - `try_collect(unit)` — a stepping living **player** unit collects an Ore in the same column span
    that sits anywhere from the top of its footprint down to **one voxel below its base** (so drops
    that fell into a 1-voxel pit at the unit's feet are reachable). Awards `value*2`,
    `EventBus.ore_collected`.
  - `snapshot()`/`restore()` for undo.

### Collection + undo + HUD
- `CombatManager` owns an `OreSystem`; `try_move` calls `try_collect` after moving. The move
  checkpoint snapshots the Ore set + `Run.active.currency`; `try_undo` restores both (re-spawning a
  collected Ore and refunding currency).
- `ui/hud.gd` shows a live "◆ Shards" readout refreshed on `EventBus.ore_collected`.

## Verification

1. `godot --headless --import` compiles clean (no new .tres).
2. Smoke `_m42_smoke()` (all pass): currency helpers + round-trip + legacy `shards` migration;
   MINERAL tile `max_hp==2`; `scatter_minerals` places tiles (54 from 30 patches); two Ore in a
   column merge to value 2; collect awards value×2 and removes the Ore; snapshot→collect→restore
   round-trips; `minerals_enabled=false` disables collection. Currency-dependent M21/M36 smokes
   still pass (start 25, repair 20, retire 27, fuse 5). (Pre-existing unrelated failures remain:
   `_m6` needs a 3rd player unit; `_m19` MapState.)
3. Manual: pink mineral patches appear (some exposed) → dig one (2 dig) → an Ore circle drops to the
   surface and merges in-column → walk a unit onto it → "◆ Shards" ticks up by 2×voxels → undo
   reverts both the Ore and the currency → currency persists to the map/shop.
