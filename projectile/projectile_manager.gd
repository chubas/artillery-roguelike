# Spawns and tracks projectiles; runs the shot RESOLUTION ROUTINE on impact (M2 §6.1, M4 §2).
#
# M4 — a shot is a SALVO: one logical shot may launch several bodies (a 5-pellet cluster, a
# main+2-arm spiral) or behave specially (a terrain-bypassing drill). All of them resolve
# through one ordered pipeline:
#
#   • Each body that contacts terrain PAUSES and reports its impact (it is not freed).
#   • Impacts are drained in collision order — (physics_frame, salvo index) — one at a time.
#     Before resolving each, the manager RE-CHECKS the voxel: if an earlier impact this drain
#     already destroyed it, the paused body is RESUMED instead and flies on through the gap.
#   • A resolved impact applies AoE damage, spawns the explosion FX, and runs post-impact
#     resolve actions (gravity pull, …) at the pluggable seam.
#   • When every body in a salvo has resolved or left the map, ONE settle beat plays, then
#     `shot_resolved(is_enemy)` fires. `is_busy()` stays true for the whole salvo lifetime,
#     so the camera and the enemy turn wait for the full thing to finish.
class_name ProjectileManager
extends Node2D

signal shot_resolved(is_enemy: bool)

# One logical shot and all the bodies it launched.
class Salvo extends RefCounted:
	var is_enemy : bool = false
	var shot : ShotDefinition = null
	var pattern : AoEPattern = null
	var members : Array = []     # live Projectile / SpiralSatellite nodes
	var pending : Array = []     # queued impacts: {node, world_pos, voxel, frame, index, force}
	var settling : bool = false  # settle-beat coroutine running → don't re-enter

var _terrain : TerrainManager
var _units_provider : Callable   # returns Array[Unit]; set by CombatScene
var _salvos : Array = []

func setup(terrain: TerrainManager, units_provider: Callable) -> void:
	_terrain = terrain
	_units_provider = units_provider

# --- Firing entry point (unchanged signature; branches on the shot's M4 payload) ----
func fire(origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition, is_enemy: bool) -> void:
	var salvo := Salvo.new()
	salvo.is_enemy = is_enemy
	salvo.shot = shot
	salvo.pattern = shot.aoe_pattern
	_salvos.append(salvo)
	if shot.spiral_arms > 0:
		_spawn_spiral(salvo, origin, direction, speed, shot)
	elif shot.projectile_count > 1:
		_spawn_cluster(salvo, origin, direction, speed, shot)
	else:
		_spawn_projectile(salvo, origin, direction, speed, shot, 0, shot.bypass_terrain)

func _spawn_projectile(salvo: Salvo, origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition, index: int, bypass: bool) -> void:
	var p := Projectile.new()
	add_child(p)
	p.launch(origin, direction, speed, shot.gravity_scale, _terrain, self, salvo, index, bypass)
	salvo.members.append(p)

func _spawn_cluster(salvo: Salvo, origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition) -> void:
	# Fan N pellets symmetrically about the aim direction, spread_deg between neighbours.
	var n := shot.projectile_count
	var mid := float(n - 1) * 0.5
	for i in range(n):
		var off_deg := (float(i) - mid) * shot.spread_deg
		var dir := direction.rotated(deg_to_rad(off_deg))
		_spawn_projectile(salvo, origin, dir, speed, shot, i, false)

func _spawn_spiral(salvo: Salvo, origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition) -> void:
	# Main guide projectile (index 0) + oscillating arms riding it.
	var main := Projectile.new()
	add_child(main)
	main.launch(origin, direction, speed, shot.gravity_scale, _terrain, self, salvo, 0, false)
	salvo.members.append(main)
	for arm in range(shot.spiral_arms):
		var sat := SpiralSatellite.new()
		add_child(sat)
		var sign_ := 1.0 if arm % 2 == 0 else -1.0
		sat.setup(main, _terrain, self, salvo, arm + 1, sign_,
				shot.spiral_amplitude, shot.spiral_frequency)
		salvo.members.append(sat)

# --- Body callbacks ---------------------------------------------------------------
# A body hit something and paused; queue its impact for ordered resolution.
func report_impact(salvo: RefCounted, node: Node2D, world_pos: Vector2,
		voxel: Vector2i, force_resolve: bool) -> void:
	salvo.pending.append({
		"node": node, "world_pos": world_pos, "voxel": voxel,
		"frame": Engine.get_physics_frames(), "index": node.proj_index,
		"force": force_resolve,
	})

# A body left the map (or lost its guide) without an impact: retire it.
func report_despawn(salvo: RefCounted, node: Node2D) -> void:
	salvo.members.erase(node)
	node.queue_free()

# --- Camera / busy queries --------------------------------------------------------
# The body the camera should follow: the first live real projectile (arms ride it anyway).
func active_projectile() -> Projectile:
	for s in _salvos:
		for m in s.members:
			if m is Projectile and is_instance_valid(m) and m.is_active():
				return m
	return null

func has_active() -> bool:
	for s in _salvos:
		for m in s.members:
			if is_instance_valid(m) and m.is_active():
				return true
	return false

# True from launch until the salvo's settle beat ends. Callers that must wait for a shot to
# FULLY finish (camera advance, enemy sequencing) poll this.
func is_busy() -> bool:
	return not _salvos.is_empty()

# Total live bodies across all salvos (smoke-test introspection).
func debug_member_count() -> int:
	var n := 0
	for s in _salvos:
		n += s.members.size()
	return n

# --- Per-frame salvo processing ---------------------------------------------------
# Runs BEFORE child bodies' _physics_process (tree order), so `pending` only ever holds
# impacts from strictly-earlier frames — no frame is half-collected when we drain.
func _physics_process(_delta: float) -> void:
	_check_bypass_unit_hits()
	for s in _salvos:
		if not s.pending.is_empty():
			_drain_salvo(s)
	# Finish salvos whose bodies are all gone (resolved or despawned).
	for s in _salvos.duplicate():
		if not s.settling and s.members.is_empty() and s.pending.is_empty():
			_finish_salvo(s)

# Bypass drills don't stop on terrain — they stop when they overlap an OPPOSING unit.
func _check_bypass_unit_hits() -> void:
	for s in _salvos:
		for m in s.members:
			if m is Projectile and m.bypass_mode and m.is_active():
				var u := _opponent_overlapping(m.position, s.is_enemy)
				if u != null:
					m._active = false
					# Force resolve: the unit-hit explosion fires in open air, not on terrain.
					report_impact(s, m, m.position, Const.world_to_voxel(m.position), true)

func _opponent_overlapping(world_pos: Vector2, is_enemy: bool) -> Unit:
	var vox := Const.world_to_voxel(world_pos)
	for u in _units_provider.call():
		if u.hp <= 0:
			continue
		var is_opponent : bool = u.is_player if is_enemy else not u.is_player
		if is_opponent and u.contains_voxel(vox):
			return u
	return null

# Resolve this salvo's queued impacts in collision order, re-checking terrain between each so
# a pellet that finds its blocker already gone flies on instead of detonating in the gap.
func _drain_salvo(salvo: Salvo) -> void:
	var items := salvo.pending
	salvo.pending = []
	items.sort_custom(func(a, b):
		if a["frame"] != b["frame"]:
			return a["frame"] < b["frame"]
		return a["index"] < b["index"])
	for it in items:
		var node : Node2D = it["node"]
		if not is_instance_valid(node):
			continue
		var vox : Vector2i = it["voxel"]
		if it["force"] or _terrain.is_blocked(vox.x, vox.y):
			_resolve_impact(salvo, it["world_pos"], vox)
			salvo.members.erase(node)
			node.queue_free()
		else:
			node.resume()   # blocker cleared by an earlier impact this drain → fly on

# One impact's consequences. THIS is the pluggable seam — new resolve actions are added here.
func _resolve_impact(salvo: Salvo, world_pos: Vector2, voxel: Vector2i) -> void:
	var pattern := salvo.pattern
	var element_id := "physical"
	if Features.elements_enabled and pattern != null and not pattern.groups.is_empty() \
			and pattern.groups[0].element != null:
		element_id = pattern.groups[0].element.id
	EventBus.projectile_impact.emit(world_pos, voxel, element_id)
	# 1. Area damage to terrain + units (and element statuses).
	AoEResolver.resolve(_terrain, _units_provider.call(), voxel, pattern, salvo.is_enemy)
	# 2. Explosion FX.
	var fx := ExplosionFX.new()
	fx.position = world_pos
	add_child(fx)
	# 3. Gravity pull — drag nearby units toward the impact (M4). Other post-impact resolve
	#    actions (death animations, terrain collapse, knockback…) slot in alongside this.
	if salvo.shot != null and salvo.shot.pull_far_radius > 0:
		GravityPullResolver.resolve(_terrain, _units_provider.call(), voxel, salvo.shot)
	# (The salvo-wide settle beat happens once in _finish_salvo, not per impact.)

func _finish_salvo(salvo: Salvo) -> void:
	salvo.settling = true
	await get_tree().create_timer(Const.SHOT_RESOLVE_DELAY).timeout
	_salvos.erase(salvo)
	shot_resolved.emit(salvo.is_enemy)
