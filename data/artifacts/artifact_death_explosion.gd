class_name ArtifactDeathExplosion
extends ArtifactDef

var _state : Dictionary = { "triggered": false }

func on_unit_died(ctx: ArtifactContext, victim: Unit) -> void:
	if _state["triggered"] or victim.is_player:
		return
	_state["triggered"] = true
	var pattern : AoEPattern = AoEPattern.make_diamond(2, 2)
	AoEResolver.resolve(ctx.terrain, ctx.units, victim.center_voxel(), pattern, 5, false, [])

func reset_per_combat() -> void:
	_state["triggered"] = false
