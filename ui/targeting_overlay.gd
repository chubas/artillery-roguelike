# World-space drawing child of TargetingUI (the CanvasLayer follows the viewport,
# so drawing here in world coordinates lines up with terrain).
# Gunbound-style aiming: barrel angle indicator always shown; while charging, the
# full simulated arc + AoE footprint at the predicted impact voxel.
class_name TargetingOverlay
extends Node2D

var terrain : TerrainManager
var unit : PlayerUnit

var angle_deg : float = 45.0
var charging : bool = false
var power_frac : float = 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func aim_dir() -> Vector2:
	var r := deg_to_rad(angle_deg)
	return Vector2(cos(r), -sin(r))

func _draw() -> void:
	if unit == null:
		return
	var bounds := unit.bounds_rect_world()
	# Hover hitbox outline (terrain spec §11.4).
	if bounds.has_point(get_global_mouse_position()):
		draw_rect(bounds, Color(1, 1, 1, 0.9), false, 1.0)
	var barrel := unit.barrel_origin_world()
	_draw_barrel_indicator(barrel)
	if charging:
		draw_rect(bounds, Color(0.3, 0.5, 1.0, 0.3))
		_draw_charge_preview(barrel)

func _draw_barrel_indicator(barrel: Vector2) -> void:
	var dir := aim_dir()
	var tip := barrel + dir * (2.5 * Const.VOXEL_SIZE)
	draw_line(barrel, tip, Color(1, 1, 1, 0.9), 2.0)
	# Small arrowhead so the direction reads at a glance.
	var n := dir.orthogonal() * 3.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip + n, tip - n]),
			Color(1, 1, 1, 0.9))

func _draw_charge_preview(barrel: Vector2) -> void:
	var speed := lerpf(Const.MIN_PROJECTILE_SPEED, Const.MAX_PROJECTILE_SPEED, power_frac)
	var sim := Trajectory.simulate_arc(terrain, barrel, aim_dir(), speed)
	var points : PackedVector2Array = sim["points"]
	# Dotted ghost arc: every 3rd physics-step point.
	for i in range(0, points.size(), 3):
		draw_circle(points[i], 2.0, Color(1, 1, 1, 0.65))
	if sim["hit"]:
		_draw_aoe_footprint(sim["impact_voxel"])

# AoE diamond at the predicted landing voxel (terrain spec §8.4).
func _draw_aoe_footprint(center: Vector2i) -> void:
	var vs := float(Const.VOXEL_SIZE)
	for vox in terrain.get_tiles_in_diamond(center.x, center.y, Const.AOE_RADIUS):
		var rect := Rect2(Const.voxel_to_world(vox), Vector2(vs, vs))
		if _is_unit_voxel(vox):
			draw_rect(rect, Color(1.0, 0.45, 0.1, 0.7))   # unit voxel in blast
		else:
			draw_rect(rect, Color(1.0, 0.15, 0.15, 0.4))
	var c := Const.voxel_center_world(center)
	draw_line(c + Vector2(-vs * 0.4, 0), c + Vector2(vs * 0.4, 0), Color.WHITE, 1.5)
	draw_line(c + Vector2(0, -vs * 0.4), c + Vector2(0, vs * 0.4), Color.WHITE, 1.5)

func _is_unit_voxel(vox: Vector2i) -> bool:
	return vox.x >= unit.origin_vox.x and vox.x < unit.origin_vox.x + PlayerUnit.WIDTH_VOX \
		and vox.y >= unit.origin_vox.y and vox.y < unit.origin_vox.y + PlayerUnit.HEIGHT_VOX
