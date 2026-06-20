# M25 — Sandbox II: Spawn overrides, terrain controls, inspector click, round advance

## Context

Enhancements to the `debug/sandbox_overlay.gd` CanvasLayer built in M24. All additions are
additive to the existing overlay; no production system changes except one new public method on
CombatManager.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Spawn overrides** are applied immediately after `debug_spawn()` returns — HP%, shield, armor SpinBoxes drive field writes on the returned Unit before its first draw. |
| 2 | **Status injection** uses `StatusInstance._init(def, stacks)` directly — same constructor the rest of the status system uses. `_last_spawned` tracks the most recent unit for the [Apply] button. |
| 3 | **Terrain regenerate** calls `TerrainManager.generate(seed)` then re-snaps all live units via `get_surface_row(col)` — avoids units floating or clipping after terrain changes. |
| 4 | **Inspector click** reuses the existing `HUD.set_inspected_unit()` — no duplicate inspector UI. HUD reference passed as optional 4th arg to `setup()`. |
| 5 | **`debug_advance_round()`** ticks `TileStatusSystem.tick_all` + `UnitStatusSystem.tick_all` per unit and increments `round_index`. Does not restart player/enemy turn logic — purely ticks status durations. |

---

## Files changed

| File | Change |
|---|---|
| `debug/sandbox_overlay.gd` | Spawn overrides (HP%/shield/armor SpinBoxes + status injection); TERRAIN section; inspector click in `_unhandled_input`; Rounds SpinBox + [Advance Rounds] in CHEATS |
| `systems/combat_manager.gd` | `debug_advance_round()` |
| `world/combat_scene.gd` | Pass `hud` as 4th arg to `overlay.call("setup", ...)` |

---

## Manual verification

1. **Spawn at 50% HP:** set HP% to 50 → spawn any unit → HP bar shows half. Shield/Armor SpinBoxes default to 0 — set to 5/3, spawn → stat icons appear.
2. **Status injection:** spawn a unit → select Burn from OptionButton, stacks=2 → [Apply] → Burn badge appears on the unit.
3. **Terrain regen:** type seed `999` → [Regenerate] → terrain changes shape; all units re-snap to new surface (none floating or buried).
4. **Inspector click:** click an enemy unit while overlay is open → HUD inspector opens for that unit (cyan outline + inspector panel).
5. **Advance rounds:** inject Burn on a unit, set Rounds to 2 → [Advance Rounds] → Burn ticks down 2 turns, unit takes tick damage.
