# Milestone 35 — Special Event Nodes + Extended Map

## Goal

Add out-of-combat event nodes to the run map and expand the map from 9 nodes (1,2,3,2,1) to 15 nodes (1,2,3,3,3,2,1). Two events provide healing and shard-economy decisions. Map generation guarantees at least 2 shops at different layers and 2 events.

---

## Key decisions (locked)

| # | Decision |
|---|---|
| 1 | 15-node map layout (1,2,3,3,3,2,1): `build_run_map(stage_paths, event_paths)` in `MapState`. `build_diamond()` and `build_linear()` preserved unchanged for smoke/regression. |
| 2 | Fixed type assignments: L2 node 3 = EVENT(triage), L3 node 7 = SHOP, L4 node 10 = EVENT(blood_price), L5 node 12 = SHOP. All other nodes COMBAT. |
| 3 | `EventDef` base class (`data/event_def.gd`) — `Resource` subclass with `choices(rs)` and `resolve(idx, rs)` virtuals. Specific events are GDScript subclasses baked as `.tres`. Follows the ArtifactDef pattern. |
| 4 | EventScreen is text-only for now (no portraits, no animations). Choice buttons are disabled when `available: false`. |
| 5 | Events resolve immediately against `RunState` — no combat involvement. |
| 6 | `act_tags: Array[String] = ["act_1"]` added to both `EventDef` and `StageDescriptor` as metadata only. No gameplay effect. |
| 7 | `_assign_terrain_variations()` already skips non-COMBAT nodes — no change needed. |
| 8 | `MapNode.event_path: String = ""` mirrors `stage_path`. `event() -> EventDef` loads from path (returns null if empty). |

---

## Event designs

### Field Triage (node 3, L2)

> "Your medic scavenges supplies. Choose how to use them."

- **Choice A:** "Restore [unit] to full HP" — targets the dead unit (or most missing-HP alive unit). Revives disabled units (`is_disabled = false`). Unavailable if no unit needs healing.
- **Choice B:** "Restore 2 HP to all units" — always available. Clamps to `max_hp`.

### Blood Price (node 10, L4)

> "A black market contact offers a deal. The price is steep."

- **Choice A:** "Take 10 ◆ for free" — always available.
- **Choice B:** "Sacrifice 3 HP from [unit] ([hp] HP) for 20 ◆" — targets the highest-current-HP alive unit. Unavailable if that unit's HP ≤ 3.

---

## 15-node map structure

```
L0: [0]           → COMBAT (start)
L1: [1, 2]        → COMBAT, COMBAT
L2: [3, 4, 5]     → EVENT(triage), COMBAT, COMBAT
L3: [6, 7, 8]     → COMBAT, SHOP, COMBAT
L4: [9, 10, 11]   → COMBAT, EVENT(blood_price), COMBAT
L5: [12, 13]      → SHOP, COMBAT
L6: [14]          → COMBAT (final)
```

Edges:
```
0:[1,2]   1:[3,4]   2:[4,5]
3:[6,7]   4:[6,7,8] 5:[7,8]
6:[9,10]  7:[9,10,11] 8:[10,11]
9:[12]    10:[12,13] 11:[13]
12:[14]   13:[14]   14:[]
```

Shops at L3 (node 7) and L5 (node 12) — guaranteed different layers. ✅  
Events at L2 (node 3) and L4 (node 10). ✅

---

## Files changed

| File | Change |
|---|---|
| `data/event_def.gd` | NEW — base class |
| `data/events/scripts/event_triage.gd` | NEW — Field Triage |
| `data/events/scripts/event_blood_price.gd` | NEW — Blood Price |
| `data/events/resources/event_triage.tres` | NEW — baked resource |
| `data/events/resources/event_blood_price.tres` | NEW — baked resource |
| `state/map_node.gd` | `event_path` field + `event()` method + serialization |
| `state/map_state.gd` | `build_run_map()` (15-node) |
| `autoloads/run.gd` | `_EVENT_PATHS` const; `start_default_run()` → `build_run_map()` |
| `autoloads/features.gd` | `events_enabled: bool = true` |
| `world/run_controller.gd` | `_enter_event()`, `_on_event_completed()`, dispatch in `_on_node_selected()` |
| `ui/event_screen.gd` | NEW — CanvasLayer event UI |
| `ui/map_screen.gd` | EVENT node teal color + "EVENT" label + detail text |
| `data/stages/stage_descriptor.gd` | `act_tags: Array[String] = ["act_1"]` |
| `scripts/bake_resources.gd` | Stage `act_tags` + event baking |
| `world/combat_scene.gd` | `_m35_smoke()` |
| `PROGRESS.md` | M35 entry; updated current state line |

---

## Smoke results (2026-06-24)

```
[smoke] -- M35 event nodes + extended map --
  node_count=15 (expect 15)
  shop_count=2 (expect 2)
  event_count=2 (expect 2)
  shops_different_layers=true (expect true)
  events_have_paths=true (expect true)
  events_loadable=true (expect true)
  stage_act_tags=["act_1"] (expect [act_1])
  triage_choice_count=2 (expect 2)
  blood_price_choice_count=2 (expect 2)
```

All M1–M34 checks pass unchanged.

---

## Out of scope

- Event portraits or illustrations
- More than 2 events or procedural event placement
- Act-based filtering (act_tags stored but not read by any system)
- Event serialization to save state (events are stateless; re-entering re-shows)
- Triage choice showing the specific unit to be revived in Choice A's label is implemented (dynamic label uses `unit.display_name`)
