class_name EssenceDoubleShot
extends EssenceDef

func on_unit_fired(ctx: EssenceContext) -> void:
	ctx.combat.schedule_refire(ctx.unit, ctx.last_shot, ctx.last_speed, 2.0)
