# Central damage formula (M39). Single entry point for computing the float base
# strength from an attacker before zone multiplier and element affinity are applied.
#
# Formula: (attack + combat_flat + conditional_bonus) × permanent_mult × combat_mult
#
# Zone multiplier and element affinity are applied per-target in AoEResolver.
class_name DamageResolver

static func compute_base(attacker: Unit, shot: ShotDefinition, context: ShotContext) -> float:
	var base := float(attacker.attack)
	var flat := float(attacker.combat_flat)
	if Features.power_formula_enabled and shot != null:
		flat += _eval_conditionals(shot.conditional_bonus, context)
	var perm := attacker.run_state.permanent_mult if attacker.run_state != null else 1.0
	return (base + flat) * perm * attacker.combat_mult

# Evaluate shot-specific conditional flat bonuses against the shot context.
# Returns the total additional flat damage when any conditions are met.
# No conditions are defined for M39 content — this is scaffolding for future shots.
static func _eval_conditionals(bonus: Dictionary, context: ShotContext) -> float:
	if context == null or bonus.is_empty():
		return 0.0
	# Future: iterate bonus keys (condition ids) and check context fields.
	# Example: if "angle_above_70" in bonus and context.launch_angle > 70.0: total += bonus["angle_above_70"]
	return 0.0
