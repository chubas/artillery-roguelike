# Milestone 8 — Wind Mechanic

## What was built

Wind is the first stage environmental force. It applies a horizontal acceleration to
projectiles each frame and, when strong enough, drives fire to spread across the terrain
in the wind direction.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | Wind stored as `wind_strength: float` in `[-1.0, 1.0]` on `CombatManager`. Actual projectile force = `wind_strength × MAX_WIND_FORCE` where `MAX_WIND_FORCE = 300.0` px/s² (≈30% of gravity). Tunable via `constants.gd`. |
| 2 | Wind updated once per round in `_begin_round()`, after `_check_reinforcements()` but before `TileStatusSystem.tick_all()`. |
| 3 | Stage wind config lives as `const _WIND_CONFIG : Dictionary` on `CombatManager` (mirrors `_REINFORCEMENT_SCHEDULE`). Fields: `start_round`, `ramp_per_round`, `max_strength`. Test-stage defaults: 3 / 0.05 / 1.0. |
| 4 | `EventBus.wind_changed(strength: float)` emitted each round so HUD and `TargetingOverlay` stay in sync without polling. |
| 5 | Projectile gets `wind_force_x` at launch time from `ProjectileManager.current_wind_force`. `Trajectory.simulate_arc()` takes the same param so preview === reality. |
| 6 | Wind spread threshold: `abs(wind_strength) >= 0.2`. Spread runs in `_wind_spread_fire()` after `TileStatusSystem.tick_all()`. Vehicle-movement rule: blocked if target column surface is >1 voxel higher than burning tile. |
| 7 | `WindIndicator` inner class in `hud.gd`, top-right corner. 0–20% = white, 20–50% = orange, >50% = red. Hidden when calm. |
| 8 | `Features.wind_enabled = true` (was stubbed false). Single gate checked at `_update_wind_for_round()`. |

---

## Bug found during verification

`signi(float)` in GDScript truncates the float to `int` before computing sign, so
`signi(0.25) = signi(0) = 0`. Wind spread was silently a no-op for any fractional
`wind_strength`. Fixed to `var wind_dir : int = 1 if wind_strength > 0.0 else -1`.

---

## Files changed

| File | Change |
|---|---|
| `constants.gd` | `MAX_WIND_FORCE = 300.0`, `WIND_SPREAD_THRESHOLD = 0.2` |
| `autoloads/features.gd` | `wind_enabled = true` |
| `autoloads/event_bus.gd` | `signal wind_changed(strength: float)` |
| `systems/combat_manager.gd` | `_WIND_CONFIG`, `wind_strength`, `_update_wind_for_round()`, `_wind_spread_fire()` (+ `signi` bug fix), `_all_waves_spawned()` stage-clear gate |
| `projectile/projectile.gd` | `wind_force_x` field + accumulation in `_physics_process()` |
| `projectile/projectile_manager.gd` | `current_wind_force` field; forwarded to all launch paths |
| `projectile/trajectory.gd` | `wind_force_x` param on `simulate_arc()` |
| `ui/targeting_overlay.gd` | Caches `_wind_force_x` from `wind_changed`; passed to all `simulate_arc()` calls |
| `ui/hud.gd` | `WindIndicator` inner class + placement |
| `world/combat_scene.gd` | `_m8_smoke()` |

---

## Smoke test checklist (all pass)

- Round 2: `wind_strength == 0.0` (before `start_round`)
- Round 3 (30 trials): `abs(wind_strength) <= 0.05`
- Round 8 (30 trials): `abs(wind_strength) <= 0.30`
- `wind=0.1`: fire does not spread (below threshold)
- `wind=0.25`: fire spreads to flat adjacent FLAMMABLE column
- `Trajectory.simulate_arc(wind_force_x=300)` produces different endpoint than without wind

---

## On smoke test philosophy

The smoke tests run inside the real `CombatScene` with shared terrain state — they are
"does it compile and do basic numbers add up" checks, not isolated unit tests. State from
earlier milestone tests bleeds into later ones, which is why the spread test scans for a
flat adjacent pair rather than assuming specific column positions. A dedicated `TestScene`
with a hand-crafted small terrain would make these cleaner; that's a future concern when
test coverage becomes a priority.
