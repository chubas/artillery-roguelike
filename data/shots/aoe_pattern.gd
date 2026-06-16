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

## Shared zone→color palette (M7): orange = full strength, yellow = half strength,
## anything below that fades toward gray. Used by both the world AoE preview and the
## unit-card pattern glyph so zone colors stay consistent everywhere. Add a threshold
## here if a future pattern introduces a third zone.
static func zone_color(multiplier: float) -> Color:
	if multiplier >= 1.0:
		return Color(1.0, 0.55, 0.1)
	if multiplier >= 0.5:
		return Color(0.95, 0.85, 0.2)
	return Color(0.6, 0.6, 0.6).lerp(Color(0.95, 0.85, 0.2), multiplier / 0.5)

# ── Static generator helpers ─────────────────────────────────────────────────
# Authoring aids: build patterns programmatically, bake to .tres via
# scripts/bake_resources.gd. The runtime always uses the baked .tres.

## Two-zone diamond: rings 0..core_radius are full strength (1.0x), rings
## core_radius+1..edge_radius are half strength (0.5x). Shape only — magnitude comes
## from whatever fires the shot (see ShotDefinition.strength / Unit.power).
static func make_diamond(core_radius: int, edge_radius: int) -> AoEPattern:
	var p := AoEPattern.new()
	var core := AoEGroup.new()
	core.multiplier = 1.0
	for dist in range(0, core_radius + 1):
		core.offsets.append_array(_ring_offsets(dist))
	p.groups.append(core)
	if edge_radius > core_radius:
		var edge := AoEGroup.new()
		edge.multiplier = 0.5
		for dist in range(core_radius + 1, edge_radius + 1):
			edge.offsets.append_array(_ring_offsets(dist))
		p.groups.append(edge)
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
