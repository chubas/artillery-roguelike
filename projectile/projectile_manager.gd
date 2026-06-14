# Spawns and tracks projectiles; runs the shot RESOLUTION ROUTINE on impact (M2 §6.1).
#
# A shot is not "done" the instant it hits — its consequences play out as an ordered
# resolution routine (AoE damage, explosion FX, and later death animations, terrain collapse,
# knockback, …), capped by a short settle beat. `shot_resolved` fires only when that whole
# routine finishes, and `is_busy()` stays true throughout — so the camera waits to focus the
# next unit and enemies wait to fire until everything has settled.
class_name ProjectileManager
extends Node2D

signal shot_resolved(is_enemy: bool)

var _terrain : TerrainManager
var _units_provider : Callable   # returns Array[Unit]; set by CombatScene
var _active : Projectile = null
var _resolving : int = 0         # shots whose resolution routine is mid-flight

func setup(terrain: TerrainManager, units_provider: Callable) -> void:
	_terrain = terrain
	_units_provider = units_provider

func fire(origin: Vector2, direction: Vector2, speed: float,
		shot: ShotDefinition, is_enemy: bool) -> Projectile:
	var p := Projectile.new()
	add_child(p)
	p.launch(origin, direction, speed, shot.gravity_scale, _terrain)
	p.impact.connect(_on_impact.bind(shot.aoe_pattern, is_enemy))
	_active = p
	return p

# The projectile currently in flight, or null; camera follows it.
func active_projectile() -> Projectile:
	if _active != null and is_instance_valid(_active):
		return _active
	return null

func has_active() -> bool:
	for c in get_children():
		if c is Projectile and c.is_active():
			return true
	return false

# True while any shot is in flight OR its resolution routine (incl. settle beat) is running.
# Callers that must wait for a shot to FULLY finish should poll this, not has_active().
func is_busy() -> bool:
	return _resolving > 0 or has_active()

# --- Shot resolution routine ------------------------------------------------------
# Async: runs the ordered list of resolve actions, then a settle beat, then signals done.
# This is the pluggable seam — new consequences of a shot are inserted as steps here.
func _on_impact(world_pos: Vector2, impact_voxel: Vector2i,
		pattern: AoEPattern, is_enemy: bool) -> void:
	_resolving += 1
	var element_id := "physical"
	if Features.elements_enabled and not pattern.groups.is_empty() \
			and pattern.groups[0].element != null:
		element_id = pattern.groups[0].element.id
	EventBus.projectile_impact.emit(world_pos, impact_voxel, element_id)

	# 1. Area damage to terrain + units (and element statuses).
	AoEResolver.resolve(_terrain, _units_provider.call(), impact_voxel, pattern, is_enemy)
	# 2. Explosion FX.
	var fx := ExplosionFX.new()
	fx.position = world_pos
	add_child(fx)
	# 3. POST-M3 resolve actions slot in here (death animations, terrain collapse, knockback…).
	# 4. Settle beat — let the consequences read before play continues.
	await get_tree().create_timer(Const.SHOT_RESOLVE_DELAY).timeout

	_resolving -= 1
	shot_resolved.emit(is_enemy)
