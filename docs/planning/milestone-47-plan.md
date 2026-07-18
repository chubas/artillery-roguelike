# Milestone 47 — First Boss: Boss1 + map-entity spawning engine

## Why

Phase 2 (productionization) is paused for a few gameplay mechanics first — the Act 1 boss and its
waves. This milestone builds the boss and the engine that spawns it, without its real attack yet.
It also generalizes hand-authored map "entities" into open objects so richer entity definitions
can be layered on later.

## What shipped

### Map entities become objects
- New `MapEntity` (`terrain/map_entity.gd`, `RefCounted`): `name`, `coordinates: Vector2i`,
  `props: Dictionary` (open key/value bag; `props["coordinates"]` mirrors the field).
- `CustomMap.entities` is now `name -> MapEntity` (was `name -> Vector2i`). The `Entity_<name>: [x, y]`
  line syntax is unchanged — the `[x, y]` shorthand means `coordinates`. Richer JSON-object values
  are a future extension in `CustomMap._parse_entity` without touching callers.
- New `pool: true|false` map metadata (default true). `pool: false` keeps a map out of the random
  run pool — `MapLibrary.pool_map_ids()` filters it; `MapLibrary.map_ids()` still lists everything
  (sandbox dropdown). `Run._assign_terrain_variations` draws from `pool_map_ids()`.

### UnitDefinition seams
- `anchored: bool` — position is fixed; the unit never falls (`settle`) when terrain beneath it is
  destroyed. `weight` only governs climbing; this stops gravity. `CombatManager._settle_unit`
  early-returns for anchored units.
- `enum AttackBehavior { PROJECTILE, NONE }` + `attack_behavior` field. `NONE` = no-op turn: the
  unit ends its turn immediately and gets no targeting telegraph. Extension point for the future
  special boss attack.

### Boss1 unit + spawning
- Baked `data/units/boss1.tres`: 5×5, 100 HP, `anchored=true`, `attack_behavior=NONE`,
  `default_shot=null`, `tags=["BOSS","MECHANICAL"]`, `Rarity.BOSS`. `base_power=1.0` only satisfies
  the bake guard (never read — the boss never fires).
- `CombatManager._spawn_map_entities()` (called in `setup()` before `all_units` is assembled) spawns
  a unit for each map entity whose **name resolves to a baked unit def by id** (`Boss1` →
  `res://data/units/boss1.tres`) at its exact top-left coordinate as an enemy. Entities that don't
  resolve to a unit are left untouched for future systems. Gated by `Features.boss_enabled`.
- `EnemyTargeting.assign_all` skips `NONE` attackers (no telegraph); `CombatManager._run_enemy_turn`
  `continue`s past them (no-op turn).

### Win condition
- `ObjectiveDescriptor.Type.DEFEAT_BOSS` — won when no living enemy carries the `BOSS` tag. Ignores
  the all-waves-spawned gate (unlike DEFEAT_ALL), so the boss dying clears the stage even with adds
  alive. `ObjectiveEvaluator.evaluate(...)` gains a `boss_alive: bool = true` param;
  `CombatManager._check_objective` computes it from the `BOSS` tag.
- Baked `data/stages/stage_boss1.tres` (objective DEFEAT_BOSS, no `initial_enemies` — boss comes from
  the map entity, wind off). The `data/maps/boss1.txt` arena already existed (`Entity_Boss1: [61,22]`);
  it now carries `pool: false`.

### Manual playtest
- `Features.boss_test_stage` (default false). When true, `Run._assign_terrain_variations` forces run
  node 0 → `custom_map_id="boss1"`, `stage_path="…/stage_boss1.tres"` — one flag to drop into the
  boss arena.
- `Features.boss_enabled` (default true) kill switch for entity spawning.

## Design decisions
- **Immobile** = a dedicated `anchored` bool, not a tag/weight (no existing concept stops gravity).
- **Entity → unit** by name→id convention (zero per-boss code; extends to any future entity-unit).
- **"Which unit is the boss"** = the `BOSS` tag (reuses `tags`; minion waves won't carry it).

## Verification
- Bake: `--import` → `res://scripts/bake_runner.tscn` → `--import` (produces `boss1.tres`,
  `stage_boss1.tres`; validation passes).
- Smoke `_m47_smoke()` (all pass): boss def 5×5/100/anchored/NONE/BOSS; `Entity_Boss1` parses to a
  `MapEntity` at (61,22), `pool=false`; spawn count 1 at (61,22) hp 100; carve terrain beneath +
  settle → position unchanged (anchored); `assign_all` → no target/solution (no-op); DEFEAT_BOSS
  evaluates ONGOING (alive) / WON (dead) / LOST (wipe); `boss1` in `map_ids()` but not
  `pool_map_ids()`; `boss_test_stage` wires node 0.
- Manual: `Features.boss_test_stage=true`, launch `res://world/run_controller.tscn`, enter node 0.

## Out of scope (later)
- The boss's real attack (the "special rule"); minion waves; collapse *crush* vs anchored units;
  a proper boss node in `build_run_map`; sandbox reposition skipping anchored units.
