# Stateless diamond-AoE resolver (terrain spec §8.3, falloff reconciled in plan §1.1).
class_name AoEResolver

# Damages every tile within Manhattan distance `radius` of (cx,cy), then flushes
# the batched collapse so tiles fall once, after the whole blast (plan §1.3).
# Returns the Array[Vector2i] of affected voxels.
static func resolve(terrain: TerrainManager, cx: int, cy: int,
		radius: int, base_damage: int) -> Array:
	var affected : Array = []
	for col in range(cx - radius, cx + radius + 1):
		for row in range(cy - radius, cy + radius + 1):
			var dist := absi(col - cx) + absi(row - cy)
			if dist > radius:
				continue
			var dmg := maxi(1, int(base_damage * falloff(dist)))
			terrain.damage_tile(col, row, dmg)
			affected.append(Vector2i(col, row))
	terrain.flush_collapses()
	terrain.aoe_resolved.emit(Vector2i(cx, cy), radius, affected)
	return affected

# Distance-based falloff: 100% / 75% / 50% / 25% / 0% at dist 0,1,2,3,4+.
# (Plan §1.1 — radius-independent, matches the spec §8.2 table.)
static func falloff(dist: int) -> float:
	return maxf(0.0, 1.0 - 0.25 * dist)
