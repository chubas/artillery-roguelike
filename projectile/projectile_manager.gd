# Spawns and tracks projectiles; resolves their AoE on impact (M2 spec §6.1).
class_name ProjectileManager
extends Node2D

var _terrain : TerrainManager
var _units_provider : Callable   # returns Array[Unit]; set by CombatScene
var _active : Projectile = null

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

func _on_impact(world_pos: Vector2, impact_voxel: Vector2i,
		pattern: AoEPattern, is_enemy: bool) -> void:
	AoEResolver.resolve(_terrain, _units_provider.call(), impact_voxel, pattern, is_enemy)
	var fx := ExplosionFX.new()
	fx.position = world_pos
	add_child(fx)
