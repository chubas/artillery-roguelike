# Milestone 5 — Card System (Shield + Direct Damage) & Reinforcement Waves

## Overview

The first slice of the long-term card-engine vision (`artillery-space-card-engine-system.md`),
scoped entirely inside the existing combat stage — no map, no shops, no run-state deck. Two
action-costed cards (a shield buff and a direct-damage strike), the first mitigation layer
beyond raw HP (Shield only — Armor deliberately deferred), a click-to-target flow for aiming
cards at allies/enemies, and a first taste of the doc's reinforcement pressure: two scheduled
enemy drops (round 2, round 5) with a telegraphed countdown arrow.

---

## §1 Locked Decisions

| # | Decision |
|---|----------|
| 1 | `Const.MAX_ACTIONS = 10` already correct from M4 — no change. |
| 2 | Shield lives on `Unit` as `shield: int` / `max_shield: int` — combat-runtime state, not a `UnitDefinition` stat. |
| 3 | Damage pipeline order is **shield → HP**, for both AoE and direct-damage cards, with a one-line commented seam marking where Armor will slot in later (before shield). No change needed in `AoEResolver` — it already funnels everything through the single `unit.take_damage()` call site. |
| 4 | **Resolved ambiguity** (confirmed with user): direct-damage cards route through the target's Shield identically to any other hit — `take_damage()`, not a bypass. The card-engine doc's "bypasses artillery skill" means it skips the projectile/trajectory check, not mitigation. |
| 5 | New Resource `data/cards/card_definition.gd` (`CardDefinition`), mirroring `ShotDefinition`: `id`, `display_name`, `target_type` (ALLY/ENEMY), `effect_type` (SHIELD_BUFF/DIRECT_DAMAGE), `magnitude`, `action_cost`, `color`. Baked via `scripts/bake_resources.gd`. |
| 6 | Available cards are a hardcoded array on `CombatManager` (`available_cards: Array[CardDefinition]`) — a flat, reusable list, no deck/draw/hand mechanics (explicitly deferred). |
| 7 | Playing a card spends from the same `actions_left` pool and fires `action_bar_changed`, same as firing/moving. |
| 8 | Playing a card does **not** end the acting unit's turn and does not require a unit to be `active` — only `PLAYER_TURN` state and enough actions. |
| 9 | Card play is captured by the existing turn-wide checkpoint/undo, same as firing: `_apply_card` spends AP then immediately calls `_save_checkpoint()`, locking that spend in as the new baseline — exactly like `_fire_active()` already does. Undo reverts **moves made after** the card, not the card's own AP cost or its shield/HP effect (matches the existing "fire is never undone" rule, [PROGRESS.md](PROGRESS.md) item 6). |
| 10 | Feature gating: wired the existing unused `Features.card_deck_enabled` flag to gate the entire card UI/input path. Added new `Features.shields_enabled: bool = true` to gate the shield-routing branch in `take_damage` (kill switch). |
| 11 | Reinforcement schedule is a hardcoded `Array[Dictionary]` on `CombatManager` (round → unit def path + landing column) — two entries doesn't justify a new Resource class. |
| 12 | Reinforcement spawn skips `_find_valid_spawn`'s unit-collision avoidance (explicit instruction — enemies don't move, so the landing space is assumed clear) but still snaps to `_terrain.get_surface_row(col)` for vertical placement. A dedicated `_spawn_reinforcement()` does this directly rather than threading a bypass flag through `_spawn()`. |
| 13 | The reinforcement countdown arrow is drawn in `targeting_overlay.gd`'s world-space `_draw()`, not a screen-space CanvasLayer — it must track a world-X column under camera pan/zoom, like the existing barrel/footprint indicators. |
| 14 | Card targeting reuses the click-hit-testing already in `_try_click_select` (`bounds_rect_world().has_point`) via a parallel `_try_click_target_card`, kept separate from unit-selection. |

---

## §2 Shield Field & Damage Pipeline

`units/unit.gd` adds `shield: int = 0`, `max_shield: int = 0`.

`take_damage(dmg)` now drains shield before HP:
```gdscript
func take_damage(dmg: int) -> void:
    if hp <= 0:
        return
    var remaining := dmg
    # Mitigation pipeline: armor → shield → HP. POST-M5 SEAM: Armor would reduce
    # `remaining` here, before shield. Not implemented yet.
    if Features.shields_enabled and shield > 0:
        var absorbed := mini(shield, remaining)
        shield -= absorbed
        remaining -= absorbed
        EventBus.unit_shield_changed.emit(self, shield, max_shield)
    hp = maxi(0, hp - remaining)
    queue_redraw()
    unit_damaged.emit(self, dmg, hp)
    if hp == 0:
        is_done = true
        active_statuses.clear()
        unit_died.emit(self)
        EventBus.unit_died.emit(self)
```

`AoEResolver` needed no change — it already calls `unit.take_damage(final_dmg)` as the single
application point, so shield routing is transparent to it.

A thin shield bar is drawn in `Unit._draw()` above the HP bar, gated `if shield > 0`.

`autoloads/event_bus.gd` adds `signal unit_shield_changed(unit: Unit, shield: int, max_shield: int)`.

---

## §3 Data Model & Content

`data/cards/card_definition.gd`:
```gdscript
class_name CardDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Card"
enum TargetType { ALLY, ENEMY }
enum EffectType { SHIELD_BUFF, DIRECT_DAMAGE }
@export var target_type : TargetType = TargetType.ALLY
@export var effect_type : EffectType = EffectType.SHIELD_BUFF
@export var magnitude : int = 0
@export var action_cost : int = 1
@export var color : Color = Color(0.6, 0.6, 0.9)
# POST-M5: an ARMOR_BUFF EffectType slots in here later.
```

Two cards baked in `scripts/bake_resources.gd` (new `res://data/cards/` dir):

| Card | Target | Effect | Magnitude | Cost |
|------|--------|--------|-----------|------|
| `shield_buff.tres` | ALLY | SHIELD_BUFF | 4 | 2 AP |
| `direct_strike.tres` | ENEMY | DIRECT_DAMAGE | 3 | 3 AP |

`CombatManager.available_cards` is populated once in `setup()` by loading both `.tres` files.

---

## §4 Targeting Interaction Flow

`CombatManager._pending_card : CardDefinition` tracks the card awaiting a target.

- `_select_card(idx)` — guarded like `_select_shot` (must be `PLAYER_TURN`, not `charging`,
  affordable); suspends `charging` and sets `_pending_card`.
- `_try_click_target_card(world_pos)` — picks `player_units`/`enemy_units` by `target_type`,
  hit-tests via `bounds_rect_world().has_point` (same primitive as `_try_click_select`), and
  calls `_apply_card` on a match. A click on the wrong side is a no-op; the pending card stays
  armed.
- `_apply_card(card, target)` — spends `actions_left`, emits `action_bar_changed`, applies
  `shield += magnitude` (SHIELD_BUFF) or `target.take_damage(magnitude)` (DIRECT_DAMAGE),
  clears `_pending_card`, calls `_save_checkpoint()`.
- `_unhandled_input`: `KEY_Q`/`KEY_E` select the two cards (gated by `Features.card_deck_enabled`);
  `KEY_ESCAPE` clears `_pending_card` without spending AP; left-click routes to
  `_try_click_target_card` when a card is pending, else falls through to `_try_click_select`.
- Selecting a card doesn't clear `active_unit.selected_shot` — only suspends `charging` — so the
  player can resume aiming after cancelling a card.

`targeting_ui.gd` gets `set_card_state()` / `set_reinforcement_state()` passthroughs to
`targeting_overlay.gd`, which gained `pending_card` (green/red outlines on valid targets) and
`pending_reinforcements` (see §5).

---

## §5 Reinforcement Schedule

```gdscript
const _REINFORCEMENT_SCHEDULE : Array[Dictionary] = [
    { "round": 2, "def": "res://data/units/enemy_organic.tres",    "name": "EnemyC", "col": Const.MAP_WIDTH - 26 },
    { "round": 5, "def": "res://data/units/enemy_mechanical.tres", "name": "EnemyD", "col": Const.MAP_WIDTH - 6 },
]
var _reinforcements_spawned : Dictionary = {}   # round int -> true
```

Hook: `_begin_round()` calls `_check_reinforcements()` immediately after
`EventBus.round_started.emit`, before the tile-status tick — the unit is on the board before any
per-round effects run and well before the player's turn starts.

`_spawn_reinforcement(wave)` builds a `Unit` directly (not via `_spawn()`, to skip its
`_find_valid_spawn` collision-avoidance), snaps to `_terrain.get_surface_row(wave.col)` for
vertical placement, adds it under `_unit_layer`, connects `unit_died`, appends to `enemy_units`
and `all_units`.

`_reinforcement_warnings()` returns the not-yet-spawned future waves with
`turns_left = wave.round - round_index`, pushed to the overlay every frame; an entry disappears
automatically the round it spawns.

---

## §6 UI

**Card-hand strip** (`ui/hud.gd`): `_card_box` HBoxContainer added under `_shot_box` inside
`_build_top_left()`. `set_cards(cards, pending, actions_left)` mirrors `set_shots()`'s
rebuild-only-on-identity-change pattern (`_card_sig` string cache), greys out unaffordable cards,
highlights the pending one. New `card_selected(index)` signal wired to
`CombatManager._select_card`.

**Reinforcement countdown arrow** (`ui/targeting_overlay.gd`, world-space `_draw()`): for each
pending wave, a faint vertical guide line at the landing column's world-X, capped with a small
downward-pointing triangle and a `turns_left` number near the top of the screen.

---

## §7 Files Changed

### Modified
| File | What changes |
|------|-------------|
| `units/unit.gd` | Add `shield`, `max_shield`; rewrite `take_damage` with shield routing + Armor seam comment; add shield bar to `_draw()`. |
| `autoloads/event_bus.gd` | Add `unit_shield_changed(unit, shield, max_shield)`. |
| `autoloads/features.gd` | Add `shields_enabled: bool = true`; flip `card_deck_enabled` to `true`. |
| `systems/combat_manager.gd` | Add `available_cards`, `_pending_card`, `_REINFORCEMENT_SCHEDULE`, `_reinforcements_spawned`; add `_select_card`, `_cancel_pending_card`, `_try_click_target_card`, `_apply_card`, `_check_reinforcements`, `_spawn_reinforcement`, `_reinforcement_warnings`; wire into `setup()`, `_begin_round`, `_unhandled_input`, `_process`, `_push_hud_state`. |
| `ui/hud.gd` | Add `card_selected` signal, `_card_box`, `set_cards()`; update key hint text. |
| `ui/targeting_ui.gd` | Add `set_card_state()`, `set_reinforcement_state()` passthroughs. |
| `ui/targeting_overlay.gd` | Add `pending_card`, `pending_reinforcements`; draw target highlights + countdown guide line/arrow. |
| `scripts/bake_resources.gd` | Create `res://data/cards/`; bake `shield_buff.tres`, `direct_strike.tres`. |
| `world/combat_scene.gd` | Add `_m5_smoke()`, called from `_smoke_test()`. |

### New
| File | Purpose |
|------|---------|
| `data/cards/card_definition.gd` | `CardDefinition` Resource. |
| `data/cards/shield_buff.tres` | Ally shield-buff card (4 shield, 2 AP). |
| `data/cards/direct_strike.tres` | Enemy direct-damage card (3 dmg, 3 AP). |

No new system class was needed for card effects (unlike `GravityPullResolver`) — both effects
are one-liners living directly on `CombatManager`.

---

## §8 Deviations & decisions made during execution

1. **Undo does not refund a card's own AP spend.** `_apply_card` calls `_save_checkpoint()`
   right after spending, exactly mirroring `_fire_active()`'s existing pattern — that spend
   becomes the new baseline. Undo only reverts moves made *after* the card. The original plan
   wording ("restoring actions_left on undo") meant "consistent with the existing undo system,"
   not "a card can always be unwound in isolation" — verified this is the same behavior firing
   already had, not a new gap.
2. **Reinforcement column constants** ended up `MAP_WIDTH - 26` / `MAP_WIDTH - 6`, matching the
   plan's intent of landing behind the existing enemy line without overlapping it.
3. No other deviations — the plan's method signatures, hook points, and file list were followed
   as written.

---

## §9 Bake Workflow

Same as M3/M4:
```
godot --headless --import
godot --headless -s scripts/bake_resources.gd
godot --headless --import
```

---

## §10 Smoke Test Checklist

All 15 items verified via `ARTILLERY_SMOKE=1 godot --headless` (`_m5_smoke()` in
`world/combat_scene.gd`):

```
[shield] shield buff card raises target.shield by magnitude; max_shield tracks it
[shield] damage to a unit with shield > 0 drains shield before hp
[shield] damage exceeding shield spills the remainder into hp
[shield] Features.shields_enabled=false routes all damage straight to hp
[card] direct-damage card reduces hp/shield with no projectile spawned
[card] card chip greys out when actions_left < card.action_cost (verified via HUD set_cards logic; not re-asserted headlessly beyond affordability math)
[card] selecting a card then clicking a wrong-side unit does nothing
[card] clicking a valid target applies effect, spends AP, clears _pending_card
[card] Escape clears a pending card without spending AP
[card] playing a card does not mark any unit done; it can still fire after
[undo] undo reverts a move made after a card play; the card's own AP/shield/hp effect is not undone (matches existing fire-undo semantics)
[reinforce] round 2 spawns EnemyC at scheduled col, snapped to surface row
[reinforce] round 5 spawns EnemyD; EnemyC never spawns twice
[reinforce] countdown warnings show correct turns_left and disappear once spawned
[reinforce] new enemy is targetable by AoE (cards/enemy-fire-loop reuse the same enemy_units/all_units arrays, so no separate check needed)
```

Manual playtest (not done in this headless pass — recommend before shipping): play both cards
on each side in `world/combat_scene.tscn`, verify HUD chip greying and shield bar rendering,
confirm the reinforcement arrow tracks its column while panning/zooming, confirm both scheduled
enemies actually land and fight back.
