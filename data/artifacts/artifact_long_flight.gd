class_name ArtifactLongFlight
extends ArtifactDef

func modify_projectile_strength(ctx: ArtifactContext, strength: int, flight_time: float) -> int:
	if flight_time > 10.0:
		return int(float(strength) * 1.2)
	return strength
