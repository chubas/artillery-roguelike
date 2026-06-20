# Per-run mutable state for one squad unit (run-state spec §3). The persistent layer the combat
# `Unit` node is built from (on combat entry) and written back to (on exit). Holds only
# primitives / ids so it stays serialization-friendly — see to_dict/from_dict (no disk I/O yet).
class_name RunUnitState
extends RefCounted

var definition_id : String = ""        # res:// path of the UnitDefinition (id-as-path for now)
var display_name  : String = ""
var current_hp    : int = 0            # persists across stages — the run-deciding resource
var max_hp        : int = 0            # = definition.max_hp in M12 (+ permanent upgrades later)
var is_disabled   : bool = false       # hit 0 HP; persists as disabled; does not deploy
var kills         : int = 0            # scaling counter, accumulates across the run
var upgrade_slots     : int = 2             # shared pool for upgrades + fused essences (design doc §5)
var equipped_essences : Array[String] = []  # EssenceDef resource paths equipped on this unit (M22)
var upgrades          : Array[String] = []  # empty in M12 — seam for permanent upgrades
var equipment         : Array[String] = []  # empty in M12 — seam for equipment loadout

# Build a fresh, full-HP run-unit from a UnitDefinition path.
static func from_definition(def_path: String, dname: String = "") -> RunUnitState:
	var rus := RunUnitState.new()
	rus.definition_id = def_path
	var def : UnitDefinition = load(def_path)
	rus.max_hp = def.max_hp
	rus.current_hp = def.max_hp
	rus.display_name = dname if dname != "" else def.display_name
	return rus

func to_dict() -> Dictionary:
	return {
		"definition_id": definition_id,
		"display_name": display_name,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"is_disabled": is_disabled,
		"kills": kills,
		"upgrade_slots": upgrade_slots,
		"equipped_essences": equipped_essences.duplicate(),
		"upgrades": upgrades.duplicate(),
		"equipment": equipment.duplicate(),
	}

static func from_dict(d: Dictionary) -> RunUnitState:
	var rus := RunUnitState.new()
	rus.definition_id = d.get("definition_id", "")
	rus.display_name = d.get("display_name", "")
	rus.current_hp = d.get("current_hp", 0)
	rus.max_hp = d.get("max_hp", 0)
	rus.is_disabled = d.get("is_disabled", false)
	rus.kills = d.get("kills", 0)
	rus.upgrade_slots = d.get("upgrade_slots", 2)
	rus.equipped_essences.assign(d.get("equipped_essences", []))
	rus.upgrades.assign(d.get("upgrades", []))
	rus.equipment.assign(d.get("equipment", []))
	return rus
