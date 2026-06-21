# Milestone 27 — Map Squad Bar, Shards HUD, Repair & Retire

## Goal

Make the world map the hub for squad management between stages: always show the run's Shards
balance, display every squad member as a portrait card, and let the player **Repair** disabled
units or **Retire** any unit (healthy or disabled) to free capacity — the first two Shard sinks
from the currency design doc.

---

## Context (already in place)

| Piece | Status |
|---|---|
| Shards in `RunState.resources["shards"]`, start **10** | M21 (`Run.start_default_run()`) |
| Unit death → `is_disabled = true` on write-back | M12 (`CombatBridge.write_back()`) |
| Disabled units stay in `Run.active.squad`, excluded from deploy | M12 (`CombatBridge.build_squad()`) |
| Disabled units still count toward capacity | M23 (`_used_capacity()` sums all squad entries) |
| Whole-squad-disabled → RUN OVER | M14 (`run_controller._on_combat_exited`) |
| Map capacity label | M23 (`MapScreen._capacity_label`) |

No combat or run-flow changes are required for persistence — M27 is map UI + squad actions.

---

## Deliverables

1. **Shards HUD** — always visible on `MapScreen` (and the run-complete / run-over banner state).
2. **Squad portrait bar** — horizontal row of card-sized unit portraits at the top; one entry per
   `RunUnitState` in squad order.
3. **Hover tooltip** — name + `current_hp / max_hp` (disabled units show `0 / max_hp`).
4. **Unit context menu** — click any portrait → popup with **Retire** (+2 ◆); **Repair** (5 ◆)
   shown only when the unit is disabled. Refresh bar, shards label, and capacity after any action.
5. **`SquadOps` utility** — static repair/retire logic (keeps UI thin, smoke-testable without scene tree).
6. **Smoke test** — `_m27_smoke()` in `combat_scene.gd`.

---

## Locked decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Repair cost: flat 5 Shards** | User-specified for M27. Design doc §1.3 scaling (missing HP + repair history) is deferred — no `repair_count` field yet. |
| 2 | **Retire refund: flat 2 Shards** | User-specified for M27. Design doc §3 per-unit-type payout deferred; one constant for now. |
| 3 | **Repair restores fully** | `is_disabled = false`, `current_hp = max_hp`. Shield/armor still reset per-combat as today. |
| 4 | **Retire removes the unit** | `squad.remove_at(index)` — frees `capacity_cost`, refunds Shards. Essences/upgrades on that instance are lost (no transplant in M27). |
| 5 | **Portrait ≠ card resource** | Draw a card-frame placeholder using `UnitDefinition.color` (same palette as combat `_draw()`). No sprite art; no `CardDefinition` involvement. |
| 6 | **Context menu on every portrait** | Click any squad member to open actions. Matches design doc §2: retire is valid on healthy or disabled units. |
| 7 | **Repair only when disabled; Retire always** | Repair row hidden or greyed when unit is active. Repair disabled when `shards < 5`. Retire always enabled (+2 ◆, same payout either way). |
| 8 | **Shards label placement** | Top strip of the map screen, left side: `◆ Shards: N`. Portrait bar shares the same top strip (right side or full width below the label row). |
| 9 | **No new run-state fields** | Flat costs need no serialization changes. `to_dict`/`from_dict` already round-trip `resources` and `squad`. |

---

## UI layout (MapScreen)

```text
┌─────────────────────────────────────────────────────────────┐
│ ◆ Shards: 10          Squad Capacity: 4 / 8                 │
│ [Cluster] [Bypass] [Magnet†] [Spiral]   ← portrait cards    │
├─────────────────────────────────────────────────────────────┤
│              ARTILLERY SPACE — RUN MAP                      │
│                    (diamond graph)                          │
│                    stage detail + hint                      │
└─────────────────────────────────────────────────────────────┘

† disabled: desaturated color + faint red border (all portraits clickable)
```

### Portrait card (`UnitPortrait` control)

- Size ~56×72 px (card silhouette, not full reward-card 190×230).
- Body: filled rect in `UnitDefinition.color`; disabled → `color.lerp(dark_red, 0.5)`.
- Optional thin HP strip at bottom (`current_hp / max_hp` as fill width).
- Hover: `Tooltip` or custom popup — `"{display_name}\nHP: {current} / {max}"`.
- Click: emit `portrait_clicked(index)` → parent opens context menu.

### Context menu (`UnitActionMenu` — PopupPanel or PopupMenu)

| Action | Enabled when | Effect |
|---|---|---|
| **Repair (5 ◆)** | unit `is_disabled` and `shards >= 5` | `SquadOps.repair_unit(rs, index)` |
| **Retire (+2 ◆)** | always (any squad member) | `SquadOps.retire_unit(rs, index)` |

Healthy units: menu shows **Retire** only. Disabled units: both **Repair** and **Retire**.

Dismiss on action, outside click, or Esc. After action: `_refresh()` on map screen.

---

## SquadOps API

New file: `state/squad_ops.gd` (`class_name SquadOps`).

```gdscript
const REPAIR_COST := 5
const RETIRE_REFUND := 2

static func repair_unit(rs: RunState, index: int) -> bool
static func retire_unit(rs: RunState, index: int) -> bool
static func can_repair(rs: RunState, unit: RunUnitState) -> bool
static func can_retire(unit: RunUnitState) -> bool
static func used_capacity(rs: RunState) -> int   # move from run_controller for single source
```

**`repair_unit`:** guard index + disabled + shards; deduct 5; clear disabled; set HP to max; return success.

**`retire_unit`:** guard index; remove from squad (healthy or disabled); add 2 shards; return success.

**`used_capacity`:** sum `UnitDefinition.capacity_cost` for every squad member (disabled or not). Update `run_controller._used_capacity()` to delegate here.

---

## Files to change

| File | Change |
|---|---|
| `state/squad_ops.gd` | **New** — repair/retire/capacity helpers |
| `ui/unit_portrait.gd` | **New** — card-frame portrait + hover + click signal |
| `ui/map_screen.gd` | Top strip (shards + squad bar); wire portrait clicks → action menu; `_refresh()` updates all |
| `world/run_controller.gd` | `_used_capacity()` → `SquadOps.used_capacity()` |
| `world/combat_scene.gd` | `_m27_smoke()` + call in smoke chain |
| `state/squad_ops.gd.uid` | Godot import artifact — **commit with script** so `class_name SquadOps` registers headless |
| `ui/unit_portrait.gd.uid` | Same for `UnitPortrait` |
| `docs/planning/milestone-27-plan.md` | This file |
| `PROGRESS.md` | M27 entry (on implementation) |

**New `class_name` scripts:** run `godot --headless --import` once after adding them, then commit the `.uid` files. Without this, dependent scripts fail to parse and smoke hangs in a `_hud`/`_targeting` nil loop.

---

## Build phases

| Phase | Goal | Ends when |
|---|---|---|
| **1. SquadOps** | Static repair/retire/capacity | Smoke can repair/retire in isolation |
| **2. Shards HUD** | Label on map, updates on action | Map shows `◆ Shards: 10` at run start |
| **3. Portrait bar** | All squad members rendered | Hover shows name + HP; disabled visually distinct |
| **4. Action menu** | Click portrait → Retire (any) / Repair (disabled) | Manual: retire healthy unit; kill + repair/retire disabled unit |
| **5. Smoke** | `_m27_smoke()` | Headless smoke passes |

---

## Manual verification

1. **Start run** — map shows Shards **10**, two portraits (Cluster, Bypass), capacity **4 / 8**.
2. **Enter combat, kill one unit, clear stage** — return to map; dead unit still in bar (disabled look), capacity still **4 / 8**, Shards unchanged.
3. **Hover** any portrait — tooltip shows correct name and HP (0/max for disabled).
4. **Repair** disabled unit — Shards **5**, unit active at full HP, deploys next fight.
5. **Repair blocked** — with Shards **4**, Repair action greyed out.
6. **Retire** disabled unit — Shards **+2**, portrait gone, capacity drops by **2**.
7. **Retire** healthy unit — same **+2** refund, unit removed, capacity freed (design doc §2).
8. **All disabled, none repaired** — entering next stage impossible (no deployable units); existing RUN OVER path still fires on failed combat exit.
9. **New Run** — Shards reset to **10**, default squad restored.

---

## Smoke test (`_m27_smoke`)

Deterministic, no scene tree:

```
Run.start_default_run()
assert shards == 10
disable squad[0] (is_disabled=true, current_hp=0)
assert SquadOps.used_capacity == 4
SquadOps.repair_unit → shards==5, not disabled, hp==max
SquadOps.retire_unit (disabled) → squad.size==1, shards==7, used_capacity==2
Run.start_default_run(); SquadOps.retire_unit (healthy) → squad.size==1, shards==12
RunState round-trip preserves shards + disabled state
```

---

## Out of scope

| Item | Notes |
|---|---|
| Shard **income** (terrain, kills, stage clear) | Sources in design doc §1.2 — later milestone |
| Escalating repair cost / `repair_count` | Flat 5 for M27; seam is a future field on `RunUnitState` |
| Per-unit-type retire payout | Flat 2 for M27 |
| Fusion | M28+ |
| Reward screen Shards display | Map-only for M27 |
| Unit sprite portraits | Placeholder colors until art pass |
| Save/load to disk | `to_dict` already sufficient for round-trip tests |

---

## Seams for later

| Seam | Notes |
|---|---|
| **`RunUnitState.repair_count`** | Increment on repair; feed into scaled cost from design doc |
| **`UnitDefinition.retire_payout`** | Replace flat `RETIRE_REFUND` constant |
| **Fusion** | Third menu action; uses `upgrade_slots` + essence transplant |
| **Shard earn VFX on map** | When income milestones land, animate `◆` counter |
