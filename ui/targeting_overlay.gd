# World-space drawing child of TargetingUI (the CanvasLayer follows the viewport,
# so drawing here in world coordinates lines up with terrain).
# M2: aim state lives on the active Unit; the charge preview shows the shot's actual
# AoEPattern footprint (damage-gradient opacity) at the predicted impact voxel.
class_name TargetingOverlay
extends Node2D

var terrain : TerrainManager
var units : Array = []          # all units, for hover outlines + footprint highlight

var active_unit : Unit = null
var charging : bool = false
var power_frac : float = 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Hover hitbox outline on any unit (terrain spec §11.4).
	var mouse := get_global_mouse_position()
	for u in units:
		if u.bounds_rect_world().has_point(mouse):
			draw_rect(u.bounds_rect_world(), Color(1, 1, 1, 0.9), false, 1.0)
	if active_unit == null or active_unit.hp <= 0:
		return
	var barrel := active_unit.barrel_origin_world()
	_draw_barrel_indicator(barrel, active_unit.aim_dir())
	if charging:
		_draw_charge_preview(barrel)

func _draw_barrel_indicator(barrel: Vector2, dir: Vector2) -> void:
	var tip := barrel + dir * (2.5 * Const.VOXEL_SIZE)
	draw_line(barrel, tip, Color(1, 1, 1, 0.9), 2.0)
	var n := dir.orthogonal() * 3.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip + n, tip - n]),
			Color(1, 1, 1, 0.9))

func _draw_charge_preview(barrel: Vector2) -> void:
	var shot := active_unit.get_active_shot()
	var speed := lerpf(Const.MIN_PROJECTILE_SPEED,
			shot.base_speed * Const.PLAYER_POWER_MULT, power_frac)
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale)
	var points : PackedVector2Array = sim["points"]
	for i in range(0, points.size(), 3):
		draw_circle(points[i], 2.0, Color(1, 1, 1, 0.65))
	if sim["hit"]:
		_draw_pattern_footprint(sim["impact_voxel"], shot.aoe_pattern)

func _draw_pattern_footprint(center: Vector2i, pattern: AoEPattern) -> void:
	var vs := float(Const.VOXEL_SIZE)
	var aoe_map := pattern.to_map()
	var max_dmg := pattern.max_damage()
	for offset in aoe_map:
		var vox : Vector2i = center + offset
		var rect := Rect2(Const.voxel_to_world(vox), Vector2(vs, vs))
		if _hits_damageable_unit(vox):
			draw_rect(rect, Color(1.0, 0.45, 0.1, 0.75))   # unit voxel in blast
		else:
			var group : AoEGroup = aoe_map[offset]
			# Tint by element so the player reads the payload at a glance (M3).
			var base := Color(1.0, 0.15, 0.15)             # physical = red
			if group.element != null and Features.elements_enabled:
				match group.element.id:
					"fire": base = Color(1.0, 0.5, 0.1)    # orange
					"electric": base = Color(0.4, 0.7, 1.0) # blue
			# Damage gradient: stronger groups read as more opaque.
			base.a = 0.2 + 0.35 * float(group.damage) / max_dmg
			draw_rect(rect, base)
	var c := Const.voxel_center_world(center)
	draw_line(c + Vector2(-vs * 0.4, 0), c + Vector2(vs * 0.4, 0), Color.WHITE, 1.5)
	draw_line(c + Vector2(0, -vs * 0.4), c + Vector2(0, vs * 0.4), Color.WHITE, 1.5)

func _hits_damageable_unit(vox: Vector2i) -> bool:
	# Player shots damage only enemies (friendly fire off in M2).
	for u in units:
		if u.hp > 0 and not u.is_player and u.contains_voxel(vox):
			return true
	return false
