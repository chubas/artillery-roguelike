# Milestone 15 — Pre-Combat Placement

## What was built

A placement phase before each fight: the player positions the non-disabled squad within the
stage's spawn zone, then confirms to begin combat (run-state spec §8). The zone is a per-stage
property defaulting to the left half of the map; placement reuses the combat scene's terrain/unit
rendering as a new game state, not a separate scene.

Also fixed a reported bug: selecting a card highlighted every copy of that card type.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | Spawn zone is a **per-stage** column band (`spawn_min_col`/`spawn_max_col`), default **left half** (`0 .. MAP_WIDTH/2-1`). Column-range only for now; richer zones await terrain variability. |
| 2 | Placement is a **`GameState.PLACEMENT`** inside the combat scene, not a separate scene — reuses terrain/units/camera. |
| 3 | Click-to-place: click a unit to select, click a spot to move it; invalid spots (out-of-zone clamp / blocked / overlap) are rejected, no partial move. |
| 4 | Card-selection highlight keys off the hand **index**, not the `CardDefinition` (duplicates share one cached instance). |

---

## Changes

- `data/stages/stage_descriptor.gd` — `spawn_min_col` / `spawn_max_col`; baked left-half on
  stages 01–03 (`scripts/bake_resources.gd`).
- `systems/combat_manager.gd` — `PLACEMENT` added to `GameState`; `setup()` ends in
  `_start_placement()`; `_confirm_placement()` → `_begin_round()` (wired to `start_battle_pressed`);
  `_place_player_squad` spreads the squad across the zone; `_spawn_min_col`/`_spawn_max_col`;
  `_placement_place(unit, col)` (clamp into zone, snap to surface, validate via
  `UnitMovement.bbox_terrain_clear` + `overlaps_any_unit`); `_placement_input` branch in
  `_unhandled_input`; placement HUD + overlay push in `_push_hud_state` / `_process`.
- `ui/hud.gd` — `start_battle_pressed` signal; `_build_placement()` (instruction + Start Battle,
  bottom-center); `set_placement_mode(active)`; turn text "DEPLOY SQUAD".
- `ui/targeting_ui.gd` + `ui/targeting_overlay.gd` — `set_placement_state(active, min, max)`;
  `_draw_spawn_zone()` translucent band.
- `world/combat_scene.gd` — `combat._confirm_placement()` in smoke mode before `_smoke_test`;
  `_m15_smoke()`.
- **Card bug fix:** `CombatManager._pending_index` (set in `_select_card`, cleared in
  `_cancel_pending_card`/`_apply_card`); `HUD.set_cards(..., pending_index)` highlights `i == pending_index`.

---

## Verification

- **Bake:** `--import` → `-s scripts/bake_resources.gd` → `--import` (stages gain the zone fields).
- **`_m15_smoke()`** (re-enters PLACEMENT against the live combat): stage_01 zone = `0..59`;
  scanning the zone finds a valid column the unit moves to; a right-half click (col 115) keeps the
  unit `<= spawn_max` (never leaves the zone); `_confirm_placement()` leaves PLACEMENT and advances
  the round.
- **Regression:** `ARTILLERY_SMOKE=1 godot --headless` — 45 milestone headers (M4–M15), all
  spot-checks pass, 0 ERROR lines, no leaked instances. Non-smoke launch boots to the map.
- **Manual:** map → Enter Stage → squad in a highlighted left-half band, "DEPLOY SQUAD"; click a
  unit then a spot to reposition (right half rejected); Start Battle → combat begins; positions hold.

---

## Seams for later

- **Moderate-information model (spec §8):** enemy HP is still shown during placement; hiding exact
  HP at placement is a deferred UI refinement.
- **REACH_ZONE/HOLD_ZONE objectives (M-future):** the spawn zone is the first "zone region" on a
  stage; objective zones can follow the same column-range shape.
- **Richer zones:** column-range only; arbitrary regions arrive with terrain variability.
