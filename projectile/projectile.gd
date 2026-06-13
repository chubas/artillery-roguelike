# Point projectile: ballistic arc + DDA face-contact collision (terrain spec §9).
# M2: gravity_scale from ShotDefinition; AoE resolution moved to ProjectileManager.
class_name Projectile
extends Node2D

signal impact(world_pos: Vector2, impact_voxel: Vector2i)

var velocity : Vector2 = Vector2.ZERO
var gravity_scale : float = 1.0
var _terrain : TerrainManager
var _active : bool = false

func launch(origin: Vector2, direction: Vector2, speed: float,
		gscale: float, terrain: TerrainManager) -> void:
	position = origin
	velocity = direction.normalized() * speed
	gravity_scale = gscale
	_terrain = terrain
	_active = true

func is_active() -> bool:
	return _active

func _physics_process(delta: float) -> void:
	if not _active:
		return
	velocity.y += Const.GRAVITY * gravity_scale * delta
	var new_pos := position + velocity * delta
	# Shared with the charge preview (Trajectory) so the ghost arc never lies.
	var hit := Trajectory.check_segment(_terrain, position, new_pos)
	if hit["collided"]:
		_active = false
		impact.emit(hit["contact_point"], hit["impact_voxel"])
		queue_free()
		return
	position = new_pos
	# Out-of-bounds despawn (sides and bottom; arcs may exit the top and return).
	var w := Const.world_pixel_size()
	if position.x < 0 or position.x > w.x or position.y > w.y:
		_active = false
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.9, 0.3))
