# Data definition of a damage element (M3 spec §3.1). Carried on AoEGroups; resolved
# by AoEResolver into affinity multipliers + applied statuses. Immutable .tres.
class_name ElementDef
extends Resource

@export var id           : String = ""
@export var display_name : String = ""

## Unit status applied on hit (reference to StatusEffectDef)
@export var unit_status  : StatusEffectDef = null

## Tile status applied on hit (reference to TileStatusDef)
@export var tile_status  : TileStatusDef = null

## Unit tag this element is strong against (×1.5 damage)
@export var strong_vs_tag : String = ""

## Unit tag this element is weak against (×0.5 damage)
@export var weak_vs_tag : String = ""

## Special multiplier vs SHIELDED tag (0 = not special)
@export var vs_shielded_mult : float = 0.0
