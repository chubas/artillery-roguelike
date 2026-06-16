# Shield Generator (M6): grants shield_amount to every living ally within aura_radius
# at the start of the player's turn (CombatManager._pulse_shield_generators). Ally-only
# for now — see the plan note for widening to enemies later without restructuring.
# Destructible like a mine, but with no special death behavior (plain deployable_died).
class_name ShieldGenerator
extends Deployable

@export var aura_radius : int = 10
@export var shield_amount : int = 2

func _init() -> void:
	max_hp = 5
	hp = 5
	color = Color(0.3, 0.6, 0.95)
	display_name = "Shield Generator"
