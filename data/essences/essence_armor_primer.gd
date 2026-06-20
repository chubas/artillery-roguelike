class_name EssenceArmorPrimer
extends EssenceDef

func on_combat_start(ctx: EssenceContext) -> void:
	var level := ctx.unit.run_state.level if ctx.unit.run_state != null else 0
	ctx.unit.add_armor(effective_value(level))
