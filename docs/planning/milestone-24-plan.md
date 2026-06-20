# M24 — Debug Sandbox Overlay

## Context

A toggleable debug overlay on top of `combat_scene` for rapid content authoring and synergy
testing. Core constraint: every action routes through the **same production entry points** a real
run uses — no parallel state-mutation paths.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Overlay is a CanvasLayer** added as a child of `combat_scene` in `_ready()`, gated by `Features.sandbox_enabled`. Toggle with `` ` `` (`KEY_QUOTELEFT`). |
| 2 | **Godot Button/Label/VBoxContainer nodes** for the panel UI — not code-drawn. Functional dev tool; visual polish is out of scope. |
| 3 | **Public `debug_*` methods on CombatManager** for every action — no direct private-field access from the overlay. Keeps the "no new mutation paths" rule by adding thin wrappers over existing private logic. |
| 4 | **`DirAccess` at runtime** scans `data/units/`, `data/cards/`, `data/artifacts/resources/` at setup. All lists are sorted alphabetically by display name. |
| 5 | **Two-step spawn**: selecting a unit + [As Player]/[As Enemy] arms a `_pending_spawn` flag; the next left-click on the world resolves the voxel column. `accept_event()` blocks the click from reaching `CombatManager`. World coordinates derived via `get_viewport().canvas_transform.affine_inverse() * event.position` — the standard pattern for CanvasLayer input. |
| 6 | **`debug_invulnerable` on `Unit`** checked at the top of `take_damage()`. **`debug_enemies_passive` on CombatManager** checked per-enemy in `_run_enemy_turn()`. Both are simple bool fields; no feature flag needed. |
| 7 | **No smoke test** — dev tool only; verified manually per the checklist below. |

---

## Files changed

| File | Change |
|---|---|
| `autoloads/features.gd` | `sandbox_enabled: bool = true` |
| `systems/combat_manager.gd` | `debug_enemies_passive` field; passivity check in `_run_enemy_turn()`; all `debug_*` public methods |
| `units/unit.gd` | `debug_invulnerable` field; guard at top of `take_damage()` |
| `world/combat_scene.gd` | Instantiate overlay in `_ready()` (gated by feature flag and not smoke env) |
| `debug/sandbox_overlay.gd` | NEW — CanvasLayer overlay with spawn/card/artifact/cheats/isolation panels |
| `docs/planning/milestone-24-plan.md` | This file |
| `PROGRESS.md` | M24 entry |

---

## CombatManager public API added

```gdscript
var debug_enemies_passive : bool = false

func debug_spawn(def: UnitDefinition, col: int, unit_name: String, is_player: bool) -> Unit
func debug_inject_card_to_hand(def: CardDefinition) -> void
func debug_inject_card_to_deck(def: CardDefinition) -> void
func debug_inject_artifact(def: ArtifactDef) -> void
func debug_refill_ap() -> void
func debug_force_next_wave() -> void
```

---

## Manual verification checklist

1. Launch game → combat scene → press `` ` `` → debug panel appears on right side.
2. **Spawn (player):** Select a unit from list → [As Player] → click terrain → unit appears, joins `player_units`.
3. **Spawn (enemy):** Same with [As Enemy] → unit joins `enemy_units`; fires during enemy turn.
4. **Card injection:** Select a card → [→ Hand] → card appears in hand HUD immediately.
5. **Artifact injection:** Select an artifact → [Activate] → artifact fires `on_combat_start` hook.
6. **Refill AP:** Click during player turn → AP bar refills.
7. **End Player Turn:** Click → enemy turn starts.
8. **Force Wave:** Click → next reinforcement wave spawns.
9. **Player Invulnerable (ON):** Toggle → button turns green → player units take 0 damage.
10. **Enemies Passive (ON):** Toggle → button turns green → enemies skip firing.
11. Press `` ` `` again → panel hides; game input resumes normally.
12. `Features.sandbox_enabled = false` → overlay never added; zero cost in production.

---

## Seams for later

- Terrain regeneration (seed field + [Regenerate] button)
- Scenario save/load (capture live state to `.tres`)
- Full unit inspector (click any unit → show all stats + essences)
- Headless scenario regression runner
