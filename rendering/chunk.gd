# One CHUNK_SIZE×CHUNK_SIZE region. _draw() paints its voxels as colored rects with
# variant tints and crack overlays (terrain spec §11.2–11.3, placeholder art).
# Redraws only when marked dirty by TerrainRenderer.
class_name Chunk
extends Node2D

# Placeholder palette: earth tones per variant; reinforced reads as stone;
# the indestructible spawn platform reads as dark steel.
const COLOR_SOLID := [
	Color8(152, 114, 76), Color8(141, 104, 68),
	Color8(160, 122, 82), Color8(133, 98, 64),
]
const COLOR_REINFORCED := [
	Color8(122, 130, 140), Color8(112, 120, 130),
	Color8(130, 138, 148), Color8(104, 112, 122),
]
const COLOR_PLATFORM := Color8(70, 76, 88)
const COLOR_LAVA     := Color8(220, 80, 20)

var cx : int = 0
var cy : int = 0
var _terrain : TerrainManager

func setup(chunk_col: int, chunk_row: int, terrain: TerrainManager) -> Chunk:
	cx = chunk_col
	cy = chunk_row
	_terrain = terrain
	position = Vector2(cx * Const.CHUNK_SIZE * Const.VOXEL_SIZE,
			cy * Const.CHUNK_SIZE * Const.VOXEL_SIZE)
	return self

func mark_dirty() -> void:
	queue_redraw()

func _draw() -> void:
	var vs := float(Const.VOXEL_SIZE)
	for ly in range(Const.CHUNK_SIZE):
		for lx in range(Const.CHUNK_SIZE):
			var col := cx * Const.CHUNK_SIZE + lx
			var row := cy * Const.CHUNK_SIZE + ly
			var tile := _terrain.get_tile(col, row)
			if tile == null:
				continue
			var rect := Rect2(lx * vs, ly * vs, vs, vs)
			var base : Color
			if tile.type == Tile.TileType.LAVA:
				base = COLOR_LAVA
				draw_rect(rect, base)
				draw_rect(rect, base.darkened(0.3), false, 1.0)
				continue
			if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE):
				base = COLOR_PLATFORM
			elif tile.max_hp > 3:
				base = COLOR_REINFORCED[tile.variant]
			else:
				base = COLOR_SOLID[tile.variant]
			draw_rect(rect, base)
			# Hairline border keeps the voxel grid readable.
			draw_rect(rect, base.darkened(0.3), false, 1.0)
			_draw_cracks(rect, tile.damage_state())
			_draw_status_overlay(rect, tile)
			_draw_hp_label(rect, tile)

# Placeholder tile-status tints (M3 §16): burning = orange, electrified = blue-white.
func _draw_status_overlay(rect: Rect2, tile: Tile) -> void:
	if tile.tile_statuses.is_empty():
		return
	if tile.tile_statuses.has("burning"):
		draw_rect(rect, Color(1.0, 0.45, 0.1, 0.45))
	if tile.tile_statuses.has("electrified"):
		draw_rect(rect, Color(0.55, 0.8, 1.0, 0.5))

func _draw_hp_label(rect: Rect2, tile: Tile) -> void:
	if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE):
		return
	var font  := ThemeDB.fallback_font
	var fsize : int = 7
	var text  := str(tile.hp)
	var tw    := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var center := rect.position + rect.size * 0.5
	draw_string(font, Vector2(center.x - tw * 0.5, center.y + font.get_ascent(fsize) * 0.5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.55))

func _draw_cracks(rect: Rect2, state: int) -> void:
	if state == 0:
		return
	var p := rect.position
	var s := rect.size
	if state == 1:
		draw_rect(rect, Color(0, 0, 0, 0.18))
		draw_line(p + Vector2(s.x * 0.2, s.y * 0.8), p + Vector2(s.x * 0.8, s.y * 0.25),
				Color(0, 0, 0, 0.55), 1.0)
	else:
		draw_rect(rect, Color(0, 0, 0, 0.4))
		draw_line(p + Vector2(s.x * 0.15, s.y * 0.85), p + Vector2(s.x * 0.85, s.y * 0.2),
				Color(0, 0, 0, 0.7), 1.0)
		draw_line(p + Vector2(s.x * 0.2, s.y * 0.2), p + Vector2(s.x * 0.85, s.y * 0.8),
				Color(0, 0, 0, 0.7), 1.0)
