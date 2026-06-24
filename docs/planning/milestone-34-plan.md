# Milestone 34 — Shop Node + AP Rebalance + Rarity

## Goal

Introduce a SHOP node type on the run map where players spend Shards to buy cards, artifacts, and units between combats. Artifact cycling (no repeat until all pool entries offered) is shared between reward screens and shop visits. Re-roll button refreshes the offer at escalating cost. Starting shards increased to 25; each cleared combat rewards 20.

Also includes: AP rebalance (10→5 base), all card costs tuned to 1 AP (Halve Wind 0 AP, Direct Strike damage 2), and a `Rarity` metadata tag on all content types.

---

## Key decisions (locked)

| # | Decision |
|---|---|
| 1 | Diamond nodes 3 and 5 (outer paths at layer 2) become SHOP; node 4 stays COMBAT. Players can take center path (node 4) to skip shops. |
| 2 | `RunState.artifact_seen_set: Array[String]` tracks artifacts offered this cycle (rewards + shop). Resets when pool exhausted. Serialized. |
| 3 | `Run.pick_artifacts_for_offer(n)` — single helper used by both reward screen and shop. Marks seen_set; resets cycle when pool size < n. Uses `run_rng`. |
| 4 | `RunController._on_node_selected()` dispatcher replaces direct `_enter_combat` connection. Checks `node.type == SHOP` and `Features.shop_enabled`. |
| 5 | Shop offers: 5 cards (no intra-offer repeats), 3 artifacts (seen_set cycling), 1 unit (repeats OK). Re-roll resamples cards and unit freely; artifacts still cycle. |
| 6 | Re-roll cost: 5◆ base, +5◆ each subsequent roll. Resets per shop visit (UI state, not serialized). |
| 7 | Prices: CARD=10◆, ARTIFACT=15◆, UNIT=20◆. Bought items stay bought within the visit (button disabled). |
| 8 | Combat clear: +20 shards in `_on_combat_exited()` before starting reward sequence. |
| 9 | Starting shards: 25 (was 10). |
| 10 | `Features.shop_enabled` kill switch — when false, shop nodes appear on map but clicking one falls through to `_enter_combat`. |
| 11 | `MapNode.stage()` guards against empty `stage_path` (returns null) so shop nodes don't cause a load-path error. |

---

## Files changed

| File | Change |
|---|---|
| `state/run_state.gd` | Added `artifact_seen_set: Array[String]`; updated `to_dict()/from_dict()` |
| `autoloads/run.gd` | `pick_artifacts_for_offer()`; `_assign_terrain_variations()` skips non-COMBAT; starting shards 25 |
| `state/map_node.gd` | `stage()` null-guard on empty `stage_path` |
| `state/map_state.gd` | `build_diamond()` sets nodes 3, 5 to `Type.SHOP` with empty `stage_path` |
| `ui/map_screen.gd` | `_draw_node()` purple fill + "SHOP" label; `_refresh()` shows shop detail text |
| `world/run_controller.gd` | `_on_node_selected()` dispatcher; `_enter_shop()`/`_on_shop_closed()`; +20 shards on clear; artifact reward via `Run.pick_artifacts_for_offer(3)` |
| `ui/shop_screen.gd` | NEW — CanvasLayer shop UI: 3-column layout (cards/artifacts/units), buy buttons, re-roll, leave |
| `debug/sandbox_overlay.gd` | Give Shards control (LineEdit + button) in CHEATS section |
| `autoloads/features.gd` | `shop_enabled: bool = true` |
| `world/combat_scene.gd` | `_m34_smoke()` + smoke expected values updated for 25-shard baseline |

---

## Smoke results (2026-06-24)

```
[smoke] -- M34 shop node --
  shop_nodes=2 (expect 2)
  offered=3 seen_set=3 (expect 3, 3)
  after drain: seen_set_reset=true (expect true)
  start_shards=25 (expect 25)
```

All M1–M33 checks pass (M21/M27 expected values updated to 25-shard baseline).

---

---

## AP Rebalance (added to M34)

### Key decisions (locked)

| # | Decision |
|---|---|
| AP-1 | `Const.MAX_ACTIONS` 10 → 5. Forces real turn tension: 2 moves + 1 card + 1 shot = full turn. |
| AP-2 | All card `action_cost` → 1. Halve Wind → 0. Direct Strike magnitude 3 → 2. |
| AP-3 | Elemental shot costs (fire=2, electric=3) unchanged — they're shots, not cards, and stay at 2–3 AP per design. |
| AP-4 | Movement stays at 1 AP per tile (unchanged). |

### Files changed

| File | Change |
|---|---|
| `constants.gd` | `MAX_ACTIONS` 10 → 5 |
| `scripts/bake_resources.gd` | All card costs → 1; Halve Wind → 0; Direct Strike magnitude → 2 |
| `world/combat_scene.gd` | Updated expected values in M4/M20 smoke tests |
| `ui/hud.gd` | Updated stale pip comment |

---

## Rarity (added to M34)

### Key decisions (locked)

| # | Decision |
|---|---|
| R-1 | `Rarity` class in `data/rarity.gd` — string constants: BASIC, COMMON, RARE, EPIC, LEGENDARY, BOSS, EVENT. Mirrors Faction pattern. |
| R-2 | `@export var rarity: String` added to `CardDefinition`, `UnitDefinition`, `ArtifactDef`. Default `Rarity.COMMON`. |
| R-3 | Direct Strike and Shield Up → `Rarity.BASIC`. All other current content → `Rarity.COMMON`. |
| R-4 | No gameplay effect yet — metadata tag only. Future: loot weighting, visual badge, shop price tier. |

### Files changed

| File | Change |
|---|---|
| `data/rarity.gd` | NEW — Rarity class with string constants + `display_name()` |
| `data/cards/card_definition.gd` | `rarity` field |
| `data/units/unit_definition.gd` | `rarity` field |
| `data/artifact_def.gd` | `rarity` field |
| `scripts/bake_resources.gd` | Rarity assignments on all content; `_bake_artifact()` gets optional rarity param; `_save_player_unit()` sets COMMON |

---

## Out of scope

- Shop node chest icon (color + "SHOP" label only)
- Artifact descriptions in shop (name only, consistent with reward screen)
- Shop shard display syncing with HUD in real time
- Persistence of "sold out" state if player leaves and re-enters same shop (resamples on each visit)
- Act-gated shop inventory
- Rarity visual badge in HUD/reward/shop (tag only for now)
