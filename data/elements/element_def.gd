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

## Special multiplier vs SHIELDED tag (0 = not special) — unit tag rule in AoEResolver.
@export var vs_shielded_mult : float = 0.0

## Element × mitigation-layer matrix (mechanics-compatibility §1). Applied as damage
## passes through armor → shield → HP in Unit.take_damage(). 1.0 = normal.
enum MitigationLayer { ARMOR, SHIELD, HP }
@export var vs_armor_mult  : float = 1.0
@export var vs_shield_mult : float = 1.0
@export var vs_hp_mult     : float = 1.0

func mitigation_mult(layer: MitigationLayer) -> float:
	match layer:
		MitigationLayer.ARMOR:
			return vs_armor_mult
		MitigationLayer.SHIELD:
			if vs_shield_mult != 1.0:
				return vs_shield_mult
			if vs_shielded_mult > 0.0:
				return vs_shielded_mult
			return 1.0
		MitigationLayer.HP:
			return vs_hp_mult
	return 1.0
