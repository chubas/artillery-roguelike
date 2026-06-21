# Post-impact mine that crawls along the terrain contour (M5 Walker shot).
# Keeps its salvo alive until it explodes; direction is away from the firing side.
class_name WalkerCrawler
extends Node2D

const STEP_DELAY : float = 0.12

var _terrain : TerrainManager
var _manager : ProjectileManager
var _salvo : RefCounted
var _units_provider : Callable
var _vox : Vector2i
var _dir : int
var _steps_left : int
var _is_enemy : bool
var _active : bool = true

func setup(terrain: TerrainManager, manager: ProjectileManager, salvo: RefCounted,
		units_provider: Callable, impact_voxel: Vector2i, direction: int,
		max_steps: int, is_enemy: bool) -> void:
	_terrain = terrain
	_manager = manager
	_salvo = salvo
	_units_provider = units_provider
	_dir = direction
	_steps_left = max_steps
	_is_enemy = is_enemy
	var surface := _terrain.get_surface_row(impact_voxel.x)
	if surface == -1:
		_explode(impact_voxel)
		return
	_vox = Vector2i(impact_voxel.x, surface - 1)
	position = Const.voxel_center_world(_vox)
	if _opponent_at(_vox):
		_explode(_vox)
		return
	_run()

func is_active() -> bool:
	return _active

func _run() -> void:
	while _active and _steps_left > 0:
		await get_tree().create_timer(STEP_DELAY).timeout
		if not _active:
			return
		if _opponent_at(_vox):
			_explode(_vox)
			return
		var next := _crawl_step(_vox, _dir)
		if next == UnitMovement.NO_MOVE:
			_explode(_vox)
			return
		_vox = next
		_steps_left -= 1
		position = Const.voxel_center_world(_vox)
		queue_redraw()
	_explode(_vox)

func _crawl_step(from: Vector2i, direction: int) -> Vector2i:
	var new_x := from.x + direction
	if new_x < 0 or new_x >= Const.MAP_WIDTH:
		return UnitMovement.NO_MOVE
	if UnitMovement.bbox_terrain_clear(_terrain, Vector2i(new_x, from.y), 1, 1):
		var foot := from.y
		while foot < Const.MAP_HEIGHT - 1 \
				and not UnitMovement.grounded(_terrain, new_x, foot, 1):
			foot += 1
		return Vector2i(new_x, foot)
	if UnitMovement.bbox_terrain_clear(_terrain, Vector2i(new_x, from.y - 1), 1, 1):
		return Vector2i(new_x, from.y - 1)
	return UnitMovement.NO_MOVE

func _opponent_at(vox: Vector2i) -> bool:
	for u in _units_provider.call():
		if u.hp <= 0:
			continue
		var is_opponent : bool = u.is_player if _is_enemy else not u.is_player
		if is_opponent and u.contains_voxel(vox):
			return true
	return false

func _explode(vox: Vector2i) -> void:
	if not _active:
		return
	_active = false
	_manager.resolve_walker_explosion(_salvo, Const.voxel_center_world(vox), vox)
	_salvo.members.erase(self)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.95, 0.55, 0.15))
