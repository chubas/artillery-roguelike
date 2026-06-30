class_name ArtifactSystem

static func call_combat_start(artifacts: Array, ctx: ArtifactContext) -> void:
	if not Features.artifacts_enabled:
		return
	for a in artifacts:
		a.reset_per_combat()
		a.on_combat_start(ctx)

static func call_round_start(artifacts: Array, ctx: ArtifactContext) -> void:
	if not Features.artifacts_enabled:
		return
	for a in artifacts:
		a.on_round_start(ctx)

static func call_player_turn_end(artifacts: Array, ctx: ArtifactContext) -> void:
	if not Features.artifacts_enabled:
		return
	for a in artifacts:
		a.on_player_turn_end(ctx)

static func call_unit_died(artifacts: Array, ctx: ArtifactContext, victim: Unit) -> void:
	if not Features.artifacts_enabled:
		return
	for a in artifacts:
		a.on_unit_died(ctx, victim)

static func call_unit_killed(artifacts: Array, ctx: ArtifactContext, victim: Unit, killer: Unit) -> void:
	if not Features.artifacts_enabled:
		return
	for a in artifacts:
		a.on_unit_killed(ctx, victim, killer)

static func apply_card_cost(artifacts: Array, ctx: ArtifactContext, card: CardDefinition, base_cost: int) -> int:
	if not Features.artifacts_enabled:
		return base_cost
	var cost := base_cost
	for a in artifacts:
		cost = a.modify_card_cost(ctx, card, cost)
	return cost

static func apply_projectile_strength(artifacts: Array, ctx: ArtifactContext, strength: float, flight_time: float) -> float:
	if not Features.artifacts_enabled:
		return strength
	var s := strength
	for a in artifacts:
		s = a.modify_projectile_strength(ctx, s, flight_time)
	return s

static func sum_bonus_actions(artifacts: Array, ctx: ArtifactContext) -> int:
	if not Features.artifacts_enabled:
		return 0
	var total := 0
	for a in artifacts:
		total += a.bonus_actions_on_round_start(ctx)
	return total
