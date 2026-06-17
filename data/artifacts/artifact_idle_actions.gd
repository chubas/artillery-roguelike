class_name ArtifactIdleActions
extends ArtifactDef

func bonus_actions_on_round_start(ctx: ArtifactContext) -> int:
	var bonus := 0
	for u in ctx.units:
		if u.is_player and u.hp > 0 and not u.moved_this_turn:
			bonus += 1
	return bonus
