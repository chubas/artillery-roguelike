# Last Stand (M40): while a player unit is the sole surviving player unit, its attack is ×1.5.
#
# Demonstrates the compute-time predicate path of the PowerMod system. At combat start each
# player unit gets a COMBAT MULT ×1.5 mod whose `condition` closure captures the live Artifact
# context — it counts living player units at evaluation time, so the bonus switches on/off
# dynamically as units fall (or are revived) without any per-turn bookkeeping.
class_name ArtifactLastStand
extends ArtifactDef

func on_combat_start(ctx: ArtifactContext) -> void:
	for u in ctx.units:
		if not u.is_player:
			continue
		var predicate := func(_unit) -> bool:
			var alive := 0
			for other in ctx.units:
				if other.is_player and other.hp > 0:
					alive += 1
			return alive == 1
		u.add_power_mod(PowerMod.new("artifact:last_stand", PowerMod.Op.MULT, 1.5,
				PowerMod.Tier.COMBAT, "Last Stand", predicate))
