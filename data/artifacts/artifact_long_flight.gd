class_name ArtifactLongFlight
extends ArtifactDef

func modify_projectile_strength(ctx: ArtifactContext, strength: int, flight_time: float) -> int:
	if flight_time > 2.0:
		return int(float(strength) * 1.5)
	return strength
