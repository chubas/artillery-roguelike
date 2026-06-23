# Milestone 33 — RNG Architecture + Stage Profile Variation

## Goal

Give every run a unique but reproducible sequence of terrain profiles and seeds. Separate the three RNG concerns that were previously all using the global `randf()` / `randi()`:

1. **Run RNG** — deterministic sequence of stages/rewards for an entire run.
2. **Stage RNG** — reproducible per-stage mechanics (card draw, artifact effects).
3. **Combat RNG** — non-deterministic real-time events (wind, enemy fire error) that should vary within the same stage playthrough.

First stage always uses the legacy terrain generator. Subsequent stages get a random profile drawn from `run_rng`.

## Key decisions (locked)

| # | Decision |
|---|---|
| 1 | `RunState.run_meta["seed"]` (existed before, was `randi()`) is the run seed. No new field needed. |
| 2 | `Run.run_rng: RandomNumberGenerator` seeded from `run_meta["seed"]` in `start_default_run()`. |
| 3 | `MapNode` gets `terrain_profile_path: String` and `stage_seed: int`; both serialized. |
| 4 | `_assign_terrain_variations(rs)` on Run autoload iterates `rs.map.nodes`: node 0 → legacy (`terrain_profile_path = ""`), all others → random profile from `_TERRAIN_PROFILES` array. |
| 5 | `CombatScene` gets `terrain_profile_path` and `active_stage_seed` fields set by `RunController._enter_combat()` from the current `MapNode`. |
| 6 | `StageRng` autoload — Fisher-Yates shuffle, seeded from node's `stage_seed`. Used for deck shuffle. |
| 7 | `CombatRng` autoload — seeded with `stage_seed ^ Time.get_ticks_msec()`. Used for wind + enemy fire. |
| 8 | `RunController._sample()` uses `Run.run_rng.randi()` instead of global `randi()`. |
| 9 | `Features.stage_rng_enabled` gates all RNG routing. False → built-in `.shuffle()` + global `randf_range()`. |

## Files changed

| File | Change |
|---|---|
| `autoloads/run.gd` | Add `run_rng`, `_TERRAIN_PROFILES`, seed in `start_default_run()`, `_assign_terrain_variations()` |
| `state/map_node.gd` | Add `terrain_profile_path`, `stage_seed`; update `to_dict()/from_dict()` |
| `autoloads/stage_rng.gd` | NEW — seeded Fisher-Yates shuffle |
| `autoloads/combat_rng.gd` | NEW — timestamp-salted combat RNG |
| `project.godot` | Register `StageRng` and `CombatRng` after `Run` |
| `autoloads/features.gd` | Add `stage_rng_enabled` |
| `world/combat_scene.gd` | Add fields; wire RNG init before `_setup_terrain()`; update `_setup_terrain()` to use overrides; add `_m33_smoke()` |
| `world/run_controller.gd` | Set node fields in `_enter_combat()`; `_sample()` uses `Run.run_rng` |
| `systems/combat_manager.gd` | Deck shuffles → `StageRng.shuffle()`; wind → `CombatRng.rng.randf_range()` |
| `systems/enemy_system.gd` | Fire error → `CombatRng.rng.randf_range()` |

## Smoke results (2026-06-23)

```
[smoke] -- M33 RNG architecture --
  StageRng.rng.seed=12345 (expect nonzero)
  CombatRng.rng.seed=12576 (expect nonzero)
  determinism: s1=3551608539 s2=3551608539 match=true (expect true)
  node[0] profile='' (expect empty)
  node[1] profile='res://data/terrain/profiles/open_field.tres' (expect nonempty)
```

All M1–M32 checks pass.

## Out of scope

- Act-based profile weighting
- Save/load of `run_seed` across sessions
- Artifact effect hooks using `StageRng` (essences still use `randf()`)
- Shop / event node randomization (node types don't exist yet)
