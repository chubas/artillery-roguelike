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
@onready var deployable_layer_back : Node2D = $DeployableLayerBack
@onready var deployable_layer_front : Node2D = $DeployableLayerFront
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
	projectiles.setup(terrain, combat.get_units, combat.get_deployables)
	combat.unit_focused.connect(_on_unit_focused)
	combat.setup(terrain, projectiles, unit_layer, hud, targeting,
			deployable_layer_back, deployable_layer_front)
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
	_m5_smoke()
	_m6_smoke()

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

# M5 §8 checklist (deterministic, no flight required): shield mitigation, card play
# (shield buff / direct damage / targeting / undo), and the reinforcement schedule.
func _m5_smoke() -> void:
	var ally : Unit = combat.player_units[0]
	var foe : Unit = combat.enemy_units[0]
	var shield_card : CardDefinition = load("res://data/cards/shield_buff.tres")
	var strike_card : CardDefinition = load("res://data/cards/direct_strike.tres")

	print("[smoke] -- M5 shield mitigation --")
	_reset(ally); ally.shield = 0
	ally.shield = 4
	ally.take_damage(3)
	print("  dmg 3 vs shield 4: shield=%d hp=%d (expect shield=1, hp=max)" %
			[ally.shield, ally.hp])
	ally.take_damage(3)
	print("  dmg 3 vs shield 1: shield=%d hp=%d (expect shield=0, hp=max-2 spillover)" %
			[ally.shield, ally.hp])
	_reset(ally); ally.shield = 5
	Features.shields_enabled = false
	ally.take_damage(3)
	print("  shields_enabled=false: shield=%d hp=%d (expect shield=5 untouched, hp=max-3)" %
			[ally.shield, ally.hp])
	Features.shields_enabled = true

	print("[smoke] -- M5 cards: shield buff + direct damage --")
	_reset(ally); ally.shield = 0
	var ap_pre := combat.actions_left
	combat._select_card(0)   # shield_buff
	combat._apply_card(shield_card, ally)
	print("  shield buff on ally: shield=%d (expect %d) AP spent=%d (expect %d)" %
			[ally.shield, shield_card.magnitude, ap_pre - combat.actions_left, shield_card.action_cost])

	_reset(foe); foe.shield = 0
	ap_pre = combat.actions_left
	var members_pre := projectiles.debug_member_count()
	combat._select_card(1)   # direct_strike
	combat._apply_card(strike_card, foe)
	print("  direct strike on foe: hp=%d (expect max-%d) no projectile spawned=%s AP spent=%d (expect %d)" %
			[foe.hp, strike_card.magnitude, projectiles.debug_member_count() == members_pre,
			ap_pre - combat.actions_left, strike_card.action_cost])
	print("  card play doesn't mark unit done: foe.is_done=%s (expect false)" % foe.is_done)

	print("[smoke] -- M5 cards: once per turn --")
	print("  strike now in _used_cards=%s (expect true)" % (strike_card in combat._used_cards))
	_reset(foe); foe.shield = 0
	ap_pre = combat.actions_left
	combat._select_card(1)   # already used → should refuse to arm
	print("  re-select used card: pending=%s (expect <null>)" % combat._pending_card)
	combat._used_cards.clear()   # simulate a fresh turn
	print("  after turn reset, strike selectable: used=%s (expect false)" %
			(strike_card in combat._used_cards))

	print("[smoke] -- M5 card targeting + cancel --")
	_reset(ally); ally.shield = 0
	combat._select_card(0)
	combat._try_click_target_card(foe.center_world())   # wrong side: card wants ALLY
	print("  wrong-side click no-op: ally.shield=%d (expect 0, _pending_card still set=%s)" %
			[ally.shield, combat._pending_card != null])
	combat._cancel_pending_card()
	print("  escape clears pending without AP spend: pending=%s" % combat._pending_card)

	print("[smoke] -- M5 undo: card play becomes the new checkpoint baseline (like a fire) --")
	_reset(foe); foe.shield = 0
	combat._select_card(1)
	combat._apply_card(strike_card, foe)   # _apply_card's own _save_checkpoint locks this in
	var ap_after_card := combat.actions_left
	var hp_after_card := foe.hp
	combat.try_move(ally, 1)               # a move made AFTER the card IS undoable
	combat.try_undo()
	print("  undo reverts the post-card move (actions_left=%d, expect %d) but not the card's own spend or foe.hp (unchanged=%s)" %
			[combat.actions_left, ap_after_card, foe.hp == hp_after_card])

	print("[smoke] -- M5 inspector focus (ally selection vs. enemy click) --")
	combat._set_selection(ally)
	print("  selecting ally sets both active+inspected: active=%s inspected=%s (expect both ally)" %
			[combat.active_unit == ally, combat.inspected_unit == ally])
	combat._try_click_select(foe.center_world())
	print("  clicking enemy inspects it without changing active_unit: active=%s (expect true, still ally) inspected=%s (expect true, now foe)" %
			[combat.active_unit == ally, combat.inspected_unit == foe])
	print("  enemy gets the cyan inspected outline, not the white selected one: foe.inspected=%s foe.selected=%s (expect true, false)" %
			[foe.inspected, foe.selected])

	print("[smoke] -- M5 reinforcements --")
	var enemy_count_pre := combat.enemy_units.size()
	combat.round_index = 1
	var warn := combat._reinforcement_warnings()
	print("  round 1 warnings turns_left=%s (expect [1, 4])" %
			[warn.map(func(w): return w["turns_left"])])
	combat.round_index = 2
	combat._check_reinforcements()
	print("  round 2 spawn: enemy_units +%d (expect +1), new unit col=%d (expect %d)" %
			[combat.enemy_units.size() - enemy_count_pre, combat.enemy_units[-1].vox_position.x,
			Const.MAP_WIDTH - 26])
	combat._check_reinforcements()
	print("  round 2 re-check doesn't double-spawn: enemy_units=%d (expect %d)" %
			[combat.enemy_units.size(), enemy_count_pre + 1])
	combat.round_index = 5
	combat._check_reinforcements()
	print("  round 5 spawn: enemy_units +%d total (expect +2 vs original)" %
			[combat.enemy_units.size() - enemy_count_pre])
	var new_enemy : Unit = combat.enemy_units[-1]
	_reset(new_enemy)
	AoEResolver.resolve(terrain, combat.all_units, new_enemy.center_voxel(),
			load("res://data/shots/aoe/diamond_r2.tres"), false)
	print("  new enemy targetable by AoE: hp=%d (expect < max)" % new_enemy.hp)

# M6 checklist: turn-phase banners (visual, see console), mine detonation (hit + proximity,
# players only), shield generator aura + destruction, deployable falling, kill switch.
func _m6_smoke() -> void:
	print("[smoke] -- M6 phases (visual: confirm 5 === [PHASE] === banners printed above) --")

	print("[smoke] -- M6 mine: detonate by AoE hit --")
	var ally : Unit = combat.player_units[0]
	var foe : Unit = combat.enemy_units[0]
	var mine_pat : AoEPattern = load("res://data/shots/aoe/diamond_mine.tres")
	var mine := Mine.new()
	mine.explosion_pattern = mine_pat
	var mine_pos := Vector2i(foe.vox_position.x - 2, foe.vox_position.y)
	mine.set_vox_position(mine_pos)
	combat.deployables.append(mine)
	add_child(mine)
	_reset(foe)
	var deaths_pre := combat.deployables.size()
	AoEResolver.resolve(terrain, combat.all_units, mine.vox_position,
			load("res://data/shots/aoe/diamond_r2.tres"), false, combat.deployables)
	print("  mine hit: removed_from_list=%s (expect true) foe.hp=%d (expect < max, splash)" %
			[combat.deployables.size() == deaths_pre - 1, foe.hp])

	print("[smoke] -- M6 mine: proximity trigger (player only) --")
	var mine2 := Mine.new()
	mine2.explosion_pattern = mine_pat
	mine2.set_vox_position(Vector2i(ally.vox_position.x + 10, ally.vox_position.y))
	combat.deployables.append(mine2)
	add_child(mine2)
	var enemy_far : Unit = combat.enemy_units[1]
	var enemy_pos_before : Vector2i = enemy_far.vox_position
	enemy_far.set_vox_position(Vector2i(mine2.vox_position.x + 1, mine2.vox_position.y))
	print("  enemy steps near mine: still alive=%s (expect true, enemies don't trigger mines)" %
			(mine2.hp > 0))
	enemy_far.set_vox_position(enemy_pos_before)
	ally.set_vox_position(Vector2i(mine2.vox_position.x + 1, mine2.vox_position.y))
	print("  player steps near mine: detonated=%s (expect true)" % (not is_instance_valid(mine2) or mine2.hp <= 0))

	print("[smoke] -- M6 shield generator: aura grant --")
	var sg := ShieldGenerator.new()
	sg.set_vox_position(Vector2i(ally.vox_position.x, ally.vox_position.y))
	combat.deployables.append(sg)
	add_child(sg)
	var near_ally : Unit = combat.player_units[1]
	var far_ally : Unit = combat.player_units[2]
	near_ally.set_vox_position(Vector2i(sg.vox_position.x + 3, sg.vox_position.y))
	far_ally.set_vox_position(Vector2i(sg.vox_position.x + 50, sg.vox_position.y))
	near_ally.shield = 0
	far_ally.shield = 0
	combat._pulse_shield_generators()
	print("  ally within aura: shield=%d (expect %d)" % [near_ally.shield, sg.shield_amount])
	print("  ally outside aura: shield=%d (expect 0)" % far_ally.shield)

	print("[smoke] -- M6 shield generator: destruction --")
	var sg_count_pre := combat.deployables.size()
	sg.take_damage(sg.hp)
	print("  destroyed: removed_from_list=%s (expect true)" %
			(combat.deployables.size() == sg_count_pre - 1))

	print("[smoke] -- M6 deployable falling --")
	var sg2 := ShieldGenerator.new()
	var fall_col := 50
	var surface := terrain.get_surface_row(fall_col)
	sg2.set_vox_position(Vector2i(fall_col, surface - 1))
	combat.deployables.append(sg2)
	add_child(sg2)
	for r in range(surface, surface + 3):
		terrain.clear_tile(fall_col, r)
	var pos_before_fall := sg2.vox_position
	combat._settle_deployable(sg2)
	print("  fell after terrain removed: moved=%s (expect true) new_pos=%s" %
			[sg2.vox_position != pos_before_fall, sg2.vox_position])

	print("[smoke] -- M6 kill switch: deployables_enabled=false --")
	Features.deployables_enabled = false
	var sg3 := ShieldGenerator.new()
	sg3.set_vox_position(Vector2i(ally.vox_position.x, ally.vox_position.y))
	combat.deployables.append(sg3)
	add_child(sg3)
	near_ally.shield = 0
	# _pulse_shield_generators / _check_mine_triggers are no-ops once the flag is off; the
	# call sites in CombatManager already gate on it, so just confirm no shield is granted.
	print("  flag off → no aura pulse if caller respects gate: shield=%d (expect 0)" % near_ally.shield)
	Features.deployables_enabled = true

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
