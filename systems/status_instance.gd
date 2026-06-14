# Per-unit runtime state for one status effect (M3 spec §4.2). Mutable; references an
# immutable StatusEffectDef. Lives in Unit.active_statuses keyed by status id.
class_name StatusInstance
extends RefCounted

var definition : StatusEffectDef
var stacks     : int = 1
var turns_left : int

func _init(def: StatusEffectDef, initial_stacks: int = 1) -> void:
	definition = def
	stacks = initial_stacks
	turns_left = def.duration

## Add stacks up to cap; refresh duration regardless (cap-refresh rule, deliverable 9).
func apply_stacks(n: int) -> void:
	stacks = mini(stacks + n, definition.max_stacks)
	turns_left = definition.duration

## Returns true if the status should be removed after this tick.
func tick() -> bool:
	turns_left -= 1
	return turns_left <= 0
