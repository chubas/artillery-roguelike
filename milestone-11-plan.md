# Milestone 11 — Card Deck (draw / hand / discard)

## What was built

The card system went from two always-present cards (each once per turn) to a real deck: a
shuffled draw pile, a 5-card hand drawn fresh each turn, and a discard pile. Three new card
effects were added, and a HUD indicator shows draw-pile / discard counts.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Fresh hand each turn.** `_start_player_turn()` calls `_draw_hand()`, which discards the unplayed hand and draws `HAND_SIZE = 5`. |
| 2 | **Reshuffle mid-draw.** If the draw pile empties while drawing, `_reshuffle_discard()` shuffles the discard into a new draw pile and drawing continues — so a short deck still yields a full hand. |
| 3 | **AP is the only play limit.** The once-per-turn-per-card rule (`_used_cards`) is removed; you can play any hand card you can afford. |
| 4 | **Starting deck = 11 cards:** Direct Strike ×3, Shield ×3, Mine ×2, Boosted ×2, Halve Wind ×1 (`_DECK_LIST`). |
| 5 | Card play stays **non-undoable** (it re-checkpoints), so deck state needs no undo snapshot. Reuses the existing `card_deck_enabled` Features gate. |

---

## Data — `data/cards/card_definition.gd`

```gdscript
enum TargetType { ALLY, ENEMY, TILE, NONE }   # + TILE (mine), NONE (instant)
enum EffectType { SHIELD_BUFF, DIRECT_DAMAGE, ADD_BOOSTED, DEPLOY_MINE, HALVE_WIND }
```
`magnitude` is reused as Boosted stacks for ADD_BOOSTED.

New baked cards (`scripts/bake_resources.gd`):
- `boosted_card.tres` "Overdrive" — ADD_BOOSTED, ALLY, magnitude 2, cost 2.
- `mine_card.tres` "Drop Mine" — DEPLOY_MINE, TILE, cost 2.
- `halve_wind.tres` "Calm Winds" — HALVE_WIND, NONE, cost 1.
(Costs are first-pass; tunable.)

---

## Deck & play — `systems/combat_manager.gd`

- State: `const HAND_SIZE := 5`, `const _DECK_LIST`, `var _deck/_hand/_discard : Array[CardDefinition]`.
- `_build_deck()` (called in `setup()`): expand `_DECK_LIST` paths × counts, `shuffle()`.
- `_draw_hand()` / `_reshuffle_discard()`: see decisions 1–2; called from `_start_player_turn()`.
- `_select_card(idx)`: indexes `_hand`; a NONE card resolves immediately, others set `_pending_card`.
- `_try_click_target_card(world_pos)`: ALLY/ENEMY → unit bbox pick (existing); TILE → column from
  `Const.world_to_voxel`, deploy if the column has a surface.
- `_apply_card(card, target, vox)` dispatcher: SHIELD_BUFF / DIRECT_DAMAGE (existing) +
  ADD_BOOSTED (`UnitStatusSystem.apply(target, boosted.tres, magnitude)`), DEPLOY_MINE
  (`_deploy_mine_at(vox.x)`), HALVE_WIND (`_halve_wind()`). After applying, the card moves from
  `_hand` to `_discard`.
- `_deploy_mine_at(col)`: mirrors the mine branch of `_spawn_deployables` (Mine + `diamond_mine.tres`,
  snap to surface, add to `_deployable_layer_back`, append to `deployables`).
- `_halve_wind()`: `wind_strength *= 0.5`; update `_projectiles.current_wind_force`; emit
  `EventBus.wind_changed`.

---

## UI

- `ui/targeting_overlay.gd`: `_draw_card_targets` branches to `_draw_tile_target()` for TILE cards —
  a column guide + a surface-cell marker at the mouse column.
- `ui/hud.gd`: `set_cards(hand, pending, actions_left, deck_count, discard_count)` (dropped `used`);
  a `_deck_label` shows `Deck N · Discard M`. `CardChip` lost its `_used` spent/slash visuals.

---

## Files changed

| File | Change |
|---|---|
| `data/cards/card_definition.gd` | TargetType += TILE, NONE; EffectType += ADD_BOOSTED, DEPLOY_MINE, HALVE_WIND |
| `systems/combat_manager.gd` | deck/hand/discard piles, `_DECK_LIST`/`HAND_SIZE`, `_build_deck`/`_draw_hand`/`_reshuffle_discard`; `_draw_hand` in `_start_player_turn`; card play rework + `_deploy_mine_at`/`_halve_wind`; removed `available_cards`/`_used_cards` |
| `ui/targeting_overlay.gd` | TILE-target column highlight |
| `ui/hud.gd` | `set_cards` signature + deck label; CardChip `_used` removal |
| `scripts/bake_resources.gd` | bake `boosted_card.tres`, `mine_card.tres`, `halve_wind.tres` |
| `world/combat_scene.gd` | `_m11_smoke()`; M5 card smoke updated to the deck model (3-arg `_apply_card`, artifacts isolated for the AP-cost asserts) |

---

## Smoke checklist (all pass)

- Deck builds to 11; first `_draw_hand()` → hand 5, deck 6, discard 0; invariant
  `deck + hand + discard == 11`.
- Reshuffle: with deck 2 / discard 9, `_draw_hand()` draws a full 5 (drawing 2, reshuffling, then
  3 more); discard emptied; invariant holds.
- Overdrive → ally gains 2 Boosted stacks. Drop Mine → `deployables` +1, new one `is Mine`.
  Calm Winds → `wind_strength` 0.8 → 0.40 and `current_wind_force` follows.
- `ARTILLERY_SMOKE=1 godot --headless` — all M4–M11 checklists pass, no ERROR lines.

## Note: pre-existing M5 test drift fixed

Adding the M9 "Free First Card" artifact to the live loadout had been silently zeroing the M5
smoke's first card-cost assertion (AP spent 0 vs expected 2). M5 now temporarily empties
`combat.artifacts` around its raw card-cost checks so it tests base mechanics, restoring the
loadout afterward.
