# Shield Generator (M6): grants shield_amount to allied units within a circular aura
# at the start of the player's turn (CombatManager._pulse_shield_generators).
# M28: aura is a Euclidean circle precomputed in voxel offsets; drawn as a faint
# semi-transparent overlay with a more opaque border ring. Brightens on hover/select.
class_name ShieldGenerator
extends Deployable

@export var aura_radius  : int = 10
@export var shield_amount : int = 3

var _fill_offsets    : Array[Vector2i] = []
var _border_segments : PackedVector2Array = PackedVector2Array()

func _init() -> void:
	max_hp = 5
	hp = 5
	color = Color(0.3, 0.6, 0.95)
	display_name = "Shield Generator"

func _ready() -> void:
	_build_aura_offsets()

func _build_aura_offsets() -> void:
	var r2 := aura_radius * aura_radius
	for dy in range(-aura_radius, aura_radius + 1):
		for dx in range(-aura_radius, aura_radius + 1):
			if dx * dx + dy * dy <= r2:
				_fill_offsets.append(Vector2i(dx, dy))
	var fill_set : Dictionary = {}
	for v in _fill_offsets:
		fill_set[v] = true
	var vs : float = Const.VOXEL_SIZE
	for vox in _fill_offsets:
		var vx : float = vox.x * vs
		var vy : float = vox.y * vs
		if not fill_set.has(Vector2i(vox.x + 1, vox.y)):
			_border_segments.append(Vector2(vx + vs, vy))
			_border_segments.append(Vector2(vx + vs, vy + vs))
		if not fill_set.has(Vector2i(vox.x - 1, vox.y)):
			_border_segments.append(Vector2(vx, vy))
			_border_segments.append(Vector2(vx, vy + vs))
		if not fill_set.has(Vector2i(vox.x, vox.y + 1)):
			_border_segments.append(Vector2(vx, vy + vs))
			_border_segments.append(Vector2(vx + vs, vy + vs))
		if not fill_set.has(Vector2i(vox.x, vox.y - 1)):
			_border_segments.append(Vector2(vx, vy))
			_border_segments.append(Vector2(vx + vs, vy))

func _process(_delta: float) -> void:
	var new_h := bounds_rect_world().has_point(get_global_mouse_position())
	if new_h != hovered:
		hovered = new_h
		queue_redraw()

func _draw() -> void:
	var fill_alpha   : float = 0.22 if (hovered or selected) else 0.12
	var border_alpha : float = 0.45 if (hovered or selected) else 0.28
	var vs : float = Const.VOXEL_SIZE
	var fill_col   := Color(color.r, color.g, color.b, fill_alpha)
	var border_col := Color(color.r, color.g, color.b, border_alpha)
	for off in _fill_offsets:
		draw_rect(Rect2(Vector2(off.x * vs, off.y * vs), Vector2(vs, vs)), fill_col)
	var i := 0
	while i < _border_segments.size():
		draw_line(_border_segments[i], _border_segments[i + 1], border_col, 1.5, true)
		i += 2
	super._draw()
