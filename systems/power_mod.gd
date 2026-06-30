# One source-attributed modifier to a unit's attack power (M40).
#
# A unit's effective attack is base_power folded with a list of these. Each mod records WHERE it
# came from (source) so it can be removed when that source ends, shown in a UI breakdown, and
# (optionally) gated behind a live predicate. Two tiers fold separately — see PowerCalculator.
#
#   PERMANENT — run-level: equipment, permanent upgrades, lasting artifact bonuses. Serialized
#               on RunUnitState; defines the card / round-start value.
#   COMBAT    — per-combat only: status buffs/debuffs, deployable auras, conditional artifacts.
#               Rebuilt each combat; never serialized.
#
# `condition` is an optional compute-time predicate(unit) -> bool. Empty = always active. It is
# intentionally NOT serialized: conditional mods are re-attached live by their source on combat
# start (the source object owns the closure that captures whatever context it needs).
class_name PowerMod
extends RefCounted

enum Op   { ADD, MULT }
enum Tier { PERMANENT, COMBAT }

var source    : String                 # "upgrade:attack", "artifact:enemy_debuff", "equipment:railgun"
var label     : String                 # human label for UI breakdown ("Rally", "Last Stand")
var op        : Op   = Op.ADD
var value     : float = 0.0
var tier      : Tier = Tier.COMBAT
var condition : Callable = Callable()  # empty = always active; else predicate(unit) -> bool

func _init(p_source := "", p_op := Op.ADD, p_value := 0.0,
		p_tier := Tier.COMBAT, p_label := "", p_condition := Callable()) -> void:
	source = p_source
	op = p_op
	value = p_value
	tier = p_tier
	label = p_label if p_label != "" else p_source
	condition = p_condition

## True when this mod counts toward the fold right now (no predicate, or predicate passes).
func active_for(unit) -> bool:
	return not condition.is_valid() or bool(condition.call(unit))

## Serializable payload. The predicate is deliberately dropped (see class header).
func to_dict() -> Dictionary:
	return { "source": source, "label": label,
			"op": int(op), "value": value, "tier": int(tier) }

static func from_dict(d: Dictionary) -> PowerMod:
	return PowerMod.new(d.get("source", ""), d.get("op", Op.ADD), d.get("value", 0.0),
			d.get("tier", Tier.PERMANENT), d.get("label", ""))
