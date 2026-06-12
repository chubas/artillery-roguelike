# Spawns and tracks Projectile instances; spawns impact VFX (plan §2).
class_name ProjectileManager
extends Node2D

var _terrain : TerrainManager
var _active : Projectile = null

func setup(terrain: TerrainManager) -> void:
	_terrain = terrain

func fire(origin: Vector2, direction: Vector2,
		speed: float = Const.BASE_PROJECTILE_SPEED) -> Projectile:
	var p := Projectile.new()
	add_child(p)
	p.launch(origin, direction, speed, _terrain)
	p.impact.connect(_on_impact)
	_active = p
	return p

# The projectile currently in flight, or null; camera follows it.
func active_projectile() -> Projectile:
	if _active != null and is_instance_valid(_active):
		return _active
	return null

func _on_impact(world_pos: Vector2, _impact_voxel: Vector2i) -> void:
	var fx := ExplosionFX.new()
	fx.position = world_pos
	add_child(fx)
