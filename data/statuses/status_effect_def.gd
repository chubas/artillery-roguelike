# Data definition of a unit status effect (M3 spec §4.1). Immutable; a StatusInstance
# tracks per-unit state. Burn and Shock in M3; Chill/Corrode/Goo/etc. add only .tres.
class_name StatusEffectDef
extends Resource

@export var id           : String = ""
@export var display_name : String = ""
@export var max_stacks   : int = 3
@export var duration     : int = 2    # turns; -1 = permanent for stage

## Damage dealt per stack per tick (applied at tick phase)
@export var tick_damage  : int = 0

## Action point reduction per stack per turn (applied to shared pool)
@export var ap_reduction : int = 0

## Effects framing (M10): the status system is the general "Effects" layer — burn/shock are
## debuffs, but effects can also be buffs or triggers.
## True = beneficial effect (drawn green). False = debuff (drawn by element tag).
@export var is_buff : bool = false
## False = persists indefinitely (tick_all never decrements turns_left). Boosted uses this.
@export var decays_per_turn : bool = true
## True = a voluntary AP-costing move spends one stack instead of an action point (Boosted).
@export var consumed_by_move : bool = false

## Tags on this status; used by cleanse and interaction rules.
## Valid values: FIRE, ELECTRIC, POISON, SPREADABLE, ORGANIC
@export var tags : Array[String] = []

## Status that cleanses this one on application (e.g. fire cleanses chill)
@export var cleansed_by_element : String = ""

## Tokens: {tick_damage}, {ap_reduction}, {duration}, {max_stacks}. Leave empty = no tooltip.
@export var description_template : String = ""

func resolve_description() -> String:
	if description_template.is_empty(): return ""
	return description_template.format({
		"tick_damage":  tick_damage,
		"ap_reduction": ap_reduction,
		"duration":     duration,
		"max_stacks":   max_stacks,
	})
