# M36 — Repair Shop, Upgrade Shop, CONSUMABLE keyword

## Context

Add two new out-of-combat node types to the run map — Repair and Upgrade — each with a multi-option interactive screen. Also introduces the CONSUMABLE card keyword (card purged from deck after one use) and the Heal Vial card. Unit upgrade fields are added to RunUnitState and applied at combat start. Map node placement guarantees first/last nodes are always COMBAT.

---

## Key Decisions (locked)

| # | Decision |
|---|---|
| 1 | REPAIR at node 5 (L2), UPGRADE at node 6 (L3). First (node 0) and last (node 14) stay COMBAT. |
| 2 | +fire shots = `permanent_fire_prime: int` on RunUnitState; unit gets N fire prime stacks applied to `primed_elements` at combat start. |
| 3 | Fusion refund = `const FUSION_REFUND : int = 5` in `squad_ops.gd`. Set to 0 to test no-reward fuse. |
| 4 | Consumable: after `_apply_card()` appends to discard, if `is_consumable`: erase from `_discard`, erase one matching `resource_path` from `Run.active.deck`. |
| 5 | Upgrade fields are typed ints directly on RunUnitState (not string tags), serialized in to_dict/from_dict. |
| 6 | Repair constants (top of RepairScreen): `HEAL_POOL = 4` (distribute), `SINGLE_HEAL = 6`. |
| 7 | UpgradeScreen manages an internal `_phase` enum (MAIN / PICK_UNIT / PICK_UPGRADE / PICK_TARGET / PICK_CARDS / CONFIRM_FUSE). Rebuilds UI on each sub-step transition. |
| 8 | Sandbox debug: direct-effect buttons that modify Run.active immediately without opening a sub-screen. |

---

## §1 — Data: CardDefinition

**`data/cards/card_definition.gd`**

Add to `EffectType` enum:
```gdscript
HEAL = 8
```

Add field:
```gdscript
@export var is_consumable : bool = false
```

**`systems/combat_manager.gd` — `_apply_card()`** — after moving card to discard:
```gdscript
_hand.erase(card)
_discard.append(card)
if card.is_consumable and Run.active != null:
    _discard.erase(card)
    Run.active.deck.erase(card.resource_path)
```

Add HEAL to the effect dispatch match block:
```gdscript
CardDefinition.EffectType.HEAL:
    target.hp = mini(target.hp + mag, target.definition.max_hp)
```

---

## §2 — Data: Unit Upgrade Fields

**`state/run_unit_state.gd`** — add four fields:
```gdscript
var bonus_attack         : int = 0
var permanent_boosted    : int = 0
var permanent_fire_prime : int = 0
var bonus_dig            : int = 0
```
Serialize all four in `to_dict()` / `from_dict()` with safe `.get("field", 0)` defaults.

**`world/unit.gd`** (wherever `_derive_attack()` and `_ready()` live):
- `_derive_attack()`: `return definition.attack + (run_state.bonus_attack if run_state else 0)`
- `_ready()`: `dig = definition.dig + (run_state.bonus_dig if run_state != null else 0)`

**`systems/combat_bridge.gd` — `build_squad()`** — after creating each unit:
```gdscript
if rus.permanent_boosted > 0:
    var boosted_def := load("res://data/statuses/boosted.tres")
    UnitStatusSystem.apply(u, boosted_def, rus.permanent_boosted)
if rus.permanent_fire_prime > 0:
    var fire_el := load("res://data/elements/fire.tres")
    for _i in range(rus.permanent_fire_prime):
        u.primed_elements.append(fire_el)
    u.queue_redraw()
```

---

## §3 — Data: Map Node Types

**`state/map_node.gd`** — enum:
```gdscript
enum Type { COMBAT, EVENT, SHOP, BOSS, REPAIR, UPGRADE }
```

**`state/map_state.gd` — `build_run_map()`** — after existing EVENT/SHOP assignments:
```gdscript
m.nodes[5].type = MapNode.Type.REPAIR
m.nodes[5].stage_path = ""
m.nodes[6].type = MapNode.Type.UPGRADE
m.nodes[6].stage_path = ""
```

Resulting layout:
```
L0: [0]           COMBAT (start)
L1: [1, 2]        COMBAT, COMBAT
L2: [3, 4, 5]     EVENT(triage), COMBAT, REPAIR
L3: [6, 7, 8]     UPGRADE, SHOP, COMBAT
L4: [9, 10, 11]   COMBAT, EVENT(blood_price), COMBAT
L5: [12, 13]      SHOP, COMBAT
L6: [14]          COMBAT (final)
```
First (0) and last (14) are COMBAT. ✅

---

## §4 — SquadOps: Fuse Helper

**`state/squad_ops.gd`** — add at top of file and as new static method:
```gdscript
const FUSION_REFUND : int = 5

static func fuse_units(rs: RunState, source_idx: int, target_idx: int) -> bool:
    if source_idx == target_idx: return false
    if source_idx < 0 or source_idx >= rs.squad.size(): return false
    if target_idx < 0 or target_idx >= rs.squad.size(): return false
    var src : RunUnitState = rs.squad[source_idx]
    var tgt : RunUnitState = rs.squad[target_idx]
    tgt.equipped_essences.append_array(src.equipped_essences)
    rs.squad.remove_at(source_idx)
    rs.resources["shards"] = rs.resources.get("shards", 0) + FUSION_REFUND
    return true
```
Note: does NOT call `SquadOps.retire_unit()` (which gives only 2◆ and has different semantics).

---

## §5 — ui/repair_screen.gd (NEW)

**Signal:** `repair_completed`
**Constants:** `HEAL_POOL = 4`, `SINGLE_HEAL = 6`

**Option A — Distribute Heal:**
- One card per non-disabled unit with name, HP bar, and `+1` button.
- `+1` click: `u.current_hp = mini(u.current_hp + 1, u.max_hp)`, pool--; rebuild HP bar + pool label.
- When pool = 0: all `+1` buttons disabled.
- "Done" button always visible → emits `repair_completed`.

**Option B — Single Unit Heal:**
- Unit cards as buttons; tap one: `u.current_hp = mini(u.current_hp + SINGLE_HEAL, u.max_hp)` → emit `repair_completed`.

**Option C — Heal Vial Card:**
- Immediately: `Run.active.deck.append("res://data/cards/heal_vial.tres")`
- Shows confirmation + "Done" button → emit `repair_completed`.

---

## §6 — ui/upgrade_screen.gd (NEW)

**Signal:** `upgrade_completed`
**Internal state:** `_phase` enum: MAIN / PICK_UNIT / PICK_UPGRADE / PICK_TARGET / PICK_CARDS / CONFIRM_FUSE

**Main screen (MAIN):** "Upgrade Unit" / "Fuse Units" / "Remove Cards" buttons.

**Upgrade Unit:**
1. PICK_UNIT: unit buttons → select source, go PICK_UPGRADE
2. PICK_UPGRADE: four buttons:
   - "+2 Attack Power" → `rus.bonus_attack += 2`
   - "+3 Permanent Boosted" → `rus.permanent_boosted += 3`
   - "+Fire Prime" → `rus.permanent_fire_prime += 1`
   - "+1 Digging Power" → `rus.bonus_dig += 1`
   Apply and emit `upgrade_completed`.

**Fuse Units:**
1. PICK_UNIT (source): "Pick unit to sacrifice" → select
2. PICK_TARGET: remaining units → select target
3. CONFIRM_FUSE: "Fuse [source] into [target]? Retires [source] (+5◆). All essences transfer."
   - "Confirm" → `SquadOps.fuse_units(rs, src_idx, tgt_idx)` → emit `upgrade_completed`
   - "Back" → return to MAIN

**Remove Cards:**
1. PICK_CARDS: deck card buttons + "Cancel" → tap card removes one copy from `Run.active.deck`
2. After first removal: rebuild with "Skip" + remaining cards; second tap removes another copy; "Skip" → emit `upgrade_completed`

All sub-flows have a "Back"/"Cancel" that returns to MAIN at zero cost.

---

## §7 — Features + RunController + MapScreen

**`autoloads/features.gd`:**
```gdscript
var repair_enabled  : bool = true
var upgrade_enabled : bool = true
```

**`world/run_controller.gd`** — add to `_on_node_selected()`:
```gdscript
elif node.type == MapNode.Type.REPAIR and Features.repair_enabled:
    _enter_repair(node)
elif node.type == MapNode.Type.UPGRADE and Features.upgrade_enabled:
    _enter_upgrade(node)
```
Add handlers and shared `_on_node_screen_completed()` (same logic as `_on_shop_closed`/`_on_event_completed`).

**`ui/map_screen.gd` — `_draw_node()` color branches:**
- REPAIR selectable: `Color(0.85, 0.55, 0.15)` (warm orange); locked: `Color(0.45, 0.28, 0.08, 0.65)`; label "REPAIR"
- UPGRADE selectable: `Color(0.35, 0.65, 0.95)` (silver-blue); locked: `Color(0.18, 0.32, 0.48, 0.65)`; label "UPGRADE"

**`_refresh()` detail text:**
```gdscript
elif pnode.type == MapNode.Type.REPAIR:
    _detail.text = "REPAIR — heal units or add a Heal Vial card"
elif pnode.type == MapNode.Type.UPGRADE:
    _detail.text = "UPGRADE — upgrade a unit, fuse two, or remove cards"
```

---

## §8 — Bake Resources

**`scripts/bake_resources.gd`** — add Heal Vial card:
```gdscript
var heal_vial := CardDefinition.new()
heal_vial.id           = "heal_vial"
heal_vial.display_name = "Heal Vial"
heal_vial.faction      = Faction.NEUTRAL
heal_vial.target_type  = CardDefinition.TargetType.ALLY
heal_vial.effect_type  = CardDefinition.EffectType.HEAL
heal_vial.magnitude    = 10
heal_vial.is_consumable = true
heal_vial.action_cost  = 1
heal_vial.rarity       = Rarity.COMMON
heal_vial.color        = Color(0.2, 0.8, 0.4, 1.0)
_save(heal_vial, "res://data/cards/heal_vial.tres")
```

---

## §9 — Sandbox Debug

**`debug/sandbox_overlay.gd`** — add REPAIR and UPGRADE sections:

REPAIR buttons (apply immediately to Run.active):
- "Distribute Heal (4)" → +1 HP per unit (capped)
- "Heal First Unit (6)" → squad[0].current_hp += 6
- "Add Heal Vial" → Run.active.deck.append(heal_vial path)

UPGRADE section:
- SpinBox for unit index (0-based)
- "+2 ATK" / "+3 Boosted" / "+Fire Prime" / "+1 Dig" buttons
- "Fuse 0→1" → SquadOps.fuse_units(Run.active, 0, 1) if squad.size() >= 2

---

## §10 — Smoke Test

**`world/combat_scene.gd` — `_m36_smoke()`:**
- node_count=15, repair_count=1 (node 5), upgrade_count=1 (node 6)
- node[0].type == COMBAT, node[14].type == COMBAT
- heal_vial: is_consumable=true, effect_type=HEAL, magnitude=10
- RunUnitState round-trip: set bonus_attack=3 → to_dict → from_dict → verify =3
- SquadOps.fuse_units(): essences transfer, source removed, FUSION_REFUND shards granted

---

## Files Changed

| File | Change |
|---|---|
| `data/cards/card_definition.gd` | HEAL EffectType + is_consumable field |
| `data/cards/heal_vial.tres` | NEW (baked) |
| `systems/combat_manager.gd` | HEAL case; consumable purge in _apply_card() |
| `state/run_unit_state.gd` | 4 upgrade fields + serialization |
| `world/unit.gd` | _derive_attack() + _ready() read bonus fields |
| `systems/combat_bridge.gd` | Apply permanent upgrades at squad build |
| `state/map_node.gd` | REPAIR, UPGRADE added to Type enum |
| `state/map_state.gd` | Node 5=REPAIR, node 6=UPGRADE in build_run_map() |
| `state/squad_ops.gd` | FUSION_REFUND const + fuse_units() |
| `ui/repair_screen.gd` | NEW |
| `ui/upgrade_screen.gd` | NEW |
| `autoloads/features.gd` | repair_enabled, upgrade_enabled |
| `world/run_controller.gd` | REPAIR/UPGRADE dispatch + _on_node_screen_completed() |
| `ui/map_screen.gd` | REPAIR/UPGRADE colors + labels + detail text |
| `scripts/bake_resources.gd` | Bake heal_vial.tres |
| `debug/sandbox_overlay.gd` | REPAIR + UPGRADE debug sections |
| `world/combat_scene.gd` | _m36_smoke() |
| `PROGRESS.md` + `docs/planning/milestone-36-plan.md` | Docs |

---

## Verification

1. Bake: `godot --headless --import` → `godot --headless --path . res://scripts/bake_runner.tscn` → `godot --headless --import`
2. Smoke: `ARTILLERY_SMOKE=1 godot --headless --path . res://world/combat_scene.tscn`
3. Manual: start run → map shows REPAIR (orange, node 6) and UPGRADE (blue, node 7) → enter REPAIR → distribute 4 HP across units → back to map → enter UPGRADE → fuse two units → essences transfer, 5◆ granted → Heal Vial consumed after single play
