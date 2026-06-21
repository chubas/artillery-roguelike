# M28 — Aura Visualization + Deployable Selection

## Goal

Make the shield generator's aura visible on the map as a discrete voxel-circle overlay, and let
the player click any deployable (mine or shield generator) to open an inspector panel — mirroring
the unit inspector already in the HUD.

---

## Locked decisions

| # | Decision |
|---|---|
| 1 | **Euclidean circle** (`dx² + dy² <= r²`, integer math) replaces Chebyshev (square) for the aura shape. `_chebyshev()` in CombatManager stays — mines still use it for proximity triggers. |
| 2 | **Precomputed voxel offset arrays** in `ShieldGenerator._ready()`: `_fill_offsets` (all voxels in circle) and `_border_offsets` (fill voxels with at least one 4-orthogonal neighbor outside the circle). O(1) lookup via a `Dictionary` fill_set during build. |
| 3 | **Aura drawn in `ShieldGenerator._draw()`** using local-space offsets from the generator's origin voxel. Fill first, border ring second, body tile via `super._draw()` last (body sits on top). |
| 4 | **Aura alpha:** fill 0.12 (rest) / 0.22 (hover or selected); border 0.28 / 0.45. Color from existing `color` field. |
| 5 | **Hover detected in `_process()`** via `bounds_rect_world().has_point(get_global_mouse_position())` — only the body tile rect, not the aura. `queue_redraw()` only when state changes. |
| 6 | **`hovered` and `selected` bool fields on `Deployable`** (base class). Border highlight drawn in `Deployable._draw()`: white border when selected, lightened when hovered, darkened otherwise. |
| 7 | **`inspected_deployable` field on `CombatManager`** alongside `inspected_unit`. `_inspect_deployable(d)` helper clears old selection and sets new one. Selecting a deployable clears the unit selection and vice versa. |
| 8 | **`_try_click_select()` extended** — after unit checks, iterates `deployables` and calls `_inspect_deployable(d)`. Existing unit-click paths call `_inspect_deployable(null)` to clear. |
| 9 | **`_push_hud_state()` calls `_hud.set_inspected_deployable(inspected_deployable)`** after the existing `set_inspected_unit` call. |
| 10 | **`DeployableInspector` inner class in `hud.gd`** — same pattern as `UnitInspector`. Code-drawn `_draw()`. Mutually exclusive with `_inspector` (unit panel): showing one hides the other. Positioned identically to the unit inspector (bottom-right, 240×195 px panel). |
| 11 | **Type-specific stats** — `ShieldGenerator` shows "Shield / turn" + "Radius"; `Mine` shows "Damage" + "Terrain dmg". Typed with `is`/`as` casts in `_draw()`. |
| 12 | **`shield_amount` default changed from 2 → 3.** |
| 13 | **No new feature flag** — this is a UI enhancement on an existing gameplay system, not a new gameplay gate. |
| 14 | **No bake needed** — no new Resource schema changes. |

---

## Files changed

| File | Change |
|---|---|
| `world/deployable.gd` | Add `hovered`, `selected` bool fields; update `_draw()` with highlight ring |
| `world/shield_generator.gd` | Euclidean `_build_aura_offsets()` in `_ready()`; `_draw()` with aura fill + border outline; `_process()` hover poll; `shield_amount` default → 3 |
| `systems/combat_manager.gd` | `_pulse_shield_generators()` → Euclidean distance; `inspected_deployable` field; `_inspect_deployable()` helper; `_try_click_select()` → deployable branch; `_push_hud_state()` + `_start_player_turn()` wiring |
| `ui/hud.gd` | `_dep_inspector` field; `_build_bottom_right()` setup; `set_inspected_deployable()` method; `DeployableInspector` inner class |

---

## Smoke test

No new smoke checks added — aura and inspector are visual/interactive features verified manually.
All M3–M27 smoke checks continue to pass.

---

## Deferred

- Aura visualization for other future deployable types (no general `Aura` base class yet — YAGNI).
- Mine hover detection in `_process()` (mines don't have an aura; hover state on Mine not wired to `_process()` — only `Deployable._draw()` uses `hovered`, which is set to false by default and could be wired later).
- Deployable HP bar in the inspector panel.
