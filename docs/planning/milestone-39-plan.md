# Milestone 39 — Unified Damage Formula

**Status:** Complete (2026-06-29)

## Goal

Consolidate attack power into a single, readable formula with one rounding step. Remove the implicit multi-axis damage system (shot.strength × unit.power × attack_modifier) and replace it with a single entry-point static class (`DamageResolver`) that owns the full formula.

---

## Formula

```
final_damage = floor((unit.attack + combat_flat + conditional_bonus) × permanent_mult × combat_mult × zone_multiplier × element_affinity)
```

- `unit.attack` — base attack; includes `run_state.bonus_attack` baked in at `_ready()` 
- `combat_flat` — in-combat additive bonus (renamed from `attack_modifier`); cards/artifacts/debuffs write here
- `conditional_bonus` — from `ShotDefinition.conditional_bonus` + `ShotContext`; always 0 for current shots (scaffolding)
- `permanent_mult` — from `RunUnitState.permanent_mult`; default 1.0; flows into `combat_mult` at combat start
- `combat_mult` — in-combat multiplier (renamed from `Unit.power`); starts at `permanent_mult` each combat
- `zone_multiplier` — from `AoEGroup.multiplier`: 1.0 core, 0.5 edge (unchanged)
- `element_affinity` — from element tag matching + `vs_hp_mult` in `take_damage()` (unchanged logic)
- `floor()` once at the very end; can be 0 — no minimum anywhere

---

## Key Decisions

| # | Decision |
|---|---|
| 1 | `ShotDefinition.strength` and `strength_mult` removed. Shots carry only AoE pattern, element, keywords. |
| 2 | `UnitDefinition.base_power` removed. `Unit.power` renamed `combat_mult` (initialized from `permanent_mult`). |
| 3 | `Unit.attack_modifier` renamed `combat_flat`. All callers updated. |
| 4 | New `DamageResolver` static class: single `compute_base()` entry point returning `float`. |
| 5 | `AoEResolver._zone_damage()` → `float` (no round/min). `_calc_damage()` → `_calc_affinity()` returns mult only. Final: `int(floor(zone_dmg × affinity))`. |
| 6 | Dig unchanged. `shot.dig_mult`, `unit.dig`, `dig_modifier`, terrain min-1 all stay. |
| 7 | `player_split` baked at `attack = 1` — multishot unit; lower per-hit power is the design intent. |
| 8 | `★ N` attack display in UnitInspector; shows `★ N (+M)` if `combat_flat != 0`. |
| 9 | `ShotContext` class created (scaffolding for conditional bonuses; empty for all current shots). |
| 10 | `Features.power_formula_enabled` — when false, skips `permanent_mult` and `conditional_bonus`. |

---

## Rounding Behaviour Change

Old formula applied `round()` + `max(1, …)` three times (pre-zone, zone multiplier, affinity). New formula applies `floor()` once at the final step, no minimum.

For integer inputs with integer multipliers (most core-zone cases), results are unchanged. Notable differences:
- **Edge zone** (base=3, zone×0.5): old = `max(1, round(1.5)) = 2`; new = `floor(1.5) = 1`
- **Low-power edge** (base=1, zone×0.5): old = 1 (min-1); new = `floor(0.5) = 0`
- **Element affinity stacking note:** element affinity (`strong_vs_tag`) is applied in `_calc_affinity()` (AoEResolver), while `vs_hp_mult` is applied separately in `unit.take_damage()`. Both stack multiplicatively, which was always the behavior — the old M3 smoke expect strings of "-4" were wrong; the actual combined result was "-6" for fire on organic and "-2" for electric on mechanical. M39 corrects these expect strings.

---

## Files Changed

| File | Change |
|---|---|
| `data/shots/shot_context.gd` | NEW — scaffolding for conditional bonus evaluation |
| `systems/damage_resolver.gd` | NEW — `compute_base()` entry point |
| `data/units/unit_definition.gd` | Remove `base_power` |
| `data/shots/shot_definition.gd` | Remove `strength`/`strength_mult`; add `conditional_bonus`; update `resolve_params()` |
| `state/run_unit_state.gd` | Add `permanent_mult` + serialization |
| `units/unit.gd` | Rename `power`→`combat_mult`, `attack_modifier`→`combat_flat`; update `_ready()` |
| `terrain/aoe_resolver.gd` | Float strength; `_zone_damage()` no-min, `_calc_affinity()` returns mult; `floor()` at call site |
| `projectile/projectile_manager.gd` | Build `ShotContext`; `DamageResolver.compute_base()`; `Salvo.strength: float` |
| `data/artifacts/artifact_enemy_debuff.gd` | `attack_modifier` → `combat_flat` |
| `autoloads/features.gd` | Add `power_formula_enabled` |
| `ui/hud.gd` | `★ N` attack stat in UnitInspector |
| `scripts/bake_resources.gd` | Remove `strength`/`strength_mult` bake lines; `player_split` attack=1 |
| `world/combat_scene.gd` | M7/M9 field renames; M3 expect string corrections; `_m39_smoke()` |

---

## Smoke Test Results

All M39 checks pass:
- `compute_base(atk=3, flat=0, mult=1.0) = 3.0` ✓
- `compute_base(atk=3, mult=2.0) = 6.0` ✓
- `compute_base(atk=3, flat=2, mult=2.0) = 10.0` ✓
- `edge zone floor(3×0.5) = 1` ✓
- `low edge floor(1×0.5) = 0` (no min-1) ✓
- `empty conditional_bonus = 3.0` ✓
- `flag_off = 3.0` ✓
- `player_split.attack = 1` ✓
