# Spiral arm (M4): a secondary projectile body that doesn't fly its own ballistic arc —
# instead it rides the main projectile, offset perpendicular to the main's heading by a
# sinusoid, tracing a helix around the trajectory. It carries the salvo's payload and plugs
# into the SAME impact queue as real projectiles (reports to the manager, can be resumed).
# Two arms (arm_sign +1 / −1) give the twin-helix look.
class_name SpiralSatellite
extends Node2D

var proj_index : int = 1            # salvo order (arms come after the main, index 0)
var arm_sign : float = 1.0          # +1 / −1: opposite sides of the trajectory
var amplitude : float = 24.0        # perpendicular offset (world px)
var frequency : float = 2.0         # oscillations per second

var _main : Projectile              # the guide projectile (index 0)
var _terrain : TerrainManager
var _manager : ProjectileManager
var _salvo : RefCounted
var _elapsed : float = 0.0
var _active : bool = true

func setup(main: Projectile, terrain: TerrainManager, manager: ProjectileManager,
		salvo: RefCounted, index: int, sign_: float, amp: float, freq: float) -> void:
	_main = main
	_terrain = terrain
	_manager = manager
	_salvo = salvo
	proj_index = index
	arm_sign = sign_
	amplitude = amp
	frequency = freq
	position = main.position

func is_active() -> bool:
	return _active

func resume() -> void:
	_active = true

func _physics_process(delta: float) -> void:
	if not _active:
		return
	# Without a guide the arm has no trajectory to follow — retire it (the main already
	# resolved or left the map). Known limitation: arms don't outlive the main.
	if not is_instance_valid(_main) or not _main.is_active():
		_active = false
		_manager.report_despawn(_salvo, self)
		return
	_elapsed += delta
	var perp := _main.velocity.normalized().orthogonal()
	var prev := position
	position = _main.position + perp * amplitude * sin(TAU * frequency * _elapsed) * arm_sign
	var hit := Trajectory.check_segment(_terrain, prev, position)
	if hit["collided"]:
		_active = false
		_manager.report_impact(_salvo, self, hit["contact_point"], hit["impact_voxel"], false)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 2.5, Color(0.7, 0.95, 1.0))
