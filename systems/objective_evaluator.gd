# Evaluates a stage's ObjectiveDescriptor against current combat state (run-state spec §9).
# Static and pure — same shape as AoEResolver / ArtifactSystem. CombatManager computes the inputs
# and calls this at each death and at round start; the shared loss (whole squad gone) is checked
# first, then the per-type win condition. New objective types slot into the match below.
class_name ObjectiveEvaluator

enum Result { ONGOING, WON, LOST }

static func evaluate(obj: ObjectiveDescriptor, enemies_alive: bool, players_alive: bool,
		round_index: int, all_waves_spawned: bool, boss_alive: bool = true) -> Result:
	if not players_alive:
		return Result.LOST   # shared loss across all objective types
	if obj == null:
		return Result.ONGOING
	match obj.type:
		ObjectiveDescriptor.Type.DEFEAT_ALL:
			# Wait for every scheduled wave to land before clearing (M7 gate preserved).
			if not enemies_alive and all_waves_spawned:
				return Result.WON
		ObjectiveDescriptor.Type.SURVIVE_N:
			if round_index >= obj.survive_rounds:
				return Result.WON
		ObjectiveDescriptor.Type.DEFEAT_BOSS:
			# M47: the boss dying ends the stage regardless of minions/waves still on the field.
			if not boss_alive:
				return Result.WON
	return Result.ONGOING
