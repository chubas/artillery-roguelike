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
	var strength : int = 0   # unit.attack * shot.strength_mult * power + modifier, at fire time (M10)
	var dig_strength : int = 0   # unit.dig * shot.dig_mult + dig_modifier; 0 = skip dig pass (M16)
	var firing_unit : Unit = null   # M9: for on_unit_killed killer reference
	var element_overrides : Array[ElementDef] = []   # M30: captured from firing_unit.primed_elements
	var members : Array = []     # live Projectile / SpiralSatellite nodes
	var pending : Array = []     # queued impacts: {node, world_pos, voxel, frame, index, force}
	var settling : bool = false  # settle-beat coroutine running → don't re-enter

var _terrain : TerrainManager
var _units_provider : Callable   # returns Array[Unit]; set by CombatScene
var _deployables_provider : Callable = func(): return []   # returns Array[Deployable] (M6)
var _salvos : Array = []
var current_wind_force : float = 0.0   # M8: px/s² horizontal; set by CombatManager each round
var _combat : Node = null   # M9: CombatManager ref for artifact hooks; set by CombatManager

func setup(terrain: TerrainManager, units_provider: Callable,
		deployables_provider: Callable = func(): return []) -> void:
	_terrain = terrain
	_units_provider = units_provider
	_deployables_provider = deployables_provider

# --- Firing entry point (unchanged signature; branches on the shot's M4 payload) ----
func fire(origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition, is_enemy: bool, firing_unit: Unit = null) -> void:
	var salvo := Salvo.new()
	salvo.is_enemy = is_enemy
	salvo.shot = shot
	salvo.pattern = shot.aoe_pattern
	salvo.firing_unit = firing_unit
	if firing_unit != null and not firing_unit.primed_elements.is_empty():
		salvo.element_overrides = firing_unit.primed_elements.duplicate()
		firing_unit.primed_elements.clear()
		firing_unit.queue_redraw()
	# M10: strength derives from the firing unit's attack value, scaled by the shot's relative
	# multiplier and the unit's power, plus any flat attack_modifier (M9 debuffs). Clamped ≥ 0.
	var atk : int = firing_unit.attack if firing_unit != null else 3
	var pow : float = firing_unit.power if firing_unit != null else 1.0
	var modifier : int = firing_unit.attack_modifier if firing_unit != null else 0
	salvo.strength = maxi(0, roundi(atk * shot.strength_mult * pow) + modifier)
	# M16: flat dig strength for terrain only; bypass drills opt out entirely.
	if shot.bypass_terrain:
		salvo.dig_strength = 0
	else:
		var dig : int = firing_unit.dig if firing_unit != null else 1
		var dig_mod : int = firing_unit.dig_modifier if firing_unit != null else 0
		salvo.dig_strength = maxi(0, roundi(dig * shot.dig_mult) + dig_mod)
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
	p.launch(origin, direction, speed, shot.gravity_scale, _terrain, self, salvo, index, bypass,
			current_wind_force)
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
	main.launch(origin, direction, speed, shot.gravity_scale, _terrain, self, salvo, 0, false,
			current_wind_force)
	salvo.members.append(main)
	for arm in range(shot.spiral_arms):
		var sat := SpiralSatellite.new()
		add_child(sat)
		var sign_ := 1.0 if arm % 2 == 0 else -1.0
		sat.setup(main, _terrain, self, salvo, arm + 1, sign_,
				shot.spiral_amplitude, shot.spiral_frequency)
		salvo.members.append(sat)

func spawn_split_from(salvo: Salvo, _node: Projectile, origin: Vector2, direction: Vector2,
		speed: float) -> void:
	var shot := salvo.shot
	var n := shot.split_count
	var half := shot.split_spread_deg
	for i in range(n):
		var t := float(i) / maxf(float(n - 1), 1.0)
		var off_deg := lerpf(-half, half, t)
		var dir := direction.rotated(deg_to_rad(off_deg))
		_spawn_projectile(salvo, origin, dir, speed, shot, 100 + i, false)

func _spawn_walker(salvo: Salvo, impact_voxel: Vector2i) -> void:
	# Away from the player side: player (left) → +X, enemy (right) → −X.
	var dir := -1 if salvo.is_enemy else 1
	var w := WalkerCrawler.new()
	add_child(w)
	w.setup(_terrain, self, salvo, _units_provider, impact_voxel, dir,
			salvo.shot.walker_max_steps, salvo.is_enemy, salvo.shot.walker_crawl_speed)
	salvo.members.append(w)

func _try_teleport(salvo: Salvo, impact_voxel: Vector2i) -> bool:
	var unit : Unit = salvo.firing_unit
	if unit == null or not is_instance_valid(unit):
		print("[teleport] failed: no firing unit")
		return false
	var def := unit.definition
	var w := def.width_voxels
	var h := def.height_voxels
	var top_left := Vector2i(impact_voxel.x - w / 2, impact_voxel.y - h)
	top_left = UnitMovement.settle_at(top_left, w, h, _terrain)
	if top_left.x < 0 or top_left.x + w > Const.MAP_WIDTH:
		print("[teleport] failed: out of bounds at %s" % impact_voxel)
		return false
	if not UnitMovement.bbox_terrain_clear(_terrain, top_left, w, h):
		print("[teleport] failed: terrain blocked at %s" % top_left)
		return false
	var foot := top_left.y + h - 1
	if not UnitMovement.grounded(_terrain, top_left.x, foot, w):
		print("[teleport] failed: not grounded at %s" % top_left)
		return false
	if UnitMovement.overlaps_any_unit(_units_provider.call(), top_left, def, unit):
		print("[teleport] failed: unit overlap at %s" % top_left)
		return false
	unit.set_vox_position(top_left)
	return true

func resolve_walker_explosion(salvo: Salvo, world_pos: Vector2, voxel: Vector2i) -> void:
	_resolve_blast(salvo, world_pos, voxel, 0.0)

# --- Body callbacks ---------------------------------------------------------------
# A body hit something and paused; queue its impact for ordered resolution.
func report_impact(salvo: RefCounted, node: Node2D, world_pos: Vector2,
		voxel: Vector2i, force_resolve: bool) -> void:
	var ft : float = node.flight_time if node is Projectile else 0.0
	salvo.pending.append({
		"node": node, "world_pos": world_pos, "voxel": voxel,
		"frame": Engine.get_physics_frames(), "index": node.proj_index,
		"force": force_resolve, "flight_time": ft,
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
			if is_instance_valid(m) and m.has_method("is_active") and m.is_active():
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
func check_flight_segment(from: Vector2, to: Vector2, salvo: RefCounted,
		ignore_terrain: bool = false) -> Dictionary:
	return Trajectory.check_segment(_terrain, from, to, _units_provider.call(),
			salvo.is_enemy, ignore_terrain)

func _physics_process(_delta: float) -> void:
	for s in _salvos:
		if not s.pending.is_empty():
			_drain_salvo(s)
	# Finish salvos whose bodies are all gone (resolved or despawned).
	for s in _salvos.duplicate():
		if not s.settling and s.members.is_empty() and s.pending.is_empty():
			_finish_salvo(s)

func _impact_blocker_present(salvo: Salvo, vox: Vector2i) -> bool:
	if _terrain.is_blocked(vox.x, vox.y):
		return true
	return Trajectory.opponent_at_voxel(vox, _units_provider.call(), salvo.is_enemy)

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
		var behavior := salvo.shot.behavior if salvo.shot != null \
				else ShotDefinition.ShotBehavior.STANDARD
		if it["force"] or _impact_blocker_present(salvo, vox):
			salvo.members.erase(node)
			node.queue_free()
			match behavior:
				ShotDefinition.ShotBehavior.BARRIER:
					pass   # trail only — no impact effect
				ShotDefinition.ShotBehavior.WALKER:
					_spawn_walker(salvo, vox)
				ShotDefinition.ShotBehavior.TELEPORT:
					if not _try_teleport(salvo, vox):
						pass   # wasted shot — debug logged in _try_teleport
				_:
					_resolve_impact(salvo, it["world_pos"], vox, it.get("flight_time", 0.0))
		else:
			node.resume()   # blocker cleared by an earlier impact this drain → fly on

# One impact's consequences. THIS is the pluggable seam — new resolve actions are added here.
func _resolve_impact(salvo: Salvo, world_pos: Vector2, voxel: Vector2i, flight_time: float = 0.0) -> void:
	_resolve_blast(salvo, world_pos, voxel, flight_time)

func _resolve_blast(salvo: Salvo, world_pos: Vector2, voxel: Vector2i,
		flight_time: float = 0.0) -> void:
	var pattern := salvo.pattern
	var eff_element : ElementDef = salvo.element_overrides[0] if not salvo.element_overrides.is_empty() \
			else (pattern.groups[0].element if Features.elements_enabled and pattern != null \
			and not pattern.groups.is_empty() else null)
	var element_id := eff_element.id if eff_element != null else "physical"
	EventBus.projectile_impact.emit(world_pos, voxel, element_id)
	# 1. Area damage to terrain + units (and element statuses).
	var final_strength : int = salvo.strength
	if _combat != null:
		var cm := _combat as CombatManager
		if cm != null and cm._artifact_ctx != null:
			final_strength = ArtifactSystem.apply_projectile_strength(
					cm.artifacts, cm._artifact_ctx, salvo.strength, flight_time)
	var deployables_ref : Array = _deployables_provider.call()
	var units_ref : Array = _units_provider.call()
	var dig_pat : AoEPattern = salvo.shot.dig_pattern if salvo.shot != null else null
	if salvo.element_overrides.is_empty():
		AoEResolver.resolve(_terrain, units_ref, voxel, pattern, final_strength,
				salvo.is_enemy, deployables_ref, salvo.dig_strength, dig_pat)
	else:
		for el in salvo.element_overrides:
			AoEResolver.resolve(_terrain, units_ref, voxel, pattern, final_strength,
					salvo.is_enemy, deployables_ref, salvo.dig_strength, dig_pat, el)
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
