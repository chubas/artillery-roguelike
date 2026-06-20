class_name EssenceSystem

static func call_combat_start(essences: Array, ctx: EssenceContext) -> void:
	if not Features.essences_enabled:
		return
	for e in essences:
		(e as EssenceDef).reset_per_combat()
		(e as EssenceDef).on_combat_start(ctx)

static func call_round_start(essences: Array, ctx: EssenceContext) -> void:
	if not Features.essences_enabled:
		return
	for e in essences:
		(e as EssenceDef).on_round_start(ctx)

static func call_player_turn_end(essences: Array, ctx: EssenceContext) -> void:
	if not Features.essences_enabled:
		return
	for e in essences:
		(e as EssenceDef).on_player_turn_end(ctx)

static func call_unit_died(essences: Array, ctx: EssenceContext, victim: Unit) -> void:
	if not Features.essences_enabled:
		return
	for e in essences:
		(e as EssenceDef).on_unit_died(ctx, victim)

static func call_unit_fired(essences: Array, ctx: EssenceContext) -> void:
	if not Features.essences_enabled:
		return
	for e in essences:
		(e as EssenceDef).on_unit_fired(ctx)

static func apply_projectile_strength(essences: Array, ctx: EssenceContext,
		strength: int, flight_time: float) -> int:
	if not Features.essences_enabled:
		return strength
	var s := strength
	for e in essences:
		s = (e as EssenceDef).modify_projectile_strength(ctx, s, flight_time)
	return s
