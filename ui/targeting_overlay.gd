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

# M15: spawn-zone highlight during pre-combat placement.
var placement_active : bool = false
var placement_min_col : int = 0
var placement_max_col : int = 0
# Drop indicator: vertical line + unit name, shown while the player hovers to place a unit.
var drop_indicator_col : int = -1
var drop_indicator_name : String = ""

var _wind_force_x : float = 0.0   # M8: cached from EventBus.wind_changed; applied to arc preview

func _ready() -> void:
	EventBus.wind_changed.connect(func(s: float) -> void:
		_wind_force_x = s * Const.MAX_WIND_FORCE)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if placement_active:
		_draw_spawn_zone()
		if drop_indicator_col >= 0:
			_draw_drop_indicator()
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

# M15: translucent band over the placement spawn zone (full map height), with a top edge line.
func _draw_spawn_zone() -> void:
	var x0 := Const.voxel_to_world(Vector2i(placement_min_col, 0)).x
	var x1 := Const.voxel_to_world(Vector2i(placement_max_col + 1, 0)).x
	var h := float(Const.MAP_HEIGHT * Const.VOXEL_SIZE)
	var rect := Rect2(x0, 0.0, x1 - x0, h)
	draw_rect(rect, Color(0.3, 0.7, 1.0, 0.10))
	draw_line(Vector2(x1, 0.0), Vector2(x1, h), Color(0.4, 0.75, 1.0, 0.45), 2.0)

func set_drop_indicator(col: int, name: String) -> void:
	drop_indicator_col = col
	drop_indicator_name = name

func _draw_drop_indicator() -> void:
	var x := Const.voxel_to_world(Vector2i(drop_indicator_col, 0)).x + Const.VOXEL_SIZE * 0.5
	var h := float(Const.MAP_HEIGHT * Const.VOXEL_SIZE)
	draw_line(Vector2(x, 0.0), Vector2(x, h), Color.WHITE, 2.0)
	if drop_indicator_name != "":
		var font := ThemeDB.fallback_font
		var font_size := 14
		var tw := font.get_string_size(drop_indicator_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(x - tw * 0.5, 40.0), drop_indicator_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

# Highlight valid targets for the pending card: green outline for allies, red for enemies,
# or (TILE cards, M11) a column guide + surface marker at the space under the cursor.
func _draw_card_targets() -> void:
	if pending_card.target_type == CardDefinition.TargetType.TILE:
		_draw_tile_target()
		return
	var want_ally := pending_card.target_type == CardDefinition.TargetType.ALLY
	var col := Color(0.3, 0.95, 0.4, 0.9) if want_ally else Color(0.95, 0.3, 0.25, 0.9)
	for u in units:
		if u.hp > 0 and u.is_player == want_ally:
			draw_rect(u.bounds_rect_world(), col, false, 2.0)

func _draw_tile_target() -> void:
	var c := Const.world_to_voxel(get_global_mouse_position()).x
	if c < 0 or c >= Const.MAP_WIDTH:
		return
	var surface := terrain.get_surface_row(c)
	if surface == -1:
		return
	var x := Const.voxel_to_world(Vector2i(c, 0)).x + Const.VOXEL_SIZE * 0.5
	var sy := Const.voxel_to_world(Vector2i(c, surface)).y
	var col := Color(1.0, 0.7, 0.2, 0.85)
	draw_line(Vector2(x, 24.0), Vector2(x, sy), col * Color(1, 1, 1, 0.4), 2.0)
	# Surface marker box on the cell where the mine would land.
	draw_rect(Rect2(Const.voxel_to_world(Vector2i(c, surface)), Vector2(Const.VOXEL_SIZE, Const.VOXEL_SIZE)),
			col, false, 2.0)

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
	elif shot.behavior == ShotDefinition.ShotBehavior.BARRIER:
		_draw_barrier_preview(barrel, shot, speed)
	elif shot.behavior == ShotDefinition.ShotBehavior.TELEPORT:
		_draw_teleport_preview(barrel, shot, speed)
	else:
		_draw_single_preview(barrel, shot, speed)

func _draw_single_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale, 8.0, false, _wind_force_x)
	_draw_arc_dots(sim["points"], 3)
	if sim["hit"] and shot.aoe_pattern != null:
		_draw_pattern_footprint(sim["impact_voxel"], shot)

func _draw_barrier_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale, 8.0, false, _wind_force_x)
	_draw_arc_dots(sim["points"], 3)

func _draw_teleport_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale, 8.0, false, _wind_force_x)
	_draw_arc_dots(sim["points"], 3)
	if not sim["hit"]:
		return
	var def := active_unit.definition
	var impact : Vector2i = sim["impact_voxel"]
	var top_left := Vector2i(impact.x - def.width_voxels / 2, impact.y - def.height_voxels)
	top_left = UnitMovement.settle_at(top_left, def.width_voxels, def.height_voxels, terrain)
	var vs := float(Const.VOXEL_SIZE)
	var rect := Rect2(Const.voxel_to_world(top_left), Vector2(def.width_voxels, def.height_voxels) * vs)
	draw_rect(rect, Color(0.7, 0.45, 0.95, 0.35))
	draw_rect(rect, Color(0.85, 0.55, 1.0, 0.85), false, 1.5)

# Cluster: ghost every pellet's arc so the player reads the fan and each footprint (M4).
func _draw_cluster_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var n := shot.projectile_count
	var mid := float(n - 1) * 0.5
	for i in range(n):
		var off_deg := (float(i) - mid) * shot.spread_deg
		var dir := active_unit.aim_dir().rotated(deg_to_rad(off_deg))
		var sim := Trajectory.simulate_arc(terrain, barrel, dir, speed, shot.gravity_scale,
				8.0, false, _wind_force_x)
		_draw_arc_dots(sim["points"], 4)
		if sim["hit"]:
			_draw_pattern_footprint(sim["impact_voxel"], shot)

# Bypass: the ghost flies through terrain; mark the first opposing unit it would strike (M4).
func _draw_bypass_preview(barrel: Vector2, shot: ShotDefinition, speed: float) -> void:
	var sim := Trajectory.simulate_arc(terrain, barrel, active_unit.aim_dir(),
			speed, shot.gravity_scale, 8.0, true, _wind_force_x)
	var points : PackedVector2Array = sim["points"]
	_draw_arc_dots(points, 3)
	for p in points:
		var vox := Const.world_to_voxel(p)
		if _hits_damageable_unit(vox):
			_draw_pattern_footprint(vox, shot)
			return

func _draw_arc_dots(points: PackedVector2Array, stride: int) -> void:
	for i in range(0, points.size(), stride):
		draw_circle(points[i], 2.0, Color(1, 1, 1, 0.65))

func _draw_pattern_footprint(center: Vector2i, shot: ShotDefinition) -> void:
	var pattern := shot.aoe_pattern
	if pattern == null:
		return
	var vs := float(Const.VOXEL_SIZE)
	var aoe_map := pattern.to_map()
	for offset in aoe_map:
		var vox : Vector2i = center + offset
		var rect := Rect2(Const.voxel_to_world(vox), Vector2(vs, vs))
		if _hits_damageable_unit(vox):
			draw_rect(rect, Color(1.0, 0.45, 0.1, 0.75))   # unit voxel in blast
		else:
			var group : AoEGroup = aoe_map[offset]
			# Discrete zone fill (M7): core/edge color, never a continuous gradient — the
			# player reads strength tier, not an exact number (design doc §2.3).
			var base := AoEPattern.zone_color(group.multiplier)
			base.a = 0.55
			draw_rect(rect, base)
	# M16: dig overlay on terrain footprint (skipped for bypass — trail is the terrain interaction).
	if not shot.bypass_terrain:
		var dig_pat := shot.dig_pattern if shot.dig_pattern != null else pattern
		_draw_dig_footprint(center, dig_pat)
	var c := Const.voxel_center_world(center)
	draw_line(c + Vector2(-vs * 0.4, 0), c + Vector2(vs * 0.4, 0), Color.WHITE, 1.5)
	draw_line(c + Vector2(0, -vs * 0.4), c + Vector2(0, vs * 0.4), Color.WHITE, 1.5)

func _draw_dig_footprint(center: Vector2i, dig_pattern: AoEPattern) -> void:
	var vs := float(Const.VOXEL_SIZE)
	var dig_map := dig_pattern.to_map()
	for offset in dig_map:
		var vox : Vector2i = center + offset
		var rect := Rect2(Const.voxel_to_world(vox), Vector2(vs, vs))
		draw_rect(rect, Color(1.0, 0.95, 0.75, 0.22))
		draw_rect(rect, Color(0.85, 0.70, 0.35, 0.85), false, 1.5)

func _hits_damageable_unit(vox: Vector2i) -> bool:
	# Player shots damage only enemies (friendly fire off in M2).
	for u in units:
		if u.hp > 0 and not u.is_player and u.contains_voxel(vox):
			return true
	return false
