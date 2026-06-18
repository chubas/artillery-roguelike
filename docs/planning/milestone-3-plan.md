# Milestone 3 — Implementation Plan & Locked Decisions

Engine for emergent combat: EventBus, Features, elements (Fire/Electric), unit statuses
(Burn/Shock), tile statuses (Burning/Electrified). Built on top of the M2 combat loop.

## Locked decisions (from planning Q&A)

1. **Map is 120 wide**, not the spec's 300. Test scenario adapted: players at cols 12/15,
   the ORGANIC enemy at `MAP_WIDTH-20` (100), the MECHANICAL enemy at `MAP_WIDTH-14` (106).
2. **EventBus = gameplay events only.** Turn / unit / status / element / projectile /
   `aoe_resolved` route through `EventBus`. The high-frequency per-tile render signal
   (`TerrainManager.tile_changed`) stays a direct local connection to `TerrainRenderer` —
   thousands of emits per collapse have no business on the global bus.
3. **CONDUCTIVE = reinforced tiles.** The existing ~10% reinforced (stone/steel) tiles get
   `status_tags = ["CONDUCTIVE"]`; standard solid gets `["FLAMMABLE"]`; the indestructible
   platform gets `[]`. No new generation pass.
4. **Fire spread is exposure-gated.** A FLAMMABLE tile only ignites a neighbour that borders
   VOID (`_is_exposed`). Fire creeps along the surface instead of tunnelling through buried
   rock map-wide. (`status_tags` still tags all solid FLAMMABLE; the gate is in `_spread`.)
5. **Player full-charge power ×2.5** (`Const.PLAYER_POWER_MULT`). User request — M2 shots
   fell short and under-covered. Applied in `_fire_active` and the charge preview. Enemies
   (IK firing) are unaffected.

## Deviations from the spec text

- **No fire ↔ burning circular resource reference.** The spec puts `tick_element: ElementDef`
  on `TileStatusDef`, which makes `fire.tile_status = burning` and `burning.tick_element = fire`
  a hard cycle that Godot's `.tres` loader cannot resolve (loading fire requires burning
  requires fire → "non-existent resource"). Instead `TileStatusDef` carries
  `applied_status: StatusEffectDef` (the unit status to apply) and tile tick damage is
  **physical**. The reference graph is a clean DAG: `fire → {burn, burning}`, `burning → burn`.
  Affinity on a 1-damage tick is a no-op anyway, so nothing is lost in M3.
- **`UnitStatusSystem.tick_all()` returns AP reduction** instead of calling
  `CombatManager.action_bar.spend()`. We use an `actions_left: int`, not an action-bar object,
  and keep the dependency one-directional (`CombatManager → UnitStatusSystem`). The caller
  subtracts the returned reduction from the shared pool.
- **AoE damages a unit once per blast** (dominant = highest-base-damage group covering it),
  carried over from M2 — the spec's per-voxel loop one-shots multi-voxel units. The dominant
  group's element drives affinity + applied status.
- **Tile tick damage hits both sides** (fire burns everyone touching the tile); shot AoE keeps
  M2 friendly-fire-off (player shots hit enemies only).
- **Enemy Shock AP reduction is moot in M3** — enemies have no shared action pool yet (spec §6
  step 6 is post-M2). Enemy Burn still ticks.

## Resolution order (spec §6, as implemented in CombatManager)

`_begin_round()` → tile statuses tick → `_start_player_turn()` (player unit statuses tick,
Shock AP reduction applied to pool) → player actions → `_run_enemy_turn()` (enemy statuses
tick → enemy fire) → next `_begin_round()`.

## Build / re-bake workflow

Resources are generated, not hand-authored:

```
godot --headless --import                      # register class_names + new .tres
godot --headless -s scripts/bake_resources.gd  # write all .tres (single pass, DAG order)
godot --headless --import                      # register the freshly-baked .tres
```

## Verification

`ARTILLERY_SMOKE=1 godot --headless` runs the §10 checklist headless. All pass:
affinity (basic ×1.0, fire ×1.5 on organic, electric ×1.5 on mechanical), Burn/Shock
application + tick, Shock AP reduction, Burning tile set + exposure-gated spread, Electric
chain through CONDUCTIVE, and `Features.elements_enabled = false` → all shots physical.

## Known leftover (pre-existing, not M3)

`world/world.tscn` references the deleted `world/world.gd` and logs a load error on import.
It is an orphan (main scene is `combat_scene.tscn`) and intentionally left in place.
