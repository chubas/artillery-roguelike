# Milestone 14 — Linear Run Loop (MapState + run controller)

## What was built

The loop that makes stages into a *run*: a linear `MapState`, a `RunController` that swaps between
a map screen and combat, and the map↔combat flow with `RunState` carrying HP/kills/disabled across
stages. (Run-state spec §7, build-order step 7.) Deliberately "dead simple": linear, 3 COMBAT
nodes, no branching, no events/shops — those are M15+.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | Map is **linear**, 3 COMBAT nodes; `MapNode.Type` reserves EVENT/SHOP/BOSS for later. |
| 2 | `RunController` is the **new main scene** and instances `combat_scene` per stage (re-instancing = the per-stage combat reset). |
| 3 | `combat_scene` stays **standalone-runnable** (self-bootstraps a default run + `stage_01`). |
| 4 | Write-back stays in `combat_scene`; the controller only reads `Run.active` to decide flow. |
| 5 | Run ends on a lost stage **or** whole-squad-disabled → "RUN OVER"; clearing the last node → "RUN COMPLETE"; "New Run" rebuilds the default run. |

---

## New files

- `state/map_node.gd` — `MapNode` (type + `stage_path`; `stage()`, `threat_tags()`, to/from_dict,
  `make_combat`).
- `state/map_state.gd` — `MapState` (nodes/current/visited; `current_node`, `is_last`,
  `mark_visited`, `advance`, `is_complete`, `build_linear`, to/from_dict).
- `world/run_controller.gd` + `world/run_controller.tscn` — the run-flow controller / main scene.
- `ui/map_screen.gd` — `MapScreen` (CanvasLayer, code-drawn): node strip + detail + Enter Stage +
  end banner; signals `stage_selected(node)` / `new_run_requested`.
- `data/stages/stage_03.tres` — baked third stage (defeat-all, seed 24680).

## Changed files

- `state/run_state.gd` — `to_dict`/`from_dict` serialize `map` (a `MapState`).
- `autoloads/run.gd` — `start_default_run()` builds `MapState.build_linear(_DEFAULT_MAP)`
  (stage_01/02/03).
- `world/combat_scene.gd` — `signal combat_exited(outcome)` emitted after write-back; `_m14_smoke()`.
- `scripts/bake_resources.gd` — bake `stage_03`.
- `project.godot` — `run/main_scene` → `run_controller.tscn`.

---

## Flow (run_controller.gd)

```
_ready: smoke → _enter_combat(null) (combat_scene runs the chain + quits)
        else  → ensure Run.active; _show_map
_show_map: swap in MapScreen(map); stage_selected→_enter_combat, new_run_requested→_restart
_enter_combat(node): instance combat_scene, set .stage before add_child, connect combat_exited
_on_combat_exited(outcome):
   any_alive = squad has a non-disabled unit
   cleared & any_alive → map.mark_visited; last? "RUN COMPLETE" : (map.advance; _show_map)
   else → "RUN OVER"
```

`_swap` frees the old child (`queue_free`, safe mid-signal) and adds the new one.

---

## Verification

- **Bake:** `--import` → `-s scripts/bake_resources.gd` → `--import` (stage_03).
- **`_m14_smoke()`** (deterministic — drives `MapState`/`RunState`, not the awaited scene swap):
  default map has 3 nodes / current 0 / COMBAT; `mark_visited`+`advance` walk to node 2 with
  `is_last` true and `is_complete` only after all visited; all-disabled squad → `any_alive` false;
  `RunState.from_dict(to_dict())` preserves map nodes/current/visited.
- **Regression:** `ARTILLERY_SMOKE=1 godot --headless` — controller (now main scene) instances
  combat_scene; all 44 M4–M14 checks pass, 0 ERROR lines, no leaked instances.
- **Non-smoke launch:** headless boots to the map screen with no errors (validated ~4s idle).
- **Manual:** map → Enter Stage 1 → clear → back at node 2 (node 1 cleared, HP carried) → … →
  "RUN COMPLETE"; lose a stage / whole squad disabled → "RUN OVER" → New Run resets.

---

## Notable fix

`var cs := load(scene).instantiate()` failed to parse (untyped return) — annotated
`var cs : Node = (load(...) as PackedScene).instantiate()`.

---

## Seams for later milestones

- **M15 (placement):** the controller can insert a placement phase between map and combat.
- **M16 (squad select):** a pre-run screen sets `Run.active.squad` before the first `_show_map`.
- **M17 (events/rewards):** `MapNode.Type` EVENT/SHOP + branching edges (currently linear); the
  map screen already reads `threat_tags` for telegraphing.
- Save/load: `RunState`/`MapState` now fully round-trip via `to_dict`/`from_dict`.
