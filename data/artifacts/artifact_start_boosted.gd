class_name ArtifactStartBoosted
extends ArtifactDef

# At the start of the stage, grant every player unit Boosted(3) — their first 3 moves cost
# no action point (each spends a Boosted stack instead). The stacks persist across turns.
func on_combat_start(ctx: ArtifactContext) -> void:
	var boosted : StatusEffectDef = load("res://data/statuses/boosted.tres")
	for u in ctx.units:
		if u.is_player:
			UnitStatusSystem.apply(u, boosted, 3)
