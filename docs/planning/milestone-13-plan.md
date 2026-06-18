# Milestone 13 — Stage as Data (StageDescriptor) + Objective Evaluator

## What was built

The stage stops being hardcoded in `CombatManager`. Everything it used to bake in — enemies,
reinforcement schedule, deployable placements, wind profile, terrain seed, win condition — moves
into a **`StageDescriptor`** the scene reads, and the win/loss check becomes a data-driven
**objective evaluator** (defeat-all + survive-N). Once a stage is data, the map (M14) is a graph
of these. (Run-state spec §5 + §9, steps 4 + 6 of the build order.)

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | Stage descriptors are **hand-authored `.tres`** (Resource subclasses baked via `bake_resources.gd`). |
| 2 | `stage_01` reproduces today's content **exactly** (seed 12345, same enemies/waves/deployables/wind, defeat-all) so the live game + all M4–M12 smoke tests are unchanged. |
| 3 | Objective types this milestone: **DEFEAT_ALL** (existing gate) + **SURVIVE_N** only. Reach/hold-zone need zone defs tied to placement (M15). |
| 4 | The objective evaluator is **static + pure** (explicit args, not a context object yet). |
| 5 | `terrain_seed` is wired now (clean: `generate(seed)` + scene-driven generation timing). |
| 6 | `combat_scene` owns the active stage for now (defaults to `stage_01`); M14's run controller will set it from the map node. |

---

## New files

- `data/stages/objective_descriptor.gd` — `ObjectiveDescriptor` (Resource): `type` (DEFEAT_ALL /
  SURVIVE_N), `survive_rounds`.
- `data/stages/stage_descriptor.gd` — `StageDescriptor` (Resource): `terrain_seed`,
  `initial_enemies`, `reinforcements`, `deployables`, `wind_*`, `objective`, reserved
  `rewards`/`threat_tags`.
- `systems/objective_evaluator.gd` — `ObjectiveEvaluator.evaluate(obj, enemies_alive,
  players_alive, round_index, all_waves_spawned) → Result {ONGOING, WON, LOST}`.
- `data/stages/stage_01.tres`, `stage_02.tres` — baked.

## Changed files

- `terrain/terrain_manager.gd` — `generate(seed := Const.NOISE_SEED)` (surface noise + derived
  cave/HP/variant seeds use it); `_ready` only allocates the grid (no auto-generate).
- `systems/combat_manager.gd` — `setup(..., stage)`; `_spawn_enemies` / `_check_reinforcements` /
  `_spawn_reinforcement` / `_reinforcement_warnings` / `_all_waves_spawned` / `_update_wind_for_round`
  / `_spawn_deployables` all read `_stage`; reinforcement dict key `def`→`unit`; win/loss replaced
  by `_check_objective()` (called on death and at `_start_player_turn` top); removed the
  `_REINFORCEMENT_SCHEDULE` / `_WIND_CONFIG` / `_DEPLOYABLE_PLACEMENTS` consts.
- `world/combat_scene.gd` — `var stage`; loads `stage_01` by default, `terrain.generate(stage
  .terrain_seed)` before `renderer.setup`, passes `stage` to `combat.setup`; `_m13_smoke()`.
- `scripts/bake_resources.gd` — bakes the two stages (+ `data/stages` dir).

---

## Verification

- **Bake:** `--import` → `-s scripts/bake_resources.gd` → `--import` (two new `.tres`).
- **`_m13_smoke()`:** descriptor shape (stage_01: 2 enemies / 2 waves / 3 deployables / DEFEAT_ALL;
  stage_02: SURVIVE_N / survive_rounds 4 / seed 777); evaluator verdicts for both types across
  enemies-alive / waves-pending / cleared / squad-wiped / round-3 / round-4; `generate(12345)` vs
  `generate(777)` give different surface rows.
- **Regression:** `ARTILLERY_SMOKE=1 godot --headless` — live combat boots `stage_01`; all M4–M12
  checklists pass unchanged (EnemyA@100, EnemyB@107, reinforcements col 94 r2 / r5, identical
  terrain), 0 ERROR lines.

---

## Seams for later milestones

- **M14:** the run/scene-flow controller sets `combat_scene.stage` from the active `MapState` node
  and consumes `combat_finished`; `StageDescriptor.threat_tags` feeds the map's threat preview.
- **M15:** REACH_ZONE / HOLD_ZONE objective types + a `spawn_zone` field (placement).
- **M17:** `StageDescriptor.rewards` granting.
- Wind RNG is still unseeded (only terrain is reproducible); fold into `run_meta.seed` if full
  determinism is wanted later.
