# Scene root: wires the M1 systems together and owns player input (plan §2).
# Firing model (user decision 2026-06-12, Gunbound-style):
#   ↑/↓ adjusts angle · hold Space to charge min→max power · release fires
#   (auto-fires if the charge reaches max) · full arc preview while charging.
extends Node2D

const PAN_SPEED := 700.0   # px/s camera pan
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0

@onready var terrain : TerrainManager = $TerrainManager
@onready var renderer : TerrainRenderer = $TerrainRenderer
@onready var projectiles : ProjectileManager = $ProjectileManager
@onready var unit_layer : Node2D = $UnitLayer
@onready var targeting : TargetingUI = $TargetingUI
@onready var camera : Camera2D = $Camera2D

var unit : PlayerUnit
var hud : HUD

var angle_deg : float = 45.0
var charging : bool = false
var charge_frac : float = 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color8(24, 26, 34))
	# TerrainManager._ready() already ran (child before parent): grid is generated.
	renderer.setup(terrain)
	projectiles.setup(terrain)
	_spawn_unit()
	targeting.setup(terrain, unit)
	hud = HUD.new()
	add_child(hud)
	_setup_camera()
	print("[terrain] ", terrain.debug_stats())
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		_smoke_test()

func _spawn_unit() -> void:
	unit = PlayerUnit.new()
	unit_layer.add_child(unit)
	# Stand on the spawn platform: top-left = platform row minus unit height.
	var col := Const.SPAWN_PLATFORM_COL + 3
	var platform_row := terrain.get_surface_row(col)
	unit.place_at(Vector2i(col, platform_row - PlayerUnit.HEIGHT_VOX))

func _setup_camera() -> void:
	var w := Const.world_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(w.x)
	camera.limit_bottom = int(w.y)
	camera.position = unit.barrel_origin_world()

func aim_dir() -> Vector2:
	var r := deg_to_rad(angle_deg)
	return Vector2(cos(r), -sin(r))

# --- Input ---------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_SPACE:
		if event.pressed and not event.echo and not charging:
			charging = true
			charge_frac = 0.0
		elif not event.pressed and charging:
			_release_shot()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / 1.1)

func _release_shot() -> void:
	charging = false
	var speed := lerpf(Const.MIN_PROJECTILE_SPEED, Const.MAX_PROJECTILE_SPEED, charge_frac)
	projectiles.fire(unit.barrel_origin_world(), aim_dir(), speed)
	charge_frac = 0.0

func _zoom_camera(factor: float) -> void:
	var z : float = clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

# --- Per-frame: angle, charge, HUD, camera --------------------------------------
func _process(delta: float) -> void:
	# Angle adjust (held = continuous).
	var adj := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		adj += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		adj -= 1.0
	if adj != 0.0:
		angle_deg = clampf(angle_deg + adj * Const.ANGLE_RATE_DEG * delta,
				Const.ANGLE_MIN_DEG, Const.ANGLE_MAX_DEG)

	# Charge: fills min→max over CHARGE_TIME; auto-fires at full.
	if charging:
		charge_frac = minf(charge_frac + delta / Const.CHARGE_TIME, 1.0)
		if charge_frac >= 1.0:
			_release_shot()

	hud.set_angle(angle_deg)
	hud.set_power(charge_frac, charging)
	targeting.set_aim_state(angle_deg, charging, charge_frac)

	# Camera: follow projectile in flight, else WASD pan.
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

# --- Headless smoke test (ARTILLERY_SMOKE=1): full fire→collision→AoE→collapse --
func _smoke_test() -> void:
	var destroyed := [0]
	terrain.tile_destroyed.connect(func(_c, _r, _t): destroyed[0] += 1)
	var dir := Vector2(1.0, -1.0).normalized()   # 45° reference shot (spec §9.6)
	await get_tree().create_timer(0.3).timeout
	projectiles.fire(unit.barrel_origin_world(), dir, Const.BASE_PROJECTILE_SPEED)
	await get_tree().create_timer(1.5).timeout
	projectiles.fire(unit.barrel_origin_world(), dir, Const.BASE_PROJECTILE_SPEED)
	await get_tree().create_timer(1.5).timeout
	print("[smoke] destroyed=%d | " % destroyed[0], terrain.debug_stats())
	get_tree().quit()
