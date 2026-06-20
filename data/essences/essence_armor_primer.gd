class_name EssenceArmorPrimer
extends EssenceDef

func on_combat_start(ctx: EssenceContext) -> void:
	ctx.unit.armor += 10
