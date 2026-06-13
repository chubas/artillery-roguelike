# Ordered list of AoEGroups (M2 spec §2.2). Groups are evaluated in order; if two
# groups cover the same offset the LAST one wins (inner rings can override outer).
class_name AoEPattern
extends Resource

@export var groups : Array[AoEGroup] = []

## Flatten to offset→AoEGroup dictionary for O(1) lookup during resolution.
func to_map() -> Dictionary:
	var result : Dictionary = {}
	for group in groups:
		for offset in group.offsets:
			result[offset] = group
	return result

func max_damage() -> int:
	var m := 1
	for group in groups:
		m = maxi(m, group.damage)
	return m

# ── Static generator helpers ─────────────────────────────────────────────────
# Authoring aids: build patterns programmatically, bake to .tres via
# scripts/bake_resources.gd. The runtime always uses the baked .tres.

static func make_diamond(radius: int, base_dmg: int, falloff: float = 1.0) -> AoEPattern:
	# falloff: damage reduction per ring. 1.0 = reduce by 1 per ring.
	var p := AoEPattern.new()
	for dist in range(0, radius + 1):
		var g := AoEGroup.new()
		g.damage = maxi(1, base_dmg - int(dist * falloff))
		g.offsets = _ring_offsets(dist)
		p.groups.append(g)
	return p

static func _ring_offsets(dist: int) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if dist == 0:
		result.append(Vector2i(0, 0))
		return result
	for col in range(-dist, dist + 1):
		var row_abs := dist - absi(col)
		result.append(Vector2i(col, row_abs))
		if row_abs != 0:
			result.append(Vector2i(col, -row_abs))
	return result
