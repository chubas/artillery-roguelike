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

# Camera focus target (the selected ally). _focusing is a one-shot pan: it eases the camera
# to the unit, then releases so WASD can free-pan without the camera snapping back.
var _focus_target : Unit = null
var _focusing : bool = false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color8(24, 26, 34))
	renderer.setup(terrain)
	hud = HUD.new()
	add_child(hud)
	projectiles.setup(terrain, combat.get_units)
	combat.unit_focused.connect(_on_unit_focused)
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

func _on_unit_focused(unit: Unit) -> void:
	# Selection moved to a new ally. Defer the actual pan until any in-flight projectile has
	# resolved (the projectile-follow branch in _process owns the camera while active) — so a
	# post-fire auto-advance focuses the next unit only AFTER the shot lands.
	_focus_target = unit
	_focusing = true

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
		_focusing = false   # manual pan cancels an in-progress focus
		camera.position += pan.normalized() * PAN_SPEED * delta / camera.zoom.x
		return
	# Ease toward the focused unit until centered, then release for free panning.
	if _focusing and is_instance_valid(_focus_target):
		var target := _focus_target.center_world()
		camera.position = camera.position.lerp(target, 0.18)
		if camera.position.distance_to(target) < 2.0:
			_focusing = false

# --- Headless integration smoke test (ARTILLERY_SMOKE=1) --------------------------
# Validates the M3 §10 checklist: affinity, unit/tile statuses, chain, feature flag.
func _smoke_test() -> void:
	await get_tree().create_timer(0.3).timeout
	var ea : Unit = combat.enemy_units[0]   # organic (weak fire)
	var eb : Unit = combat.enemy_units[1]   # mechanical (weak electric)
	var fire_pat : AoEPattern = load("res://data/shots/aoe/diamond_r2_fire.tres")
	var elec_pat : AoEPattern = load("res://data/shots/aoe/diamond_r2_electric.tres")
	var phys_pat : AoEPattern = load("res://data/shots/aoe/diamond_r2.tres")

	print("[smoke] -- spawn --")
	for u in combat.all_units:
		print("  %s player=%s tags=%s pos=%s hp=%d" %
				[u.display_name, u.is_player, u.definition.tags, u.vox_position, u.hp])

	print("[smoke] -- affinity (center dmg = 3 base) --")
	_reset(ea)
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), phys_pat, false)
	print("  basic on organic: -%d (expect -3, x1.0)" % (ea.definition.max_hp - ea.hp))
	_reset(ea)
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), fire_pat, false)
	print("  fire on organic:  -%d (expect -4, x1.5) burn_stacks=%d (expect 1)" %
			[ea.definition.max_hp - ea.hp, _stacks(ea, "burn")])

	print("[smoke] -- burn tick --")
	var hp_pre := ea.hp
	UnitStatusSystem.tick_all(ea)
	print("  burn tick: -%d (expect -1/stack)" % (hp_pre - ea.hp))

	print("[smoke] -- electric affinity --")
	_reset(eb)
	AoEResolver.resolve(terrain, combat.all_units, eb.center_voxel(), elec_pat, false)
	print("  electric on mechanical: -%d (expect -4, x1.5) shock_stacks=%d (expect 1)" %
			[eb.definition.max_hp - eb.hp, _stacks(eb, "shock")])

	print("[smoke] -- shock AP reduction --")
	var p : Unit = combat.player_units[0]
	p.active_statuses.clear()
	UnitStatusSystem.apply(p, load("res://data/statuses/shock.tres"), 2)
	var red := UnitStatusSystem.tick_all(p)
	print("  ap_reduction from 2 shock stacks=%d (expect 2)" % red)

	print("[smoke] -- burning tile set + spread --")
	var col := 60
	var srow := terrain.get_surface_row(col)
	TileStatusSystem.apply(terrain, Vector2i(col, srow),
			load("res://data/tile_statuses/burning.tres"))
	var before := _count_burning()
	TileStatusSystem.tick_all(terrain, combat.all_units)
	var after := _count_burning()
	print("  burning tiles before=%d after_tick=%d (expect spread to exposed FLAMMABLE)" %
			[before, after])

	print("[smoke] -- electric chain through CONDUCTIVE --")
	# Inject a conductive origin tile next to a conductive tile overlapping EnemyA's bbox.
	var v : Vector2i = ea.vox_position                # inside EnemyA's bbox
	var origin : Vector2i = v + Vector2i(-1, 0)       # adjacent, outside the bbox
	terrain.set_tile(v.x, v.y, _conductive_tile())
	terrain.set_tile(origin.x, origin.y, _conductive_tile())
	_reset(ea); ea.active_statuses.clear()
	TileStatusSystem.apply(terrain, origin, load("res://data/tile_statuses/electrified.tres"))
	var chain_pre := ea.hp
	TileStatusSystem.tick_all(terrain, combat.all_units)
	print("  chain to EnemyA: -%d (expect >=1 via conductive network)" % (chain_pre - ea.hp))

	print("[smoke] -- feature flag: elements_enabled=false --")
	Features.elements_enabled = false
	_reset(ea); ea.active_statuses.clear()
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), fire_pat, false)
	print("  fire on organic (elements OFF): -%d (expect -3, physical) burn_stacks=%d (expect 0)" %
			[ea.definition.max_hp - ea.hp, _stacks(ea, "burn")])
	Features.elements_enabled = true

	_m4_smoke()

	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

# M4 §12 checklist (deterministic, no flight required): shot-family data, salvo spawn counts,
# gravity-pull bands/ordering/blocking, and the action economy.
func _m4_smoke() -> void:
	print("[smoke] -- M4 shot families (data) --")
	var cluster : ShotDefinition = load("res://data/shots/cluster_basic.tres")
	var bypass : ShotDefinition = load("res://data/shots/bypass_basic.tres")
	var pull : ShotDefinition = load("res://data/shots/pull_basic.tres")
	var spiral : ShotDefinition = load("res://data/shots/spiral_basic.tres")
	print("  cluster: count=%d spread=%.1f (expect 5, 1.0)" %
			[cluster.projectile_count, cluster.spread_deg])
	print("  bypass: terrain=%s (expect true)" % bypass.bypass_terrain)
	print("  pull: near=%d/%d far=%d/%d (expect 4/2, 8/1)" %
			[pull.pull_near_radius, pull.pull_near_voxels,
			pull.pull_far_radius, pull.pull_far_voxels])
	print("  spiral: arms=%d amp=%.0f (expect 2, 24)" %
			[spiral.spiral_arms, spiral.spiral_amplitude])

	print("[smoke] -- M4 action economy --")
	var cf : ShotDefinition = load("res://data/shots/cluster_fire.tres")
	var ce : ShotDefinition = load("res://data/shots/cluster_electric.tres")
	print("  costs: basic=%d fire=%d electric=%d (expect 0, 2, 3)" %
			[cluster.action_cost, cf.action_cost, ce.action_cost])
	print("  MAX_ACTIONS=%d (expect 10)" % Const.MAX_ACTIONS)

	print("[smoke] -- M4 salvo spawn counts --")
	projectiles.fire(Vector2(100, 100), Vector2.RIGHT, 1.0, cluster, false)
	print("  cluster members=%d (expect 5)" % projectiles.debug_member_count())
	projectiles.fire(Vector2(120, 100), Vector2.RIGHT, 1.0, spiral, false)
	print("  +spiral members=%d (expect 8 = 5 + main + 2 arms)" %
			projectiles.debug_member_count())

	print("[smoke] -- M4 gravity pull (band + closest-first + block) --")
	_pull_smoke(pull)

# Build a flat indestructible shelf, drop two units on it, fire a pull centred to the right,
# and check each is hauled the right number of steps — closest first, blocked unit stays put.
func _pull_smoke(pull: ShotDefinition) -> void:
	var row := 30
	var c0 := 45
	for c in range(c0, c0 + 20):
		terrain.set_tile(c, row, _floor_tile())   # walking surface
		for r in range(row - 4, row):
			terrain.clear_tile(c, r)               # clear the air above
	var near_u : Unit = combat.enemy_units[0]
	var far_u : Unit = combat.enemy_units[1]
	near_u.hp = near_u.definition.max_hp
	far_u.hp = far_u.definition.max_hp
	# near_u at impact-2 (inner band), far_u at impact-6 (outer band). Impact to their right.
	var impact := Vector2i(c0 + 16, row - 1)
	near_u.set_vox_position(Vector2i(impact.x - 2, row - near_u.definition.height_voxels))
	far_u.set_vox_position(Vector2i(impact.x - 6, row - far_u.definition.height_voxels))
	var near_x0 := near_u.vox_position.x
	var far_x0 := far_u.vox_position.x
	GravityPullResolver.resolve(terrain, combat.all_units, impact, pull)
	print("  near unit moved +%d (expect +2, inner band)" % (near_u.vox_position.x - near_x0))
	print("  far unit moved +%d (expect +1, outer band)" % (far_u.vox_position.x - far_x0))
	# Blocked case: wall a unit in with a 2-high column on the pull side; it shouldn't move.
	far_u.set_vox_position(Vector2i(c0 + 2, row - far_u.definition.height_voxels))
	for r in range(row - 2, row):
		terrain.set_tile(c0 + 3, r, _floor_tile())   # 2-voxel wall toward the impact
	var blocked_x0 := far_u.vox_position.x
	GravityPullResolver.resolve(terrain, combat.all_units, Vector2i(c0 + 16, row - 1), pull)
	print("  walled unit moved +%d (expect +0, blocked by 2-voxel wall)" %
			(far_u.vox_position.x - blocked_x0))

func _floor_tile() -> Tile:
	var t := Tile.new().setup(Tile.TileType.SOLID, 99, 0)
	t.flags = Tile.FLAG_INDESTRUCTIBLE
	return t

func _reset(u: Unit) -> void:
	u.hp = u.definition.max_hp

func _stacks(u: Unit, id: String) -> int:
	return u.active_statuses[id].stacks if u.active_statuses.has(id) else 0

func _count_burning() -> int:
	var n := 0
	for c in range(Const.MAP_WIDTH):
		for r in range(Const.MAP_HEIGHT):
			var t := terrain.get_tile(c, r)
			if t != null and t.tile_statuses.has("burning"):
				n += 1
	return n

func _conductive_tile() -> Tile:
	var t := Tile.new().setup(Tile.TileType.SOLID, 6, 0)
	t.status_tags = ["CONDUCTIVE"]
	return t
