class_name ArtifactEnemyDebuff
extends ArtifactDef

func on_player_turn_end(ctx: ArtifactContext) -> void:
	for u in ctx.units:
		if not u.is_player and u.hp > 0:
			# Accumulating COMBAT debuff: -3 attack each player turn end (-6 after two turns).
			u.adjust_power_mod("artifact:enemy_debuff", PowerMod.Op.ADD, -3.0,
					PowerMod.Tier.COMBAT, "Enemy Debuff")
