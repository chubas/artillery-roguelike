# Milestone 12 — Run-State Backbone & Combat I/O Contract

## What was built

The first layer of the roguelite run (run-state spec steps 1–3): a persistent `RunState`, the
read/write contract that connects it to combat, and the `CombatBridge` seam that keeps
`CombatManager` from absorbing run I/O. The stage stays hardcoded — `StageDescriptor` extraction
is M13. Gate: the §4.3 proof that HP persists across a stage boundary while combat state resets.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | `Run` **autoload** is the single source of truth (3rd autoload, after EventBus/Features). |
| 2 | `RunState`/`RunUnitState` are plain `RefCounted` with `to_dict`/`from_dict` — serialization-ready, **no disk I/O** (schema will churn while the run layer settles). |
| 3 | A dedicated **`CombatBridge`** (static) owns RunState↔combat translation; `CombatManager` is parameterized and never touches `RunState`. |
| 4 | Persist/discard boundary is **structural**: persistent truth in `RunUnitState`; fresh `Unit` nodes each combat reset everything else. |
| 5 | `definition_id` / deck / artifacts are **resource paths** for now (id-as-path); a real id registry is later. |
| 6 | Stage (enemies, reinforcements, wind, deployables) stays hardcoded — M13 target. |

---

## Persist / discard boundary

- **Persist** (`RunUnitState`): `current_hp`, `kills`, `is_disabled`, `max_hp`, `upgrades`,
  `equipment`. (`RunState`): `deck`, `artifacts`, `resources`, `map`, `run_meta`.
- **Reset per combat** (lives only on the `Unit`/combat layer, never copied out): shields,
  effects/`active_statuses`, position, AP, hand/discard. Artifact `reset_per_combat` still fires.

---

## New files

- `state/run_unit_state.gd` — `RunUnitState` + `to_dict`/`from_dict` + `from_definition(path)`
  (full-HP factory).
- `state/run_state.gd` — `RunState` + `to_dict`/`from_dict`.
- `autoloads/run.gd` — `Run` autoload: `active : RunState`, `start_default_run()` (canonical
  default squad/deck/artifact lists live here now). Registered in `project.godot [autoload]`.
- `systems/combat_bridge.gd` — `CombatBridge` (static):
  - `build_squad(rs) -> Array` — non-disabled `RunUnitState`→`Unit` (sets `definition`,
    `run_state`, `is_player`, name; does **not** add to tree).
  - `write_back(rs, player_units)` — copies `hp→current_hp`, `kills→kills`, sets `is_disabled`
    when `hp <= 0` (via each unit's `run_state` back-ref).

## Changed files

- `units/unit.gd` — `run_state`, `kills`; `_ready()` initializes hp/kills/attack from `run_state`
  when present (else full HP). `_derive_attack()` = `definition.attack` (upgrade seam).
- `systems/combat_manager.gd` — `setup()` takes `squad` / `deck_source` / `artifact_paths`;
  `_spawn_all_units` → `_place_player_squad` + `_spawn_enemies`; `_build_deck`/`_init_artifacts`
  read the passed sources; `_DECK_LIST`/`_ARTIFACT_LOADOUT` consts removed; player kill-credit in
  `_on_unit_died`; `combat_finished(outcome)` signal on stage clear / loss.
- `world/combat_scene.gd` — `_ready()` bootstraps the default run, builds the squad via the
  bridge, passes squad/deck/artifacts to `setup()`, and on `combat_finished` calls
  `CombatBridge.write_back()` + logs the persisted squad. `_m12_smoke()` harness.

---

## Verification

- **Import only** (no new `.tres`): `godot --headless --import` registers the `Run` autoload.
- **`_m12_smoke()`** (deterministic, temp holders fire `Unit._ready` off the live squad):
  stage-1 build → A spawns at `max-2` (current, not max), attack from definition; write-back →
  A `current_hp` lowered + `kills` carried, B (0 HP) `is_disabled`; stage-2 build → B excluded, A
  at persisted HP with a fresh (0) shield; `from_dict(to_dict())` round-trips squad/deck/hp.
- **Regression:** `ARTILLERY_SMOKE=1 godot --headless` — live combat now boots from the default
  run; all M4–M11 checklists pass unchanged (same squad order/names, 11-card deck, 8 artifacts);
  0 ERROR lines.

---

## Seams left for later milestones

- **M13:** `_spawn_enemies` + `_REINFORCEMENT_SCHEDULE` + `_WIND_CONFIG` +
  `_DEPLOYABLE_PLACEMENTS` → `StageDescriptor`; objective evaluator.
- **M14:** a run/scene-flow controller consumes `combat_finished` to advance `MapState` (here
  `combat_scene` just writes back + logs); `RunState.map` is a placeholder.
- **Upgrades/equipment:** `RunUnitState.upgrades`/`equipment` are empty; `Unit._derive_attack`
  and `max_hp` are the fold-in points. The HP bar still draws against `definition.max_hp`.
- **Disk save/load:** `to_dict`/`from_dict` are the foundation; no file format committed yet.
