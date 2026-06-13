# Scene root for the M2 combat prototype: wires systems together, owns the camera.
# Combat input lives in CombatManager; only camera pan/zoom is handled here.
extends Node2D

const PAN_SPEED := 700.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0

@onready var terrain : TerrainManager = $TerrainManager
@onready var renderer : TerrainRenderer = $TerrainRenderer
@onready var projectiles : ProjectileManager = $ProjectileManager
@onready var unit_layer : Node2D = $UnitLayer
@onready var combat : CombatManager = $CombatManager
@onready var targeting : TargetingUI = $TargetingUI
@onready var camera : Camera2D = $Camera2D

var hud : HUD

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color8(24, 26, 34))
	renderer.setup(terrain)
	hud = HUD.new()
	add_child(hud)
	projectiles.setup(terrain, combat.get_units)
	combat.setup(terrain, projectiles, unit_layer, hud, targeting)
	targeting.setup(terrain, combat.all_units)
	_setup_camera()
	print("[terrain] ", terrain.debug_stats())
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		_smoke_test()

func _setup_camera() -> void:
	var w := Const.world_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(w.x)
	camera.limit_bottom = int(w.y)
	if not combat.player_units.is_empty():
		camera.position = combat.player_units[0].center_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / 1.1)

func _zoom_camera(factor: float) -> void:
	var z : float = clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

func _process(delta: float) -> void:
	var p := projectiles.active_projectile()
	if p != null:
		camera.position = camera.position.lerp(p.position, 0.18)
		return
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		pan.x += 1
	if Input.is_physical_key_pressed(KEY_W):
		pan.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		pan.y += 1
	if pan != Vector2.ZERO:
		camera.position += pan.normalized() * PAN_SPEED * delta / camera.zoom.x

# --- Headless integration smoke test (ARTILLERY_SMOKE=1) --------------------------
func _smoke_test() -> void:
	await get_tree().create_timer(0.3).timeout
	print("[smoke] -- spawn --")
	for u in combat.all_units:
		print("  %s player=%s pos=%s hp=%d" % [u.display_name, u.is_player, u.vox_position, u.hp])
	for i in range(combat.all_units.size()):
		for j in range(i + 1, combat.all_units.size()):
			var a : Unit = combat.all_units[i]
			var b : Unit = combat.all_units[j]
			var ra := Rect2i(a.vox_position, Vector2i(a.definition.width_voxels, a.definition.height_voxels))
			var rb := Rect2i(b.vox_position, Vector2i(b.definition.width_voxels, b.definition.height_voxels))
			if ra.intersects(rb):
				print("  OVERLAP FAIL: %s vs %s" % [a.display_name, b.display_name])
	print("[smoke] -- pattern --")
	var pat : AoEPattern = load("res://data/shots/aoe/diamond_r2.tres")
	var m := pat.to_map()
	print("  offsets=%d center_dmg=%d ring2_dmg=%d" %
			[m.size(), m[Vector2i.ZERO].damage, m[Vector2i(2, 0)].damage])
	print("[smoke] -- AoE on EnemyA --")
	var ea : Unit = combat.enemy_units[0]
	var hp_before := ea.hp
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), pat, false)
	print("  EnemyA hp %d -> %d (expect -3)" % [hp_before, ea.hp])
	print("[smoke] -- movement + undo --")
	var u1 : Unit = combat.player_units[0]
	var p0 := u1.vox_position
	combat.try_move(u1, 1)
	combat.try_move(u1, 1)   # 2nd move blocked: Unit1 (2 wide) would overlap Unit2 at col 15
	print("  moved %s -> %s actions_left=%d (expect 1 move, 4: 2nd blocked by Unit2)" %
			[p0, u1.vox_position, combat.actions_left])
	combat.try_undo()
	print("  undo -> %s actions_left=%d (expect %s, 5)" % [u1.vox_position, combat.actions_left, p0])
	print("[smoke] -- enemy IK --")
	var target := EnemySystem.nearest_living_player(ea, combat.player_units)
	var sol := EnemySystem.firing_solution(ea, target)
	if sol.is_empty():
		print("  IK FAIL: no solution")
	else:
		var sim := Trajectory.simulate_arc(terrain, ea.barrel_origin_world(),
				sol["direction"], sol["speed"], 1.0, 12.0)
		if sim["hit"]:
			var miss : Vector2i = sim["impact_voxel"] - target.center_voxel()
			print("  angle=%s speed=%.0f impact=%s target=%s miss=(%d,%d) voxels" %
					[sol["angle_deg"], sol["speed"], sim["impact_voxel"],
					target.center_voxel(), miss.x, miss.y])
		else:
			print("  IK arc never landed (speed=%.0f)" % sol["speed"])
	print("[smoke] -- win condition --")
	combat.enemy_units[0].take_damage(99)
	combat.enemy_units[1].take_damage(99)
	print("  game_state=%d (expect %d STAGE_CLEAR)" %
			[combat.game_state, CombatManager.GameState.STAGE_CLEAR])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
