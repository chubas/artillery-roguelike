# M38 — Unit Weight Classes & Tiered Climb Costs

## Context

Introduce a `weight` field on `UnitDefinition` that controls how high a unit can climb per step and how many AP an extended climb costs. Current behavior (1-voxel climb, 1 AP) becomes the Medium default. Light units can climb higher with an extra AP; Heavy units are ground-locked.

---

## Key Decisions (locked)

| # | Decision |
|---|---|
| 1 | `UnitDefinition.weight : int = 2` — 0=weightless (future flying), 1=light, 2=medium, 3=heavy. Integer so future classes slide in without enum changes. |
| 2 | Climb rules: **Light(1)**: 1–2 vox = 1 AP, 3 vox = 2 AP; **Medium(2)**: 1 vox = 1 AP, 2 vox = 2 AP; **Heavy(3)**: no climbing. Weightless(0): unlimited. Falling is unaffected by weight for all classes. |
| 3 | `UnitMovement.resolve_move()` loops through 1..max_climb voxels finding the lowest accessible ledge. Returns NO_MOVE if no ledge is reachable within the weight limit. |
| 4 | `CombatManager._move_ap_cost()` helper: compares climb height vs `free_climb_for_weight()` — returns 1 or 2 AP. |
| 5 | Boosted move token covers 1 AP. Extended climb (2 AP) with a token still requires 1 AP from the action pool. |
| 6 | `climb_max` field removed from `UnitDefinition` — was obsolete, now fully replaced by `weight`. |
| 7 | `Features.weight_mobility_enabled` kill switch — when false, `_move_ap_cost()` always returns 1 AP. |
| 8 | All current units baked at `weight=2` (medium) with comments marking good light/heavy candidates. |

---

## Climb Limit Table

| Weight | Free climb (1 AP) | Max climb (2 AP) | Can fall? |
|--------|------------------|------------------|-----------|
| 0 (weightless) | unlimited | unlimited | yes |
| 1 (light)  | 2 voxels | 3 voxels | yes |
| 2 (medium) | 1 voxel  | 2 voxels | yes |
| 3 (heavy)  | 0 voxels | 0 voxels | yes |

---

## Files Changed

| File | Change |
|---|---|
| `data/units/unit_definition.gd` | Replaced `climb_max` with `weight : int = 2` |
| `systems/unit_movement.gd` | Added `free_climb_for_weight()`, `max_climb_for_weight()`; multi-voxel loop in `resolve_move()` |
| `systems/combat_manager.gd` | Added `_move_ap_cost()`; refactored `try_move()` AP check + deduction |
| `autoloads/features.gd` | `weight_mobility_enabled` |
| `scripts/bake_resources.gd` | Replaced `u.climb_max` with `u.weight = 2` everywhere; light/heavy candidate comments |
| `world/combat_scene.gd` | `_m38_smoke()` |
| `PROGRESS.md` | Updated header + M38 entry |

---

## Smoke Results

```
[smoke] -- M38 weight classes --
  free_climb_for_weight(0)=99 (expect 99)
  free_climb_for_weight(1)=2 (expect 2)
  free_climb_for_weight(2)=1 (expect 1)
  free_climb_for_weight(3)=0 (expect 0)
  max_climb_for_weight(0)=99 (expect 99)
  max_climb_for_weight(1)=3 (expect 3)
  max_climb_for_weight(2)=2 (expect 2)
  max_climb_for_weight(3)=0 (expect 0)
  all_player_units_weight_2=true (expect true)
  medium_3vox_cliff_result=true (expect NO_MOVE)
  heavy_1vox_blocked=true (expect NO_MOVE)
  weight_mobility_enabled=true (expect true)
```

All checks pass. Full smoke (M3–M38) completes without new errors.
