class_name ArtifactSquadRegen
extends ArtifactDef

func on_round_start(ctx: ArtifactContext) -> void:
	for u in ctx.units:
		if u.is_player and u.hp > 0:
			u.hp = mini(u.hp + 1, u.definition.max_hp)
			u.queue_redraw()
