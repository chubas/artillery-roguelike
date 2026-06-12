# Line-of-sight DDA voxel raycast (terrain spec §10). M1 use: firing-arc validation only.
class_name LoS

# False if any blocked tile lies strictly between `from` and `to`.
static func has_los(terrain: TerrainManager, from: Vector2i, to: Vector2i) -> bool:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var steps := maxi(abs(dx), abs(dy))
	if steps == 0:
		return true
	var sx := float(dx) / steps
	var sy := float(dy) / steps
	for i in range(1, steps):
		var col := int(round(from.x + sx * i))
		var row := int(round(from.y + sy * i))
		if terrain.is_blocked(col, row):
			return false
	return true
