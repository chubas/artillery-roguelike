# Central damage formula (M40). Single entry point for computing the float base
# strength from an attacker before zone multiplier and element affinity are applied.
#
# Base attack comes from PowerCalculator.effective_attack_f(attacker): definition.base_power
# folded with the unit's source-attributed PowerMods in two tiers —
#   permanent = max(0, (base_power + Σ perm_add) × Π perm_mult)
#   combat    = max(0, (permanent  + Σ comb_add) × Π comb_mult)
#
# On top of that, a shot may add a flat conditional_bonus (additive, pre-zone), evaluated from
# ShotContext. Zone multiplier and element affinity are applied per-target in AoEResolver, where
# the single floor() happens — so this returns a float to preserve precision downstream.
class_name DamageResolver

static func compute_base(attacker: Unit, shot: ShotDefinition, context: ShotContext) -> float:
	var power := PowerCalculator.effective_attack_f(attacker)
	if Features.power_formula_enabled and shot != null:
		power += _eval_conditionals(shot.conditional_bonus, context)
	return maxf(0.0, power)

# Evaluate shot-specific conditional flat bonuses against the shot context.
# Returns the total additional flat damage when any conditions are met.
# No conditions are defined for M39 content — this is scaffolding for future shots.
static func _eval_conditionals(bonus: Dictionary, context: ShotContext) -> float:
	if context == null or bonus.is_empty():
		return 0.0
	# Future: iterate bonus keys (condition ids) and check context fields.
	# Example: if "angle_above_70" in bonus and context.launch_angle > 70.0: total += bonus["angle_above_70"]
	return 0.0
