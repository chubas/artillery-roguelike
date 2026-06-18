# Milestone 9 — Artifact System

## What was built

A hook-driven engine for passive squad-wide effects, plus 7 initial artifact implementations.
Artifacts trigger at specific game events (round start, unit death, card play, projectile impact)
and can read/modify game state through a shared `ArtifactContext`.

---

## Locked Decisions

| # | Decision |
|---|----------|
| 1 | `ArtifactDef` extends `Resource` with virtual hook methods. Concrete artifacts are `class_name` subclasses, each in their own `.gd` file, baked to `.tres` in `data/artifacts/resources/`. |
| 2 | `ArtifactSystem` is a static dispatcher (same pattern as `TileStatusSystem`/`UnitStatusSystem`). Gated at every call site by `Features.artifacts_enabled`. |
| 3 | `ArtifactContext` is a `RefCounted` bag (terrain, units array, combat Node ref). Built once in `CombatManager._init_artifacts()`, reused for the whole combat. |
| 4 | `CombatManager._ARTIFACT_LOADOUT: Array` holds resource paths to activate. Empty by default — populate to enable artifacts in a stage. |
| 5 | Artifact #4 "first card costs 0" is **per-combat** (not per-run). `reset_per_combat()` is called at `call_combat_start`. |
| 6 | Artifact #3 enemy debuff stacks indefinitely (by user decision); effective damage = `max(0, base + modifier)` at fire time. |
| 7 | `Unit.attack_modifier: int` is applied in `ProjectileManager.fire()`: `effective = max(0, base_str + modifier)`. |
| 8 | `Unit.moved_this_turn: bool` set true in `CombatManager.try_move()`, reset to false at `_begin_round()` before artifact hooks run. |
| 9 | `Projectile.flight_time: float` is accumulated in `_physics_process(delta)`, stored in the impact pending dict so `modify_projectile_strength` reads it at resolution. |
| 10 | Killer tracking: `CombatManager._last_firing_unit` records the most recent unit to fire (player or enemy); passed as `killer` to `call_unit_killed`. |

---

## Bug found during implementation

GDScript's native `Resource` class has a method called `reset_state()` — overriding it
is treated as an error: *"Warning treated as error."* The hook was renamed to
`reset_per_combat()` throughout (`ArtifactDef`, `ArtifactSystem`, and the two one-shot
artifact implementations that use it).

---

## Files Changed

| File | Change |
|---|---|
| `data/artifact_def.gd` | NEW — base Resource class with virtual hooks |
| `data/artifact_context.gd` | NEW — RefCounted context bag |
| `systems/artifact_system.gd` | NEW — static dispatcher with gate |
| `data/artifacts/artifact_squad_regen.gd` | NEW |
| `data/artifacts/artifact_lifesteal.gd` | NEW |
| `data/artifacts/artifact_enemy_debuff.gd` | NEW |
| `data/artifacts/artifact_free_first_card.gd` | NEW |
| `data/artifacts/artifact_idle_actions.gd` | NEW |
| `data/artifacts/artifact_death_explosion.gd` | NEW |
| `data/artifacts/artifact_long_flight.gd` | NEW |
| `data/artifacts/resources/*.tres` (×7) | NEW — baked artifact resources |
| `autoloads/features.gd` | `artifacts_enabled = true` |
| `units/unit.gd` | `attack_modifier: int`, `moved_this_turn: bool` |
| `projectile/projectile.gd` | `flight_time: float` + accumulation in `_physics_process` |
| `projectile/projectile_manager.gd` | `Salvo.firing_unit`, `_combat` ref, `apply_projectile_strength` in `_resolve_impact`, `attack_modifier` in `fire()`, `flight_time` in pending dict |
| `systems/combat_manager.gd` | artifacts list, context, `_init_artifacts()`, hook call sites in `_begin_round`/`end_player_turn`/`_apply_card`/`_on_unit_died`/`try_move`, `_last_firing_unit` |
| `scripts/bake_resources.gd` | `data/artifacts/resources/` dir + 7 bake entries |
| `world/combat_scene.gd` | `_m9_smoke()` |
| `PROGRESS.md` | new dated entry |
| `milestone-9-plan.md` | this file |

---

## Smoke Test Checklist (all pass)

- `ArtifactFreeFirstCard.modify_card_cost()`: returns 0 on first call, base cost on second
- `ArtifactLongFlight.modify_projectile_strength()`: unchanged at 9s, ×1.2 floor at 11s
- `ArtifactIdleActions.bonus_actions_on_round_start()`: returns player count when none moved, -1 when one moved
- `ArtifactEnemyDebuff.on_player_turn_end()`: stacks -3 per call on enemy `attack_modifier`
- `ArtifactSquadRegen.on_round_start()`: heals player unit +1 HP (not beyond max)
- `ArtifactSystem.apply_card_cost()` pipeline: returns 0 with free-first-card artifact active
- No ERROR lines in `ARTILLERY_SMOKE=1 godot --headless`
