class_name EssenceDef
extends Resource

@export var essence_name : String = ""
@export var description  : String = ""
@export var slot_cost    : int = 1
@export var faction      : String = "neutral"

func on_combat_start(ctx: EssenceContext)    -> void: pass
func on_round_start(ctx: EssenceContext)     -> void: pass
func on_player_turn_end(ctx: EssenceContext) -> void: pass
func on_unit_died(ctx: EssenceContext, victim: Unit) -> void: pass
func on_unit_fired(ctx: EssenceContext)      -> void: pass
func modify_projectile_strength(ctx: EssenceContext, strength: int, flight_time: float) -> int:
	return strength
func reset_per_combat() -> void: pass
