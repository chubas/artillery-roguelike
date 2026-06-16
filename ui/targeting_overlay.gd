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

# M5: card targeting + reinforcement countdown state, pushed each frame by CombatManager.
var pending_card : CardDefinition = null
var pending_reinforcements : Array = []   # [{ "col": int, "turns_left": int }]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Hover hitbox outline on any unit (terrain spec §11.4).
	var mouse := get_global_mouse_position()
	for u in units:
		if u.bounds_rect_world().has_point(mouse):
			draw_rect(u.bounds_rect_world(), Color(1, 1, 1, 0.9), false, 1.0)
	_draw_reinforcement_warnings()
	if pending_card != null:
		_draw_card_targets()
	if active_unit == null or active_unit.hp <= 0:
		return
	var barrel := active_unit.barrel_origin_world()
	_draw_barrel_indicator(barrel, active_unit.aim_dir())
	if charging:
		_draw_charge_preview(barrel)

# Highlight valid targets for the pending card: green outline for allies, red for enemies.
func _draw_card_targets() -> void:
	var want_ally := pending_card.target_type == CardDefinition.TargetType.ALLY
	var col := Color(0.3, 0.95, 0.4, 0.9) if want_ally else Color(0.95, 0.3, 0.25, 0.9)
	for u in units:
		if u.hp > 0 and u.is_player == want_ally:
			draw_rect(u.bounds_rect_world(), col, false, 2.0)

# Telegraphed reinforcement drops: a faint vertical guide line down the landing column,
# capped with a downward-pointing arrow and a turns-remaining number near the top.
func _draw_reinforcement_warnings() -> void:
	for w in pending_reinforcements:
		var x := Const.voxel_to_world(Vector2i(w["col"], 0)).x + Const.VOXEL_SIZE * 0.5
		var top_y := 24.0
		var bottom_y := float(Const.MAP_HEIGHT * Const.VOXEL_SIZE)
		draw_line(Vector2(x, top_y), Vector2(x, bottom_y), Color(1.0, 0.25, 0.2, 0.18), 2.0)
		var pts := PackedVector2Array([
			Vector2(x, top_y + 14), Vector2(x - 6, top_y), Vector2(x + 6, top_y)])
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.25, 0.85))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(x + 8, top_y + 12), str(w["turns_left"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

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
	if shot.bypass_terrain:
		_draw_bypass_preview(barrel, shot, speed)
	elif shot.projectile_count > 1:
		_draw_cluster_preview(barrel, shot, speed)
	else:
		_draw_single_preview(barrel, shot, speed)

func _draw_single_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale)
	_draw_arc_dots(sim["points"], 3)
	if sim["hit"]:
		_draw_pattern_footprint(sim["impact_voxel"], shot.aoe_pattern)

# Cluster: ghost every pellet's arc so the player reads the fan and each footprint (M4).
func _draw_cluster_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var n := shot.projectile_count
	var mid := float(n - 1) * 0.5
	for i in range(n):
		var off_deg := (float(i) - mid) * shot.spread_deg
		var dir := active_unit.aim_dir().rotated(deg_to_rad(off_deg))
		var sim := Trajectory.simulate_arc(terrain, barrel, dir, speed, shot.gravity_scale)
		_draw_arc_dots(sim["points"], 4)
		if sim["hit"]:
			_draw_pattern_footprint(sim["impact_voxel"], shot.aoe_pattern)

# Bypass: the ghost flies through terrain; mark the first opposing unit it would strike (M4).
func _draw_bypass_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale, 8.0, true)
	var points : PackedVector2Array = sim["points"]
	_draw_arc_dots(points, 3)
	for p in points:
		var vox := Const.world_to_voxel(p)
		if _hits_damageable_unit(vox):
			_draw_pattern_footprint(vox, shot.aoe_pattern)
			return

func _draw_arc_dots(points: PackedVector2Array, stride: int) -> void:
	for i in range(0, points.size(), stride):
		draw_circle(points[i], 2.0, Color(1, 1, 1, 0.65))

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
