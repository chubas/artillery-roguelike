# Static placeholder unit: 2 wide × 3 tall voxels on the spawn platform (terrain spec §13).
# No movement, no HP in M1. Barrel origin = top-center voxel of the bounding box.
class_name PlayerUnit
extends Node2D

const WIDTH_VOX  : int = 2
const HEIGHT_VOX : int = 3

var origin_vox : Vector2i = Vector2i.ZERO   # top-left voxel of bounding box

func place_at(top_left_vox: Vector2i) -> void:
	origin_vox = top_left_vox
	position = Const.voxel_to_world(origin_vox)
	queue_redraw()

# World position the barrel fires from (top-center of the box).
func barrel_origin_world() -> Vector2:
	return Const.voxel_to_world(origin_vox) \
		+ Vector2(WIDTH_VOX * Const.VOXEL_SIZE * 0.5, 0.0)

# Voxel-space bounding box, used by hitbox highlight (Phase 9).
func bounds_rect_world() -> Rect2:
	return Rect2(Const.voxel_to_world(origin_vox),
		Vector2(WIDTH_VOX * Const.VOXEL_SIZE, HEIGHT_VOX * Const.VOXEL_SIZE))

func _draw() -> void:
	# Placeholder body, drawn in local space (node is positioned at top-left).
	draw_rect(Rect2(Vector2.ZERO,
		Vector2(WIDTH_VOX * Const.VOXEL_SIZE, HEIGHT_VOX * Const.VOXEL_SIZE)),
		Color(0.3, 0.5, 0.9))
