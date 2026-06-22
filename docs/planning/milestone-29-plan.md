# Milestone 29 — Unit Stacking

## Problem

The hard constraint "two units cannot occupy the same voxel" was too limiting for the intended
design. Many planned effects — area buffs, cluster mechanics, displacement effects — revolve
around multiple units sharing the same space. Dropping the constraint now prevents rework
later.

## Decisions

| # | Decision |
|---|---|
| 1 | **Visual offset: up+left, 2px per layer** — `Vector2(-2*i, -2*i)`. Purely cosmetic; hitboxes unchanged. |
| 2 | **Scroll = inspect-only** — cycling changes the inspected/HUD unit, never the active-turn unit. |
| 3 | **Scroll = hover-based** — only cycles when 2+ living entities share the hovered voxel. |
| 4 | **Placement fully allows stacking** — the overlap check in `_placement_drop()` removed. |
| 5 | **Enemy spawn: overlap check removed** — enemies can spawn on top of existing units. |
| 6 | **Mine trigger unchanged** — Chebyshev ≤ 3 already catches same-voxel (distance 0). |
| 7 | **`overlaps_any_unit()` kept** in `UnitMovement` as a utility; no longer called in the move path. |
| 8 | **ShieldGenerator aura stays at true map position** — `stack_visual_offset` shifts only the body tile in `deployable._draw()`, not the aura in `shield_generator._draw()`. |
| 9 | **Feature flag** — `stacking_enabled` gates the constraint removal; false restores all overlap checks. |

## Files changed

| File | Change |
|---|---|
| `autoloads/features.gd` | Add `stacking_enabled: bool = true` |
| `systems/unit_movement.gd` | `resolve_move()` — return settled voxel directly; remove `_final_if_unit_free()` |
| `systems/combat_manager.gd` | Remove overlap guards in `_placement_drop()` + `_find_valid_spawn()`; add `_recompute_stack_offsets()` + call sites; add scroll handler + `_scroll_stack_cycle()` + `_entities_at_vox()` |
| `world/combat_scene.gd` | Remove WHEEL_UP/DOWN zoom; add `_m29_smoke()` |
| `units/unit.gd` | Add `stack_visual_offset: Vector2`; apply `draw_set_transform` in `_draw()` |
| `world/deployable.gd` | Add `stack_visual_offset: Vector2`; apply offset to body `Rect2` in `_draw()` |
| `PROGRESS.md` | M29 entry |

## Explicitly out of scope

- Stack count badge in HUD (the 2.5D offset is the only visual cue for now)
- Mixed-faction stack cycling behavior beyond inspecting next entity
- GravityPullResolver / shove effects landing on occupied voxels (already works)
