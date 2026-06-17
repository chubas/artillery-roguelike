class_name ArtifactLifesteal
extends ArtifactDef

func on_unit_killed(ctx: ArtifactContext, _victim: Unit, killer: Unit) -> void:
	if killer == null or not killer.is_player or killer.hp <= 0:
		return
	var heal := (killer.definition.max_hp - killer.hp) / 2
	if heal > 0:
		killer.hp = mini(killer.hp + heal, killer.definition.max_hp)
		killer.queue_redraw()
