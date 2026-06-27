# M37 — Card Viewer + Squad Viewer

## Context

Add two persistent UI overlays accessible from both the world map and combat views. The player needs a way to review their current deck and squad roster at any point in a run without interrupting flow. A "Deck [N]" indicator opens a modal deck browser; a "Squad" button opens a modal squad viewer with an optional retire action (world view only).

---

## Key Decisions (locked)

| # | Decision |
|---|---|
| 1 | Both viewers extend `Control` (not `CanvasLayer`) with `set_as_top_level(true)` and `set_anchors_preset(PRESET_FULL_RECT)`. This allows `add_child()` from any parent while rendering at viewport level above everything else. |
| 2 | MapScreen: "Deck [N]" Button at left of top_row; "Squad" Button at right. Deck button text updated each `_refresh()`. |
| 3 | HUD: existing `_deck_label : Label` replaced with `_deck_btn : Button` — same text, now clickable. Squad button added in `_build_top_right()` below Undo. |
| 4 | Button + Label node approach (same as RepairScreen/UpgradeScreen) — raw `_draw()` is reserved for HUD inner classes. |
| 5 | DeckViewer two-column layout: left = `ScrollContainer` card list, right = detail panel. Card hover (`mouse_entered`) updates detail. Clicking backdrop closes. |
| 6 | SquadViewer: `world_mode: bool` param. Retire button visible only in world mode; hidden entirely in combat. Clicking a row toggles selection (gold text highlight). Retire calls `SquadOps.retire_unit()` and emits `retired`. |
| 7 | HP shown in SquadViewer uses `RunUnitState.current_hp` — during combat this is pre-combat HP (live HP is on `Unit` nodes). Acceptable for M37; revisit if live HP display is needed. |
| 8 | HUD opens its own viewer instances directly — no signal relay through CombatScene. |
| 9 | `CombatManager._process()` guard: `if _hud == null or _targeting == null: return` to silence pre-`setup()` error spam. |
| 10 | `_smoke_test()` 60-second safety timer: `get_tree().quit(1)` if smoke hasn't finished, to prevent infinite hangs on future errors. |

---

## Files Changed

| File | Change |
|---|---|
| `ui/deck_viewer.gd` | NEW |
| `ui/squad_viewer.gd` | NEW |
| `ui/map_screen.gd` | Deck + Squad buttons in top_row; handlers; `_refresh()` updates deck text |
| `ui/hud.gd` | `_deck_label` → `_deck_btn`; Squad button in top_right column; handlers |
| `autoloads/features.gd` | `deck_viewer_enabled`, `squad_viewer_enabled` |
| `systems/combat_manager.gd` | `_process()` null guard for `_hud`/`_targeting` |
| `world/combat_scene.gd` | `_m37_smoke()`; 60s safety quit timer in `_smoke_test()` |
| `PROGRESS.md` | Updated header + M37 entry |

---

## Smoke Results

```
[smoke] -- M37 deck viewer + squad viewer --
  deck_viewer_in_tree=true (expect true)
  squad_viewer_world_in_tree=true (expect true)
  squad_viewer_combat_in_tree=true (expect true)
  deck_viewer_enabled=true (expect true)
  squad_viewer_enabled=true (expect true)
```

All checks pass. Full smoke (M3–M37) completes without new errors.
