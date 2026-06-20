class_name EssenceDef
extends Resource

@export var essence_name         : String = ""
@export var description_template : String = ""
@export var slot_cost            : int = 1
@export var faction              : String = "neutral"
@export var base_value           : int = 0   # main numeric output of this essence
@export var value_per_level      : int = 0   # seam for level scaling; 0 = no scaling yet

func effective_value(level: int = 0) -> int:
	return base_value + value_per_level * level

func resolve_params(level: int = 0) -> Dictionary:
	return {"value": effective_value(level)}

func resolve_description(level: int = 0) -> String:
	if description_template.is_empty(): return ""
	return description_template.format(resolve_params(level))

func on_combat_start(ctx: EssenceContext)    -> void: pass
func on_round_start(ctx: EssenceContext)     -> void: pass
func on_player_turn_end(ctx: EssenceContext) -> void: pass
func on_unit_died(ctx: EssenceContext, victim: Unit) -> void: pass
func on_unit_fired(ctx: EssenceContext)      -> void: pass
func modify_projectile_strength(ctx: EssenceContext, strength: int, flight_time: float) -> int:
	return strength
func reset_per_combat() -> void: pass
