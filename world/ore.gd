# Collectible Ore drop (M42): appears where a MINERAL vein was destroyed, falls to the surface, and
# merges with other Ore in its column (values sum). A player unit stepping onto its voxel collects
# it for `value * OreSystem.ORE_CURRENCY` currency. Drawn as a floating circle with a high z_index so
# it sits above units and deployables. Pure view + data — OreSystem owns spawn/settle/collect logic.
class_name Ore
extends Node2D

var vox_position : Vector2i = Vector2i.ZERO
var value        : int = 1   # number of source mineral voxels merged into this drop

func _ready() -> void:
	z_index = 4000   # above unit_layer / deployable layers

func setup(vox: Vector2i, val: int) -> Ore:
	value = val
	set_vox_position(vox)
	return self

func set_vox_position(p: Vector2i) -> void:
	vox_position = p
	position = Const.voxel_to_world(p)
	queue_redraw()

func contains_voxel(vox: Vector2i) -> bool:
	return vox == vox_position

func _draw() -> void:
	var c := Vector2(Const.VOXEL_SIZE, Const.VOXEL_SIZE) * 0.5
	var radius := float(Const.VOXEL_SIZE) * 0.42
	# Soft outer glow, solid pink core, white rim.
	draw_circle(c, radius + 2.0, Color(1.0, 0.5, 0.8, 0.25))
	draw_circle(c, radius, Color(0.95, 0.45, 0.75, 0.95))
	draw_arc(c, radius, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.5)
	# Debug value readout: currency this Ore yields, in purple to stand apart from the white terrain
	# durability numbers. (Placeholder — a proper collectible indicator may replace this later.)
	var font := ThemeDB.fallback_font
	var label := str(value * OreSystem.ORE_CURRENCY)
	var fsize := 9
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := c - Vector2(tw * 0.5, -3.0)
	draw_string(font, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.6))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.72, 0.45, 1.0))
