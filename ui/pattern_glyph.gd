# Shared AoE-pattern glyph renderer (M41). Draws a small zone-colored grid of an AoEPattern into
# `rect` on any CanvasItem during its _draw(). Extracted from UnitInspector so the combat inspector
# and the reward preview render identical glyphs. Static — pass the drawing CanvasItem in.
class_name PatternGlyph

static func draw(ci: CanvasItem, pattern: AoEPattern, rect: Rect2) -> void:
	if pattern == null:
		return
	var aoe_map := pattern.to_map()
	if aoe_map.is_empty():
		return
	var min_c := 0
	var max_c := 0
	var min_r := 0
	var max_r := 0
	for offset in aoe_map:
		min_c = mini(min_c, offset.x)
		max_c = maxi(max_c, offset.x)
		min_r = mini(min_r, offset.y)
		max_r = maxi(max_r, offset.y)
	var span := maxi(max_c - min_c, max_r - min_r) + 1
	var cell := clampf(floorf(minf(rect.size.x, rect.size.y) / span), 3.0, 8.0)
	var origin := rect.position + rect.size * 0.5 - Vector2(cell, cell) * 0.5
	for offset in aoe_map:
		var group : AoEGroup = aoe_map[offset]
		var pos := origin + Vector2(offset.x, offset.y) * cell
		ci.draw_rect(Rect2(pos, Vector2(cell, cell)), AoEPattern.zone_color(group.multiplier))
	ci.draw_rect(Rect2(origin, Vector2(cell, cell)), Color(1, 1, 1, 0.9), false, 1.0)
