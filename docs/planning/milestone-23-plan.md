# Milestone 23 — Unit Capacity & Skip Rewards

## What was built

Two run-management features:
1. **Unit capacity** — the player has 8 total capacity; every current unit costs 2, so the squad
   cap is 4. Enforced at the reward screen and displayed on the map and unit reward cards.
2. **Skip rewards** — card and artifact reward offers can be declined; unit offers are suppressed
   entirely when at capacity (no in-between "can't take it" state needed).

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **`UnitDefinition.capacity_cost: int = 2`** — GDScript default propagates to all existing `.tres` files automatically; no bake required. |
| 2 | **`RunState.MAX_SQUAD_CAPACITY := 8`** — a constant, not a field; capacity limit is a game rule, not per-run data. |
| 3 | **UNIT reward suppressed (not disabled) at capacity.** `_pick_reward_options(UNIT)` returns `[]`; the existing `continue` in `_show_next_reward` skips the category. Cleaner than showing three cards the player cannot take. |
| 4 | **No `Features` kill-switch.** Capacity and skip are core game rules applied from the start; they are not optional systems. The smoke path bypasses reward flow (`_enter_combat(null)`) so no gating was needed for tests. |
| 5 | **Skip shown for all reward categories**, including UNIT. The player may always decline an offer. |
| 6 | **Capacity label on `MapScreen` is a plain Label in the existing VBox** — no inner class, no new code-draw pattern. |

---

## Integration points

| File | Change |
|---|---|
| `data/units/unit_definition.gd` | Replaced TODO comment with `@export var capacity_cost: int = 2` |
| `state/run_state.gd` | `const MAX_SQUAD_CAPACITY := 8` |
| `world/run_controller.gd` | `_used_capacity()` helper; capacity guard in `_pick_reward_options(UNIT)`; connect `reward_skipped`; `_on_reward_skipped()` |
| `ui/reward_screen.gd` | `signal reward_skipped()`; skip label + `_on_skip_input()` in `_build()`; `capacity_cost` stat in `_draw_unit()` |
| `ui/map_screen.gd` | `_capacity_label` field; add after title in `_build()`; populate in `_refresh()` |
| `world/combat_scene.gd` | `_m23_smoke()` + call |
| `docs/planning/milestone-23-plan.md` | This file |
| `PROGRESS.md` | M23 entry |

---

## Seams for later

| Seam | Notes |
|------|-------|
| **Variable capacity costs** | `capacity_cost` field already exists; just needs content authoring (heavy = 3, scout = 1) |
| **Mutable capacity limit** | `RunState.MAX_SQUAD_CAPACITY` can become a `var` upgraded by artifacts or map events |
| **"Skip All" shortcut** | One button to advance past the entire reward sequence with no rewards |
| **Retire mechanic** | Removing a unit from squad to free capacity — planned, not in scope for M23 |
