# Point projectile: ballistic arc + DDA face-contact collision (terrain spec §9).
#
# M4: a projectile belongs to a SALVO (one logical shot may launch several bodies — cluster,
# spiral). On terrain contact it does NOT free itself; it PAUSES and reports the impact to its
# ProjectileManager, which resolves impacts in collision order and may RESUME this projectile
# if an earlier impact in the same salvo cleared the blocking voxel (so a later pellet flies on
# through the hole the first one punched). Bypass projectiles skip terrain collision entirely,
# damaging the centre-voxel trail and stopping only on an opposing unit (checked by the manager).
class_name Projectile
extends Node2D

var velocity : Vector2 = Vector2.ZERO
var gravity_scale : float = 1.0
var wind_force_x : float = 0.0     # M8: horizontal acceleration (px/s²) from wind
var flight_time : float = 0.0      # M9: seconds in flight, for modify_projectile_strength
var proj_index : int = 0            # order within the salvo (tie-breaks same-frame impacts)
var bypass_mode : bool = false      # drill: ignore terrain, damage trail, stop on units

var _terrain : TerrainManager
var _manager : ProjectileManager
var _salvo : RefCounted             # ProjectileManager.Salvo — opaque back-reference
var _active : bool = false
var _bypass_hit : Dictionary = {}   # Vector2i → true: trail voxels already damaged once
var _split_done : bool = false
var _barrier_hit : Dictionary = {}  # void voxels already walled this flight

func launch(origin: Vector2, direction: Vector2, speed: float, gscale: float,
		terrain: TerrainManager, manager: ProjectileManager, salvo: RefCounted,
		index: int, bypass: bool, wind_x: float = 0.0) -> void:
	position = origin
	velocity = direction.normalized() * speed
	gravity_scale = gscale
	wind_force_x = wind_x
	_terrain = terrain
	_manager = manager
	_salvo = salvo
	proj_index = index
	bypass_mode = bypass
	_active = true

func is_active() -> bool:
	return _active

# Re-armed by the manager when an earlier salvo impact cleared this projectile's blocker.
func resume() -> void:
	_active = true

func _physics_process(delta: float) -> void:
	if not _active:
		return
	flight_time += delta
	var shot : ShotDefinition = _salvo.shot
	if shot != null and shot.behavior == ShotDefinition.ShotBehavior.SPLIT \
			and not _split_done and flight_time >= shot.split_delay_sec:
		_split_done = true
		_active = false
		_manager.spawn_split_from(_salvo, self, position, velocity.normalized(),
				velocity.length())
		_manager.report_despawn(_salvo, self)
		return
	velocity.y += Const.GRAVITY * gravity_scale * delta
	velocity.x += wind_force_x * delta
	var new_pos := position + velocity * delta
	if shot != null and shot.behavior == ShotDefinition.ShotBehavior.BARRIER \
			and flight_time >= shot.barrier_delay_sec:
		_place_barrier_segment(position, new_pos, shot.barrier_tile_hp)
	if bypass_mode:
		_damage_trail(position, new_pos)
		position = new_pos
		# Unit hit is detected by the manager (it owns the unit list); terrain never stops us.
		if _out_of_bounds():
			_active = false
			_manager.report_despawn(_salvo, self)
		return
	# Shared with the charge preview (Trajectory) so the ghost arc never lies.
	var hit := Trajectory.check_segment(_terrain, position, new_pos)
	if hit["collided"]:
		_active = false   # pause — manager decides resolve vs resume; it frees us on resolve.
		_manager.report_impact(_salvo, self, hit["contact_point"], hit["impact_voxel"], false)
		return
	position = new_pos
	if _out_of_bounds():
		_active = false
		_manager.report_despawn(_salvo, self)

# Bypass trail: 1 damage to every unique voxel the centre passes through this step.
func _damage_trail(from: Vector2, to: Vector2) -> void:
	var steps := int(from.distance_to(to) / (Const.VOXEL_SIZE * 0.5)) + 1
	for i in range(steps + 1):
		var pt := from.lerp(to, float(i) / steps)
		var vox := Const.world_to_voxel(pt)
		if not _bypass_hit.has(vox):
			_bypass_hit[vox] = true
			_terrain.damage_tile(vox.x, vox.y, 1)

# Barrier trail: fill void voxels with fragile solid tiles (no damage on impact).
func _place_barrier_segment(from: Vector2, to: Vector2, tile_hp: int) -> void:
	var steps := int(from.distance_to(to) / (Const.VOXEL_SIZE * 0.5)) + 1
	for i in range(steps + 1):
		var pt := from.lerp(to, float(i) / steps)
		var vox := Const.world_to_voxel(pt)
		if _barrier_hit.has(vox):
			continue
		_barrier_hit[vox] = true
		if _terrain.get_tile(vox.x, vox.y) != null:
			continue
		_terrain.set_tile(vox.x, vox.y,
				Tile.new().setup(Tile.TileType.SOLID, tile_hp, 0))

func _out_of_bounds() -> bool:
	var w := Const.world_pixel_size()
	# Arcs may exit the top and return, so only sides + bottom despawn.
	return position.x < 0 or position.x > w.x or position.y > w.y

func _draw() -> void:
	var c := Color(0.5, 0.85, 1.0) if bypass_mode else Color(1.0, 0.9, 0.3)
	var r := 4.0
	if _salvo != null and _salvo.shot != null:
		r = _salvo.shot.projectile_draw_radius
	draw_circle(Vector2.ZERO, r, c)
