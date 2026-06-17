class_name ArtifactEnemyDebuff
extends ArtifactDef

func on_player_turn_end(ctx: ArtifactContext) -> void:
	for u in ctx.units:
		if not u.is_player and u.hp > 0:
			u.attack_modifier -= 3
