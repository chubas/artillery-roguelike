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

## Tags on this status; used by cleanse and interaction rules.
## Valid values: FIRE, ELECTRIC, POISON, SPREADABLE, ORGANIC
@export var tags : Array[String] = []

## Status that cleanses this one on application (e.g. fire cleanses chill)
@export var cleansed_by_element : String = ""
