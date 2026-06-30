class_name ArtifactLongFlight
extends ArtifactDef

func modify_projectile_strength(ctx: ArtifactContext, strength: float, flight_time: float) -> float:
	if flight_time > 2.0:
		return strength * 1.5
	return strength
