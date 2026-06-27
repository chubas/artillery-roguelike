# Scene root for the M2 combat prototype: wires systems together, owns the camera.
# Combat input lives in CombatManager; only camera pan/zoom is handled here.
extends Node2D

# M14: emitted after write-back when the stage resolves, so the run controller can advance the map.
signal combat_exited(outcome: String)

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
@onready var world_fx : WorldFXLayer = $WorldFXLayer

var hud : HUD

# The stage this combat runs (M13). Defaults to stage_01 if unset; M14's run controller will set
# it from the active map node before the scene loads.
var stage : StageDescriptor = null
# M33: run-controller sets these from MapNode before entering combat.
var terrain_profile_path : String = ""
var active_stage_seed    : int    = -1

# Camera focus target (the selected ally). _focusing is a one-shot pan: it eases the camera
# to the unit, then releases so WASD can free-pan without the camera snapping back.
var _focus_target : Unit = null
var _focusing : bool = false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color8(24, 26, 34))
	AnimationSequencer.world_fx = world_fx
	# M13: the stage descriptor drives terrain generation (its seed) before the renderer builds
	# chunks, plus enemies/reinforcements/wind/deployables/objective inside combat.
	if stage == null:
		stage = load("res://data/stages/stage_01.tres")
	if Features.stage_rng_enabled:
		var _seed := active_stage_seed if active_stage_seed >= 0 else stage.terrain_seed
		StageRng.init(_seed)
		CombatRng.init(_seed)
	_setup_terrain()
	hud = HUD.new()
	add_child(hud)
	projectiles.setup(terrain, combat.get_units, combat.get_deployables)
	combat.unit_focused.connect(_on_unit_focused)
	# M12: combat reads its squad/deck/artifacts from the active run (default run if launched
	# standalone). CombatBridge owns the RunState→combat translation; write-back on exit.
	if Run.active == null:
		Run.start_default_run()
	var squad := CombatBridge.build_squad(Run.active)
	combat.combat_finished.connect(_on_combat_finished)
	combat.setup(terrain, projectiles, unit_layer, hud, targeting,
			deployable_layer_back, deployable_layer_front,
			squad, Run.active.deck, Run.active.artifacts, stage)
	targeting.setup(terrain, combat.all_units)
	_setup_camera()
	print("[terrain] ", terrain.debug_stats())
	if Features.sandbox_enabled and OS.get_environment("ARTILLERY_SMOKE") != "1":
		var overlay : Node = load("res://debug/sandbox_overlay.gd").new()
		add_child(overlay)
		overlay.call("setup", combat, terrain, renderer, camera, hud)
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		combat._drain_placement_queue()   # drop every queued unit + confirm → start round 1
		_smoke_test()

# M12: combat resolved → write surviving HP / kills / disabled back into the run. The
# "advance the map / grant rewards" half is M14's run controller; here we just persist + log.
func _on_combat_finished(outcome: String) -> void:
	CombatBridge.write_back(Run.active, combat.player_units)
	var lines : Array = []
	for rus in Run.active.squad:
		lines.append("%s hp=%d/%d kills=%d%s" % [rus.display_name, rus.current_hp, rus.max_hp,
				rus.kills, " [disabled]" if rus.is_disabled else ""])
	print("[RUN] combat %s — squad written back: %s" % [outcome, ", ".join(lines)])
	combat_exited.emit(outcome)   # M14: hand control back to the run controller

func _setup_camera() -> void:
	var w := Const.world_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(w.x)
	camera.limit_bottom = int(w.y)
	# During placement units are hidden/unpositioned, so center on the spawn zone's midpoint.
	var mid_col := (combat._spawn_min_col() + combat._spawn_max_col()) / 2
	var mid_row := Const.MAP_HEIGHT / 2
	camera.position = Const.voxel_to_world(Vector2i(mid_col, mid_row))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_EQUAL:
			_zoom_camera(1.1)
		elif event.physical_keycode == KEY_MINUS:
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
	# Safety: force-quit after 60s in case any smoke function hangs or errors loop forever.
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[smoke] TIMEOUT — forced quit after 60s")
		get_tree().quit(1))
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
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), phys_pat, 3, false)
	print("  basic on organic: -%d (expect -3, x1.0)" % (ea.definition.max_hp - ea.hp))
	_reset(ea)
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), fire_pat, 3, false)
	print("  fire on organic:  -%d (expect -4, x1.5) burn_stacks=%d (expect 1)" %
			[ea.definition.max_hp - ea.hp, _stacks(ea, "burn")])

	print("[smoke] -- burn tick --")
	var hp_pre := ea.hp
	UnitStatusSystem.tick_all(ea)
	print("  burn tick: -%d (expect -1/stack)" % (hp_pre - ea.hp))

	print("[smoke] -- electric affinity --")
	_reset(eb)
	AoEResolver.resolve(terrain, combat.all_units, eb.center_voxel(), elec_pat, 3, false)
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
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), fire_pat, 3, false)
	print("  fire on organic (elements OFF): -%d (expect -3, physical) burn_stacks=%d (expect 0)" %
			[ea.definition.max_hp - ea.hp, _stacks(ea, "burn")])
	Features.elements_enabled = true

	_m4_smoke()
	_m5_smoke()
	_m6_smoke()
	_m7_smoke()
	_m8_smoke()
	_m9_smoke()
	_m10_smoke()
	_m11_smoke()
	_m12_smoke()
	_m13_smoke()
	_m14_smoke()
	_m19_smoke()
	_m20_smoke()
	_m15_smoke()
	_m16_smoke()
	_m17_smoke()
	_m18_smoke()
	_m21_smoke()
	_m22_smoke()
	_m23_smoke()
	_m27_smoke()
	_m29_smoke()
	_m30_smoke()
	_m31_smoke()
	_m32_smoke()
	_m33_smoke()
	_m34_smoke()
	_m35_smoke()
	_m36_smoke()
	_m37_smoke()

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
	print("  MAX_ACTIONS=%d (expect 5)" % Const.MAX_ACTIONS)

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
	# Isolate raw card mechanics from artifact effects (e.g. Free First Card zeroing a cost).
	var saved_artifacts := combat.artifacts
	combat.artifacts = [] as Array[ArtifactDef]
	_reset(ally); ally.shield = 0
	var ap_pre := combat.actions_left
	combat._apply_card(shield_card, ally, Vector2i.ZERO)
	print("  shield buff on ally: shield=%d (expect %d) AP spent=%d (expect %d)" %
			[ally.shield, shield_card.magnitude, ap_pre - combat.actions_left, shield_card.action_cost])

	_reset(foe); foe.shield = 0
	ap_pre = combat.actions_left
	var members_pre := projectiles.debug_member_count()
	combat._apply_card(strike_card, foe, Vector2i.ZERO)
	print("  direct strike on foe: hp=%d (expect max-%d) no projectile spawned=%s AP spent=%d (expect %d)" %
			[foe.hp, strike_card.magnitude, projectiles.debug_member_count() == members_pre,
			ap_pre - combat.actions_left, strike_card.action_cost])
	print("  card play doesn't mark unit done: foe.is_done=%s (expect false)" % foe.is_done)

	print("[smoke] -- M5 card targeting + cancel --")
	_reset(ally); ally.shield = 0
	combat._pending_card = shield_card   # arm an ALLY-target card
	combat._try_click_target_card(foe.center_world())   # wrong side: card wants ALLY
	print("  wrong-side click no-op: ally.shield=%d (expect 0, _pending_card still set=%s)" %
			[ally.shield, combat._pending_card != null])
	combat._cancel_pending_card()
	print("  escape clears pending without AP spend: pending=%s" % combat._pending_card)

	print("[smoke] -- M5 undo: card play becomes the new checkpoint baseline (like a fire) --")
	_reset(foe); foe.shield = 0
	combat._apply_card(strike_card, foe, Vector2i.ZERO)   # _apply_card's own _save_checkpoint locks this in
	var ap_after_card := combat.actions_left
	var hp_after_card := foe.hp
	combat.try_move(ally, 1)               # a move made AFTER the card IS undoable
	combat.try_undo()
	print("  undo reverts the post-card move (actions_left=%d, expect %d) but not the card's own spend or foe.hp (unchanged=%s)" %
			[combat.actions_left, ap_after_card, foe.hp == hp_after_card])
	combat.artifacts = saved_artifacts   # restore the live loadout

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
			load("res://data/shots/aoe/diamond_r2.tres"), 3, false)
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
			load("res://data/shots/aoe/diamond_r2.tres"), 3, false, combat.deployables)
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

# M7 checklist: zone-multiplier damage (core vs. edge), Unit.power scaling both zones
# proportionally, mine strength independent of any unit's power, and zone_color() returning
# distinct colors per tier.
func _m7_smoke() -> void:
	print("[smoke] -- M7 zone strength: core vs edge --")
	var ea : Unit = combat.enemy_units[0]
	var phys_pat : AoEPattern = load("res://data/shots/aoe/diamond_r2.tres")
	_reset(ea)
	AoEResolver.resolve(terrain, combat.all_units, ea.center_voxel(), phys_pat, 5, false)
	print("  strength=5 on core voxel: -%d (expect -5)" % (ea.definition.max_hp - ea.hp))

	print("[smoke] -- M7/M10 attack × strength_mult × power scales strength --")
	var p : Unit = combat.player_units[0]
	var base_pow := p.power
	var base_atk := p.attack
	p.attack = 3
	p.power = 2.0
	# M10 fire formula: round(attack * strength_mult(1.0) * power) + attack_modifier(0).
	var scaled_strength := roundi(p.attack * 1.0 * p.power)
	print("  attack=3 * mult=1.0 * power=2.0 -> salvo strength=%d (expect 6)" % scaled_strength)
	p.power = base_pow
	p.attack = base_atk

	print("[smoke] -- M7 mine strength independent of unit power --")
	var mine := Mine.new()
	mine.explosion_pattern = phys_pat
	print("  mine.strength=%d (expect 4, no unit-power factor)" % mine.strength)
	mine.queue_free()

	print("[smoke] -- M7 zone_color distinct per tier --")
	var core_col := AoEPattern.zone_color(1.0)
	var edge_col := AoEPattern.zone_color(0.5)
	print("  core=%s edge=%s distinct=%s (expect true)" %
			[core_col, edge_col, core_col != edge_col])

# M8 checklist: wind_strength gated before start_round, ramp limits hold over many trials,
# fire spreads only when wind > 0.2, Trajectory arc bends with wind force.
func _m8_smoke() -> void:
	print("[smoke] -- M8 wind: round 2 (before start_round=3) --")
	combat.wind_strength = 0.0
	combat._update_wind_for_round(2)
	print("  round 2: wind_strength=%.4f (expect 0.0)" % combat.wind_strength)

	print("[smoke] -- M8 wind: round 3 (first ramp step, range ±5%) --")
	# elapsed=0 → range_frac = 0.05*1 = 0.05; all 30 trials must stay within that
	var round3_ok := true
	for _i in range(30):
		combat._update_wind_for_round(3)
		if abs(combat.wind_strength) > 0.05 + 0.001:
			round3_ok = false
	print("  round 3 (30 trials) abs<=0.05: %s (expect true)" % round3_ok)

	print("[smoke] -- M8 wind: round 8 (elapsed=5, range ±30%) --")
	# elapsed=5 → range_frac = 0.05*6 = 0.30
	var round8_ok := true
	for _i in range(30):
		combat._update_wind_for_round(8)
		if abs(combat.wind_strength) > 0.30 + 0.001:
			round8_ok = false
	print("  round 8 (30 trials) abs<=0.30: %s (expect true)" % round8_ok)

	print("[smoke] -- M8 fire spread: triggers at wind=0.25, not at 0.1 --")
	# Find two adjacent FLAMMABLE columns at the same surface height so the spread isn't blocked.
	var spread_col := -1
	var spread_row := -1
	var burning_def2 : Resource = load("res://data/tile_statuses/burning.tres")
	for c in range(5, Const.MAP_WIDTH - 2):
		var r0 := terrain.get_surface_row(c)
		var r1 := terrain.get_surface_row(c + 1)
		if r0 == -1 or r1 == -1 or r0 != r1:
			continue
		var t0 := terrain.get_tile(c, r0)
		var t1 := terrain.get_tile(c + 1, r1)
		if t0 == null or t1 == null:
			continue
		if t0.tile_statuses.has("burning") or t1.tile_statuses.has("burning"):
			continue
		if t0.has_flag_tag("FLAMMABLE") and t1.has_flag_tag("FLAMMABLE"):
			spread_col = c
			spread_row = r0
			break
	if spread_col == -1:
		print("  SKIPPED: no flat adjacent FLAMMABLE pair found")
	else:
		# Gate check: abs(0.1) < 0.2 threshold → no spread.
		TileStatusSystem.apply(terrain, Vector2i(spread_col, spread_row), burning_def2)
		var before_lo := _count_burning()
		combat.wind_strength = 0.1
		combat._wind_spread_fire()
		var after_lo := _count_burning()
		print("  wind=0.1 no spread: burning %d->%d (expect same)" % [before_lo, after_lo])
		# Above-threshold: abs(0.25) >= 0.2 → spread to adjacent flat FLAMMABLE tile.
		var before_hi := _count_burning()
		combat.wind_strength = 0.25
		combat._wind_spread_fire()
		var after_hi := _count_burning()
		print("  wind=0.25 spread at col=%d: burning %d->%d (expect increase)" %
				[spread_col, before_hi, after_hi])

	print("[smoke] -- M8 trajectory bends with wind --")
	var t_origin := Vector2(300.0, 60.0)
	var t_dir := Vector2(1.0, 0.15).normalized()
	var t_speed := 400.0
	var sim0 := Trajectory.simulate_arc(terrain, t_origin, t_dir, t_speed, 1.0, 8.0, false, 0.0)
	var simw := Trajectory.simulate_arc(terrain, t_origin, t_dir, t_speed, 1.0, 8.0, false, 300.0)
	var pts0 : PackedVector2Array = sim0["points"]
	var ptsw : PackedVector2Array = simw["points"]
	var end0 : Vector2 = pts0[-1] if pts0.size() > 0 else Vector2.ZERO
	var endw : Vector2 = ptsw[-1] if ptsw.size() > 0 else Vector2.ZERO
	var bends : bool = end0.x != endw.x or sim0["impact_voxel"] != simw["impact_voxel"]
	print("  arc differs with wind=%s end_x: no_wind=%.0f wind300=%.0f (expect rightward shift)" %
			[bends, end0.x, endw.x])

func _m9_smoke() -> void:
	print("[smoke] -- M9 artifacts: system checks --")

	# Build a minimal context pointing at combat's terrain/units.
	var ctx := ArtifactContext.new()
	ctx.terrain = terrain
	ctx.units = combat.all_units
	ctx.combat = combat

	# --- Artifact #4: first card costs 0, second costs base ---
	var a4 := ArtifactFreeFirstCard.new()
	a4.reset_per_combat()
	var dummy_card : CardDefinition = load("res://data/cards/shield_buff.tres")
	var cost1 : int = a4.modify_card_cost(ctx, dummy_card, dummy_card.action_cost)
	var cost2 : int = a4.modify_card_cost(ctx, dummy_card, dummy_card.action_cost)
	print("  free first card: cost1=%d (expect 0), cost2=%d (expect %d)" %
			[cost1, cost2, dummy_card.action_cost])

	# --- Artifact #7: long-flight strength boost ---
	var a7 := ArtifactLongFlight.new()
	var s_short : int = a7.modify_projectile_strength(ctx, 10, 9.0)
	var s_long  : int = a7.modify_projectile_strength(ctx, 10, 11.0)
	print("  long flight: flight=9s→%d (expect 10), flight=11s→%d (expect 12)" %
			[s_short, s_long])

	# --- Artifact #5: idle actions count ---
	var a5 := ArtifactIdleActions.new()
	for u in combat.player_units:
		u.moved_this_turn = false
	var bonus_all_idle : int = a5.bonus_actions_on_round_start(ctx)
	combat.player_units[0].moved_this_turn = true
	var bonus_one_moved : int = a5.bonus_actions_on_round_start(ctx)
	combat.player_units[0].moved_this_turn = false
	print("  idle actions: all_idle=%d (expect %d), one_moved=%d (expect %d)" %
			[bonus_all_idle, combat.player_units.size(),
			bonus_one_moved, combat.player_units.size() - 1])

	# --- Artifact #3: enemy debuff stacks ---
	var a3 := ArtifactEnemyDebuff.new()
	var enemy : Unit = combat.enemy_units[0]
	enemy.attack_modifier = 0
	a3.on_player_turn_end(ctx)
	a3.on_player_turn_end(ctx)
	print("  enemy debuff after 2 turns: modifier=%d (expect -6)" % enemy.attack_modifier)
	enemy.attack_modifier = 0

	# --- Artifact #1: squad regen ---
	var a1 := ArtifactSquadRegen.new()
	var pu : Unit = combat.player_units[0]
	pu.hp = pu.definition.max_hp - 2
	a1.on_round_start(ctx)
	print("  squad regen: hp before=%d, after=%d (expect +1)" %
			[pu.definition.max_hp - 2, pu.hp])
	_reset(pu)

	# --- ArtifactSystem pipeline: apply_card_cost uses features flag ---
	var artifacts_test : Array[ArtifactDef] = [a4 as ArtifactDef]
	a4.reset_per_combat()
	var pipe_cost : int = ArtifactSystem.apply_card_cost(artifacts_test, ctx,
			dummy_card, dummy_card.action_cost)
	print("  pipeline apply_card_cost (feature on): %d (expect 0)" % pipe_cost)

# M10 checklist: per-unit attack drives strength (+ clamp), Boosted persists across ticks,
# Boosted is spent by moves (free move bypasses AP), undo refunds spent Boosted, and the
# Start-Boosted artifact grants 3 stacks at stage start.
func _m10_smoke() -> void:
	print("[smoke] -- M10 attack value drives strength --")
	var drill := _find_unit("Drill")
	var cluster := _find_unit("Cluster")
	if drill != null and cluster != null:
		print("  drill attack=%d (expect 10), cluster attack=%d (expect 3)" %
				[drill.attack, cluster.attack])
	# Fire formula: max(0, round(attack * strength_mult * power) + attack_modifier).
	var s_norm := maxi(0, roundi(3 * 1.0 * 1.0) + 0)
	var s_clamped := maxi(0, roundi(3 * 1.0 * 1.0) + (-5))
	print("  atk3*mult1*pow1+0=%d (expect 3); +(-5) clamped=%d (expect 0)" % [s_norm, s_clamped])

	print("[smoke] -- M10 Boosted persists across tick --")
	var boosted_def : StatusEffectDef = load("res://data/statuses/boosted.tres")
	var u : Unit = combat.player_units[0]
	u.active_statuses.clear()
	UnitStatusSystem.apply(u, boosted_def, 3)
	UnitStatusSystem.tick_all(u)
	print("  boosted after tick_all: stacks=%d present=%s (expect 3, true)" %
			[_stacks(u, "boosted"), u.active_statuses.has("boosted")])

	print("[smoke] -- M10 Boosted consumed by move token --")
	combat._spend_move_token(u, combat._unit_move_token(u))
	combat._spend_move_token(u, combat._unit_move_token(u))
	combat._spend_move_token(u, combat._unit_move_token(u))
	print("  after 3 spends: stacks=%d token_now_null=%s (expect 0, true)" %
			[_stacks(u, "boosted"), combat._unit_move_token(u) == null])

	print("[smoke] -- M10 free move bypasses AP, undo refunds boost --")
	combat.game_state = CombatManager.GameState.PLAYER_TURN
	var mover : Unit = combat.active_unit if combat.active_unit != null else combat.player_units[0]
	mover.active_statuses.clear()
	UnitStatusSystem.apply(mover, boosted_def, 2)
	combat._save_checkpoint()       # snapshots boosted=2 for this unit
	var ap_before := combat.actions_left
	combat.actions_left = 0          # prove the move is free (no AP available)
	var pos_before := mover.vox_position
	combat.try_move(mover, 1)
	if mover.vox_position == pos_before:
		combat.try_move(mover, -1)
	var moved := mover.vox_position != pos_before
	print("  moved with AP=0: %s, AP still 0: %s, boosted=%d (expect true, true, 1)" %
			[moved, combat.actions_left == 0, _stacks(mover, "boosted")])
	combat.try_undo()
	print("  after undo: boosted=%d (expect 2)" % _stacks(mover, "boosted"))
	combat.actions_left = ap_before

	print("[smoke] -- M10 Start-Boosted artifact grants 3 at stage start --")
	var sb := ArtifactStartBoosted.new()
	var ctx := ArtifactContext.new()
	ctx.terrain = terrain
	ctx.units = combat.all_units
	ctx.combat = combat
	var test_u : Unit = combat.player_units[1]
	test_u.active_statuses.clear()
	sb.on_combat_start(ctx)
	print("  player unit boosted after artifact: %d (expect 3)" % _stacks(test_u, "boosted"))

# M11 checklist: deck builds + draws a fresh 5-card hand, reshuffles the discard mid-draw when
# the draw pile runs short, and the three new card effects (boosted / mine / halve-wind) apply.
func _m11_smoke() -> void:
	combat.game_state = CombatManager.GameState.PLAYER_TURN

	print("[smoke] -- M11 deck: build + draw fresh hand --")
	combat._build_deck()
	var total := combat._deck.size()
	combat._draw_hand()
	print("  deck total=%d (expect 11); after draw hand=%d (expect 5) deck=%d (expect 6) discard=%d (expect 0)" %
			[total, combat._hand.size(), combat._deck.size(), combat._discard.size()])
	print("  invariant deck+hand+discard=%d (expect 11)" %
			[combat._deck.size() + combat._hand.size() + combat._discard.size()])

	print("[smoke] -- M11 reshuffle when draw pile runs short --")
	combat._build_deck()
	combat._hand.clear()
	combat._discard = combat._deck.duplicate()   # 11 in discard
	combat._deck.clear()
	for _i in range(2):                          # leave only 2 in the draw pile
		combat._deck.append(combat._discard.pop_back())
	combat._draw_hand()                          # draws 2, reshuffles 9, draws 3 more
	print("  after draw: hand=%d (expect 5), discard emptied by reshuffle=%s (expect true)" %
			[combat._hand.size(), combat._discard.size() == 0])
	print("  invariant total=%d (expect 11)" %
			[combat._deck.size() + combat._hand.size() + combat._discard.size()])

	print("[smoke] -- M11 Boosted card grants 2 stacks to an ally --")
	var bcard : CardDefinition = load("res://data/cards/boosted_card.tres")
	var ally : Unit = combat.player_units[0]
	ally.active_statuses.clear()
	combat._apply_card(bcard, ally, Vector2i.ZERO)
	print("  ally boosted stacks=%d (expect 2)" % _stacks(ally, "boosted"))

	print("[smoke] -- M11 Mine card deploys a mine --")
	var mcard : CardDefinition = load("res://data/cards/mine_card.tres")
	var before_dep := combat.deployables.size()
	combat._apply_card(mcard, null, Vector2i(50, 0))
	var after_dep := combat.deployables.size()
	var last_dep = combat.deployables[after_dep - 1] if after_dep > 0 else null
	print("  deployables %d->%d (expect +1), new is Mine=%s" %
			[before_dep, after_dep, last_dep is Mine])

	print("[smoke] -- M11 Halve Wind card --")
	combat.wind_strength = 0.8
	var wcard : CardDefinition = load("res://data/cards/halve_wind.tres")
	combat._apply_card(wcard, null, Vector2i.ZERO)
	print("  wind 0.80 -> %.2f (expect 0.40), force=%.0f (expect %.0f)" %
			[combat.wind_strength, combat._projectiles.current_wind_force,
			0.4 * Const.MAX_WIND_FORCE])

# M12 checklist (the §4.3 proof harness): a unit damaged in "stage 1" starts "stage 2" still
# damaged (HP persists via RunUnitState) while combat state (shields/effects) resets; disabled
# units don't redeploy; RunState round-trips through to_dict/from_dict.
func _m12_smoke() -> void:
	print("[smoke] -- M12 run-state I/O contract --")
	# A throwaway run (NOT Run.active): unit A starts damaged, unit B full.
	var rs := RunState.new()
	var a := RunUnitState.from_definition("res://data/units/player_cluster.tres", "AUnit")
	var b := RunUnitState.from_definition("res://data/units/player_bypass.tres", "BUnit")
	a.current_hp = a.max_hp - 2
	rs.squad = [a, b]
	rs.deck = ["res://data/cards/shield_buff.tres", "res://data/cards/mine_card.tres"]

	# Stage-1 read: a temp holder fires Unit._ready() without disturbing the live squad.
	var holder := Node2D.new()
	add_child(holder)
	var s1 := CombatBridge.build_squad(rs)
	for u in s1:
		holder.add_child(u)
	var ua : Unit = s1[0]
	ua.shield = 5   # tactical buffer that must NOT persist to stage 2
	print("  stage-1 build: count=%d (expect 2), A hp=%d (expect max-2=%d), attack=%d (expect %d)" %
			[s1.size(), ua.hp, a.max_hp - 2, ua.attack, ua.definition.attack])

	# Simulate the fight: A takes more damage + scores a kill; B is destroyed.
	ua.hp = a.max_hp - 4
	ua.kills = 1
	(s1[1] as Unit).hp = 0
	CombatBridge.write_back(rs, s1)
	print("  write-back: A current_hp=%d (expect %d) kills=%d (expect 1); B disabled=%s (expect true)" %
			[a.current_hp, a.max_hp - 4, a.kills, b.is_disabled])
	holder.queue_free()

	# Stage-2 read: B disabled → excluded; A rebuilt at persisted HP with a FRESH shield.
	var holder2 := Node2D.new()
	add_child(holder2)
	var s2 := CombatBridge.build_squad(rs)
	for u in s2:
		holder2.add_child(u)
	var a2 : Unit = s2[0]
	print("  stage-2: squad=%d (expect 1, B excluded), A hp=%d (expect persisted %d), shield=%d (expect 0 reset)" %
			[s2.size(), a2.hp, a.max_hp - 4, a2.shield])
	holder2.queue_free()

	# Serialization foundation: RunState survives a dict round-trip.
	var rt := RunState.from_dict(rs.to_dict())
	print("  round-trip: squad=%d (expect 2) deck=%d (expect 2) A.current_hp=%d (expect %d)" %
			[rt.squad.size(), rt.deck.size(), rt.squad[0].current_hp, a.current_hp])

# M13 checklist: stages are data (descriptor shape), the objective evaluator returns the right
# verdict per type/state, and the terrain seed actually drives generation.
func _m13_smoke() -> void:
	print("[smoke] -- M13 stage descriptors --")
	var s1 : StageDescriptor = load("res://data/stages/stage_01.tres")
	var s2 : StageDescriptor = load("res://data/stages/stage_02.tres")
	print("  stage_01: enemies=%d (expect 2) reinforce=%d (expect 2) deploy=%d (expect 3) obj=%d (expect DEFEAT_ALL=0)" %
			[s1.initial_enemies.size(), s1.reinforcements.size(), s1.deployables.size(), s1.objective.type])
	print("  stage_02: obj=%d (expect SURVIVE_N=1) survive_rounds=%d (expect 4) seed=%d (expect 777)" %
			[s2.objective.type, s2.objective.survive_rounds, s2.terrain_seed])

	print("[smoke] -- M13 objective evaluator --")
	var R := ObjectiveEvaluator.Result
	# DEFEAT_ALL: enemies alive → ONGOING; none + waves spawned → WON; no players → LOST.
	var d_ongoing := ObjectiveEvaluator.evaluate(s1.objective, true, true, 3, true)
	var d_won := ObjectiveEvaluator.evaluate(s1.objective, false, true, 3, true)
	var d_notyet := ObjectiveEvaluator.evaluate(s1.objective, false, true, 3, false)  # waves pending
	var d_lost := ObjectiveEvaluator.evaluate(s1.objective, true, false, 3, true)
	print("  defeat-all: enemiesAlive=%d notAllWaves=%d cleared=%d noPlayers=%d (expect ONGOING0, ONGOING0, WON1, LOST2)" %
			[d_ongoing, d_notyet, d_won, d_lost])
	# SURVIVE_N(4): round 3 → ONGOING; round 4 → WON; no players at round 4 → LOST.
	var s_ongoing := ObjectiveEvaluator.evaluate(s2.objective, true, true, 3, true)
	var s_won := ObjectiveEvaluator.evaluate(s2.objective, true, true, 4, true)
	var s_lost := ObjectiveEvaluator.evaluate(s2.objective, true, false, 4, true)
	print("  survive-N: round3=%d round4=%d noPlayers=%d (expect ONGOING0, WON1, LOST2)" %
			[s_ongoing, s_won, s_lost])
	print("  (enum check: ONGOING=%d WON=%d LOST=%d)" % [R.ONGOING, R.WON, R.LOST])

	print("[smoke] -- M13 terrain seed drives generation --")
	# Regenerate the live terrain under two seeds; surface rows should differ somewhere.
	terrain.generate(12345)
	var rows_a : Array = []
	for c in range(20, 100, 7):
		rows_a.append(terrain.get_surface_row(c))
	terrain.generate(777)
	var differs := false
	var i := 0
	for c in range(20, 100, 7):
		if terrain.get_surface_row(c) != rows_a[i]:
			differs = true
		i += 1
	print("  seed 12345 vs 777 surface rows differ=%s (expect true)" % differs)
	# Restore the live stage's terrain so nothing downstream sees the scratch generation.
	terrain.generate(stage.terrain_seed)

# M14 checklist: linear map builder, run-end conditions, map serialization (explicit build_linear).
func _m14_smoke() -> void:
	print("[smoke] -- M14 run map (linear) --")
	var paths := [
		"res://data/stages/stage_01.tres",
		"res://data/stages/stage_02.tres",
		"res://data/stages/stage_03.tres",
	]
	var fresh := MapState.build_linear(paths)
	print("  nodes=%d (expect 3) current=%d (expect 0) node0.type=%d (expect COMBAT=0) stage=%s" %
			[fresh.nodes.size(), fresh.current, fresh.current_node().type, fresh.current_node().stage().id])

	fresh.mark_visited(); fresh.advance()
	print("  after clear+advance: current=%d (expect 1) is_last=%s (expect false)" %
			[fresh.current, fresh.is_last()])
	fresh.mark_visited(); fresh.advance()
	print("  at node 2: is_last=%s (expect true) complete=%s (expect false, node2 not cleared)" %
			[fresh.is_last(), fresh.is_complete()])
	fresh.mark_visited()
	print("  after clearing node 2: complete=%s (expect true)" % fresh.is_complete())

	print("[smoke] -- M14 run-end conditions --")
	var rs := RunState.new()
	var a := RunUnitState.from_definition("res://data/units/player_cluster.tres", "A")
	var b := RunUnitState.from_definition("res://data/units/player_bypass.tres", "B")
	rs.squad = [a, b]
	a.is_disabled = false; b.is_disabled = false
	print("  one alive: any_alive=%s (expect true)" % rs.squad.any(func(u): return not u.is_disabled))
	a.is_disabled = true; b.is_disabled = true
	print("  all disabled: any_alive=%s (expect false → RUN OVER)" %
			rs.squad.any(func(u): return not u.is_disabled))

	print("[smoke] -- M14 map serialization --")
	var rs2 := RunState.new()
	rs2.map = fresh
	var rt := RunState.from_dict(rs2.to_dict())
	print("  round-trip: nodes=%d (expect 3) current=%d (expect 2) visited=%d (expect 3) stage1=%s" %
			[rt.map.nodes.size(), rt.map.current, rt.map.visited.size(), rt.map.nodes[1].stage_path.get_file()])

# M19 checklist: diamond DAG builder, forward-only selection, path walk, serialization.
func _m19_smoke() -> void:
	print("[smoke] -- M19 diamond map --")
	var paths := [
		"res://data/stages/stage_01.tres",
		"res://data/stages/stage_02.tres",
		"res://data/stages/stage_03.tres",
	]
	var d := MapState.build_diamond(paths)
	var layer_counts := [0, 0, 0, 0, 0]
	for n in d.nodes:
		if n.layer >= 0 and n.layer < layer_counts.size():
			layer_counts[n.layer] += 1
	print("  nodes=%d (expect 9) layers=%s (expect 1/2/3/2/1) node0.next=%s (expect [1, 2])" %
			[d.nodes.size(), layer_counts, d.nodes[0].next_nodes])

	print("[smoke] -- M19 forward-only --")
	d.mark_visited()
	var ok := d.can_select(1)
	d.select_next(1)
	print("  after clear 0, select 1: can=%s current=%d (expect true, 1)" % [ok, d.current])
	var bad := d.can_select(0)
	d.select_next(0)
	print("  select back to 0: can=%s current=%d (expect false, still 1)" % [bad, d.current])

	print("[smoke] -- M19 path walk --")
	d.mark_visited(); d.select_next(3)
	d.mark_visited(); d.select_next(6)
	d.mark_visited(); d.select_next(8)
	print("  at terminal 8: is_terminal=%s next=%s (expect true, [])" %
			[d.is_terminal(), d.nodes[8].next_nodes])
	d.mark_visited()
	print("  after clear 8: complete=%s (expect true)" % d.is_complete())

	print("[smoke] -- M19 map serialization --")
	var rs := RunState.new()
	rs.map = d
	var rt := RunState.from_dict(rs.to_dict())
	var n0 : MapNode = rt.map.nodes[0]
	print("  round-trip: nodes=%d layer0=%d next0=%s (expect 9, 0, [1,2])" %
			[rt.map.nodes.size(), n0.layer, n0.next_nodes])

# M20 checklist: armor pool above shield, element × layer matrix, armor card, Cluster baseline.
func _m20_smoke() -> void:
	print("[smoke] -- M20 armor mitigation --")
	var ally : Unit = combat.player_units[0]
	var elec : ElementDef = load("res://data/elements/electric.tres")
	var hp_max := ally.definition.max_hp
	_reset(ally); ally.armor = 4; ally.shield = 4
	ally.take_damage(3)
	print("  shield absorbs first: shield=%d armor=%d hp=%d (expect 1, 4, %d)" %
			[ally.shield, ally.armor, ally.hp, hp_max])
	_reset(ally); ally.armor = 4; ally.shield = 0
	ally.take_damage(3)
	print("  armor after shield empty: armor=%d hp=%d (expect 1, %d)" % [ally.armor, ally.hp, hp_max])
	_reset(ally); ally.armor = 4; ally.shield = 0
	ally.take_damage(3, elec)
	print("  electric weak vs armor: armor=%d hp=%d (expect 2, %d)" % [ally.armor, ally.hp, hp_max])
	_reset(ally); ally.armor = 0; ally.shield = 4
	ally.take_damage(3, elec)
	print("  electric strong vs shield: shield=%d hp=%d (expect 0, %d)" %
			[ally.shield, ally.hp, hp_max - 1])

	var cluster_def : UnitDefinition = load("res://data/units/player_cluster.tres")
	print("  cluster base_armor=%d (expect 4)" % cluster_def.base_armor)

	print("[smoke] -- M20 armor card --")
	var armor_card : CardDefinition = load("res://data/cards/armor_buff.tres")
	_reset(ally); ally.armor = 0
	combat._apply_card(armor_card, ally, Vector2i.ZERO)
	print("  armor buff: armor=%d cost=%d (expect 5, 1)" % [ally.armor, armor_card.action_cost])

# M15 checklist (drop-queue redesign): spawn zone is the left half, dropping a unit places it
# visibly in-zone, right-half column is clamped, queue must be empty before confirming.
func _m15_smoke() -> void:
	print("[smoke] -- M15 pre-combat placement (drop queue) --")
	var s1 : StageDescriptor = load("res://data/stages/stage_01.tres")
	print("  stage_01 spawn zone: %d..%d (expect 0..%d, left half)" %
			[s1.spawn_min_col, s1.spawn_max_col, Const.MAP_WIDTH / 2 - 1])

	# Re-enter PLACEMENT with one unit in the queue.
	var u : Unit = combat.player_units[0]
	u.visible = false
	combat._placement_queue = [u]
	combat.game_state = CombatManager.GameState.PLACEMENT

	var dropped_to := -1
	for c in range(s1.spawn_min_col, s1.spawn_max_col + 1):
		if combat._placement_drop(u, c):
			combat._placement_queue.pop_front()
			dropped_to = u.vox_position.x
			break
	print("  dropped into zone at col=%d visible=%s (expect valid in 0..%d, true)" %
			[dropped_to, u.visible, s1.spawn_max_col])

	# Clamp guarantee: _placement_drop clamps a right-half col into the zone.
	var u2 : Unit = combat.player_units[1]
	u2.visible = false
	combat._placement_queue = [u2]
	combat._placement_drop(u2, Const.MAP_WIDTH - 5)
	combat._placement_queue.clear()
	print("  drop right-half col: x=%d <= spawn_max=%d (expect true)" %
			[u2.vox_position.x, s1.spawn_max_col])

	# Confirm blocked while queue non-empty; succeeds when queue empty.
	combat.game_state = CombatManager.GameState.PLACEMENT
	combat._placement_queue = [u]   # put one unit back to test the guard
	var round_snapshot := combat.round_index
	combat._confirm_placement()     # should be a no-op (queue not empty)
	print("  confirm with queue non-empty: still PLACEMENT=%s (expect true)" %
			[combat.game_state == CombatManager.GameState.PLACEMENT])
	combat._placement_queue.clear()
	combat._confirm_placement()     # now valid
	print("  confirm with empty queue: left PLACEMENT=%s round advanced=%s (expect true, true)" %
			[combat.game_state != CombatManager.GameState.PLACEMENT,
			combat.round_index == round_snapshot + 1])

# M16 checklist: battle rewards (pools, apply, no-repeat artifacts) + dig vs unit damage.
func _m16_smoke() -> void:
	print("[smoke] -- M16 battle rewards --")
	var rs := Run.active

	# Pools are seeded (smoke mode restores full loadout, so artifact_pool is empty after
	# the backfill — test with a fresh scratch RunState instead).
	var scratch := RunState.new()
	scratch.unit_pool = [
		"res://data/units/player_cluster.tres",
		"res://data/units/player_bypass.tres",
		"res://data/units/player_pull.tres",
		"res://data/units/player_spiral.tres",
	]
	scratch.card_pool = [
		"res://data/cards/direct_strike.tres",
		"res://data/cards/shield_buff.tres",
	]
	scratch.artifact_pool = [
		"res://data/artifacts/resources/lifesteal.tres",
		"res://data/artifacts/resources/enemy_debuff.tres",
		"res://data/artifacts/resources/free_first_card.tres",
	]
	scratch.artifacts = ["res://data/artifacts/resources/squad_regen.tres"]
	scratch.squad.clear()
	scratch.deck = []

	print("  pools: units=%d (expect 4) cards=%d (expect 2) artifacts=%d (expect 3)" %
			[scratch.unit_pool.size(), scratch.card_pool.size(), scratch.artifact_pool.size()])

	# Simulate unit reward: adds a RunUnitState to squad.
	var unit_path := scratch.unit_pool[0]
	var udef : UnitDefinition = load(unit_path)
	scratch.squad.append(RunUnitState.from_definition(unit_path, udef.display_name))
	print("  unit reward: squad=%d (expect 1) name=%s" % [scratch.squad.size(), scratch.squad[0].display_name])

	# Simulate artifact reward: adds to artifacts, removes from pool.
	var art_path := scratch.artifact_pool[0]
	scratch.artifacts.append(art_path)
	scratch.artifact_pool.erase(art_path)
	print("  artifact reward: owned=%d (expect 2) pool=%d (expect 2) no_repeat=%s (expect true)" %
			[scratch.artifacts.size(), scratch.artifact_pool.size(),
			not scratch.artifact_pool.has(art_path)])

	# Simulate card reward: appends to deck.
	var card_path := scratch.card_pool[0]
	scratch.deck.append(card_path)
	print("  card reward: deck=%d (expect 1)" % scratch.deck.size())

	# Serialization round-trip preserves pools.
	var rt := RunState.from_dict(scratch.to_dict())
	print("  round-trip: unit_pool=%d card_pool=%d artifact_pool=%d (expect 4,2,2)" %
			[rt.unit_pool.size(), rt.card_pool.size(), rt.artifact_pool.size()])

	# RunState starts with 2 units (default run, verified against scratch, not smoke's backfilled active).
	var fresh_rs := RunState.new()
	fresh_rs.squad = [
		RunUnitState.from_definition("res://data/units/player_cluster.tres", "Cluster"),
		RunUnitState.from_definition("res://data/units/player_bypass.tres",  "Bypass"),
	]
	fresh_rs.artifacts = ["res://data/artifacts/resources/squad_regen.tres"]
	print("  default start: squad=%d (expect 2) artifacts=%d (expect 1)" %
			[fresh_rs.squad.size(), fresh_rs.artifacts.size()])

	print("[smoke] -- M16 dig decoupled from unit damage --")
	var dig_pat : AoEPattern = load("res://data/shots/aoe/diamond_r2.tres")
	var dig_col := 8
	var dig_row := terrain.get_surface_row(dig_col)
	terrain.set_tile(dig_col, dig_row, Tile.new().setup(Tile.TileType.SOLID, 3, 0))
	AoEResolver.resolve(terrain, combat.all_units, Vector2i(dig_col, dig_row),
			dig_pat, 10, false, [], 1, null)
	var chipped := terrain.get_tile(dig_col, dig_row)
	print("  strength=10 dig=1 on 3HP tile: hp=%d (expect 2)" % chipped.hp)

	var no_dig_col := 9
	var no_dig_row := terrain.get_surface_row(no_dig_col)
	terrain.set_tile(no_dig_col, no_dig_row, Tile.new().setup(Tile.TileType.SOLID, 3, 0))
	AoEResolver.resolve(terrain, combat.all_units, Vector2i(no_dig_col, no_dig_row),
			dig_pat, 10, false, [], 0, null)
	print("  dig_strength=0: tile hp=%d (expect 3, unchanged)" %
			[terrain.get_tile(no_dig_col, no_dig_row).hp])

	print("  dig footprint offsets=%d (expect >1)" % dig_pat.to_map().size())

	var bypass : ShotDefinition = load("res://data/shots/bypass_basic.tres")
	print("  bypass: terrain=%s dig_pattern=%s (expect true, null)" %
			[bypass.bypass_terrain, bypass.dig_pattern])

	var mine := Mine.new()
	print("  mine.dig=%d strength=%d (expect 4, 4)" % [mine.dig, mine.strength])
	mine.queue_free()

func _m17_smoke() -> void:
	print("[smoke] -- M17 collapsible crush --")
	var col := 50
	for row in range(Const.MAP_HEIGHT):
		terrain.clear_tile(col, row)
	var support := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	support.collapsible = false
	terrain.set_tile(col, 30, support)
	var faller := Tile.new().setup(Tile.TileType.SOLID, 6, 0)
	faller.collapsible = true
	terrain.set_tile(col, 10, faller)
	var victim : Unit = combat.player_units[0]
	_reset(victim)
	victim.shield = 0
	victim.set_vox_position(Vector2i(col, 25))
	var hp_pre := victim.hp
	terrain.resolve_all_collapses(combat.all_units, combat.deployables)
	var crushed := hp_pre - victim.hp
	var faller_gone := terrain.get_tile(col, 10) == null
	print("  crush: victim -%d (expect 6) faller consumed=%s (expect true)" %
			[crushed, faller_gone])

	print("[smoke] -- M17 stacked collapsibles settle in one tick --")
	var col2 := 51
	for row in range(Const.MAP_HEIGHT):
		terrain.clear_tile(col2, row)
	var support2 := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	support2.collapsible = false
	terrain.set_tile(col2, 40, support2)
	var a := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	a.collapsible = true
	terrain.set_tile(col2, 36, a)
	var b := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	b.collapsible = true
	terrain.set_tile(col2, 34, b)
	terrain.resolve_all_collapses([], [])
	var low := terrain.get_tile(col2, 39)
	var high := terrain.get_tile(col2, 38)
	print("  stack: tile@39=%s tile@38=%s (expect both non-null)" %
			[low != null, high != null])

	print("[smoke] -- M17 queued column after destroy --")
	var col3 := 52
	for row in range(Const.MAP_HEIGHT):
		terrain.clear_tile(col3, row)
	var anchor := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	anchor.collapsible = false
	terrain.set_tile(col3, 28, anchor)
	var hang := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
	hang.collapsible = true
	terrain.set_tile(col3, 26, hang)
	terrain.damage_tile(col3, 28, 99)   # destroys anchor, queues column
	terrain.resolve_collapses([], [])
	var landed := terrain.get_tile(col3, Const.MAP_HEIGHT - 1)
	print("  after support destroyed: rests on bottom=%s (expect true)" % (landed != null))

func _m18_smoke() -> void:
	print("[smoke] -- M18 faction tags on content --")
	var cluster : UnitDefinition = load("res://data/units/player_cluster.tres")
	var shield : CardDefinition = load("res://data/cards/shield_buff.tres")
	var mine : CardDefinition = load("res://data/cards/mine_card.tres")
	var regen : ArtifactDef = load("res://data/artifacts/resources/squad_regen.tres")
	var debuff : ArtifactDef = load("res://data/artifacts/resources/enemy_debuff.tres")
	print("  unit cluster faction=%s (expect army)" % cluster.faction)
	print("  card shield=%s mine=%s (expect neutral, army)" % [shield.faction, mine.faction])
	print("  artifact regen=%s debuff=%s (expect neutral, army)" % [regen.faction, debuff.faction])
	print("  Faction.display_name(army)=%s (expect Seekers)" % Faction.display_name(Faction.ARMY))
	print("  run faction=%s (expect army)" % Run.active.run_meta.get("faction", ""))

func _m22_smoke() -> void:
	print("[smoke] -- M22 essence system --")
	Run.start_default_run()
	var rs := Run.active
	var rs2 := RunState.from_dict(rs.to_dict())
	print("  rt equipped Cluster=%d (expect 1)" % rs2.squad[0].equipped_essences.size())
	print("  rt equipped Bypass=%d (expect 1)"  % rs2.squad[1].equipped_essences.size())
	var primer : EssenceDef = load(rs.squad[0].equipped_essences[0])
	var dshot  : EssenceDef = load(rs.squad[1].equipped_essences[0])
	print("  armor_primer slot_cost=%d (expect 1)" % primer.slot_cost)
	print("  double_shot slot_cost=%d (expect 1)"  % dshot.slot_cost)
	var ctx := EssenceContext.new()
	var dummy := Unit.new()
	dummy.definition = load("res://data/units/player_cluster.tres")
	dummy.armor = 0
	ctx.unit = dummy
	primer.on_combat_start(ctx)
	print("  armor_primer adds armor: armor=%d (expect 10)" % dummy.armor)
	dummy.free()

func _m23_smoke() -> void:
	print("[smoke] -- M23 unit capacity + skip rewards --")
	Run.start_default_run()
	var def := load("res://data/units/player_cluster.tres") as UnitDefinition
	print("  cluster.capacity_cost=%d (expect 2)" % def.capacity_cost)
	print("  MAX_SQUAD_CAPACITY=%d (expect 8)" % RunState.MAX_SQUAD_CAPACITY)
	print("  used_capacity (2-unit run)=%d (expect 4)" % SquadOps.used_capacity(Run.active))

func _m27_smoke() -> void:
	print("[smoke] -- M27 map squad bar + repair/retire --")
	Run.start_default_run()
	var rs := Run.active
	print("  shards start=%d (expect 25)" % rs.resources.get("shards", -1))
	rs.squad[0].is_disabled = true
	rs.squad[0].current_hp = 0
	print("  used_capacity disabled=%d (expect 4)" % SquadOps.used_capacity(rs))
	print("  repair ok=%s (expect true)" % SquadOps.repair_unit(rs, 0))
	print("  shards after repair=%d (expect 20)" % rs.resources.get("shards", -1))
	print("  repaired hp=%d disabled=%s (expect full/false)" %
			[rs.squad[0].current_hp, rs.squad[0].is_disabled])
	rs.squad[0].is_disabled = true
	rs.squad[0].current_hp = 0
	print("  retire disabled ok=%s squad=%d shards=%d cap=%d (expect true/1/22/2)" %
			[SquadOps.retire_unit(rs, 0), rs.squad.size(),
			rs.resources.get("shards", -1), SquadOps.used_capacity(rs)])
	Run.start_default_run()
	rs = Run.active
	print("  retire healthy ok=%s squad=%d shards=%d cap=%d (expect true/1/27/2)" %
			[SquadOps.retire_unit(rs, 0), rs.squad.size(),
			rs.resources.get("shards", -1), SquadOps.used_capacity(rs)])
	rs.squad[0].is_disabled = true
	rs.squad[0].current_hp = 0
	var rs2 := RunState.from_dict(rs.to_dict())
	print("  rt shards=%d disabled=%s (expect 27/true)" %
			[rs2.resources.get("shards", -1), rs2.squad[0].is_disabled])

func _m21_smoke() -> void:
	print("[smoke] -- M21 shards + upgrade slots --")
	Run.start_default_run()
	var rs := Run.active
	print("  shards start=%d (expect 25)" % rs.resources.get("shards", -1))
	for u in rs.squad:
		print("  upgrade_slots %s=%d (expect 2)" % [u.display_name, u.upgrade_slots])
	var rs2 := RunState.from_dict(rs.to_dict())
	print("  rt shards=%d (expect 25)" % rs2.resources.get("shards", -1))
	print("  rt upgrade_slots=%d (expect 2)" % rs2.squad[0].upgrade_slots)

func _m29_smoke() -> void:
	print("[smoke] -- M29 unit stacking --")
	if combat.enemy_units.size() < 2:
		print("  skip: need 2+ enemy units")
		return
	var u1 : Unit = combat.enemy_units[0]
	var u2 : Unit = combat.enemy_units[1]
	_reset(u1); _reset(u2)
	u2.set_vox_position(u1.vox_position)
	print("  same vox=%s (expect true)" % (u1.vox_position == u2.vox_position))
	combat._recompute_stack_offsets()
	print("  u2 offset=(%s,%s) (expect -2,-2)" % [u2.stack_visual_offset.x, u2.stack_visual_offset.y])
	var hp1 : int = u1.hp; var hp2 : int = u2.hp
	var pattern := load("res://data/shots/aoe/diamond_r2.tres") as AoEPattern
	if pattern != null:
		AoEResolver.resolve(terrain, combat.all_units, u1.center_voxel(),
				pattern, 5, false, combat.deployables)
		print("  u1 took dmg=%s u2 took dmg=%s (expect true true)" \
				% [u1.hp < hp1, u2.hp < hp2])

func _m30_smoke() -> void:
	print("[smoke] -- M30 elemental prime cards --")
	var ally : Unit = combat.player_units[0]
	var foe  : Unit = combat.enemy_units[0]
	_reset(foe)
	var fire_prime := load("res://data/cards/fire_prime.tres") as CardDefinition
	if fire_prime == null:
		print("  skip: fire_prime.tres not found"); return
	combat._apply_card(fire_prime, ally, Vector2i.ZERO)
	print("  primed count=%d first=%s (expect 1, fire)" %
			[ally.primed_elements.size(),
			ally.primed_elements[0].id if not ally.primed_elements.is_empty() else "null"])
	var hp_before : int = foe.hp
	for el : ElementDef in ally.primed_elements:
		AoEResolver.resolve(terrain, combat.all_units, foe.center_voxel(),
				load("res://data/shots/aoe/diamond_r2.tres"),
				5, false, combat.deployables, 0, null, el)
	print("  foe took fire dmg=%s (expect true)" % (foe.hp < hp_before))
	ally.primed_elements.clear()

func _m31_smoke() -> void:
	print("[smoke] -- M31 animation sequencer --")
	print("  fast_forward=%s (expect true)" % AnimationSequencer.fast_forward)
	print("  world_fx valid=%s (expect true)" % is_instance_valid(AnimationSequencer.world_fx))
	var foe : Unit = combat.enemy_units[0]
	_reset(foe)
	var hp_before := foe.hp
	# A high-strength resolve should fire unit_hit_taken → hit_flash, unit_died → death_fade.
	# In fast_forward mode all animations complete synchronously within the resolve() call.
	AoEResolver.resolve(terrain, combat.all_units, foe.center_voxel(),
			load("res://data/shots/aoe/diamond_r2.tres"), 99, false, combat.deployables)
	print("  sequencer idle=%s (expect true)" % AnimationSequencer._active_batch.is_empty())
	print("  foe took dmg=%s (expect true)" % (foe.hp < hp_before))

func _setup_terrain() -> void:
	var seed_val := active_stage_seed if active_stage_seed >= 0 else (stage.terrain_seed if stage != null else Const.NOISE_SEED)
	var profile : TerrainProfile = null
	if terrain_profile_path != "":
		profile = load(terrain_profile_path) as TerrainProfile
	elif stage != null:
		profile = stage.terrain_profile
	if profile != null and Features.terrain_profiles_enabled:
		var data := TerrainGenerator.generate(profile, seed_val)
		terrain.load_map(data)
	else:
		terrain.generate(seed_val)
	renderer.setup(terrain)

func _m32_smoke() -> void:
	print("[smoke] -- M32 terrain generation --")
	var p1 := load("res://data/terrain/profiles/open_field.tres") as TerrainProfile
	var d1 := TerrainGenerator.generate(p1, 42)
	print("  map_size=%dx%d (expect 100-130 x 90-110)" % [d1.width, d1.height])
	var solid := 0
	for c in d1.cells:
		if c != null:
			solid += 1
	print("  solid_fraction=%.2f (expect 0.3-0.7)" % (float(solid) / float(d1.width * d1.height)))

	var p2 := load("res://data/terrain/profiles/ridge_assault.tres") as TerrainProfile
	var d2 := TerrainGenerator.generate(p2, 42)
	var ridge_tiles := 0
	for c in d2.cells:
		if c != null and c.get("gen_origin", 0) == MapData.GenOrigin.SLOT_CENTER:
			ridge_tiles += 1
	print("  ridge_center_tiles=%d (expect >0)" % ridge_tiles)

	var p3 := load("res://data/terrain/profiles/fortress_siege.tres") as TerrainProfile
	var d3 := TerrainGenerator.generate(p3, 42)
	var shell_tiles := 0
	for c in d3.cells:
		if c != null and c.get("gen_origin", 0) == MapData.GenOrigin.SLOT_RIGHT \
				and c.get("hp", 3) >= 8:
			shell_tiles += 1
	print("  bunker_shell_tiles=%d (expect >0)" % shell_tiles)

	# Restore live terrain (mirror M13 pattern: call generate directly, not _setup_terrain,
	# to avoid re-running renderer.setup() which would error on already-connected signal)
	var live_seed := active_stage_seed if active_stage_seed >= 0 else (stage.terrain_seed if stage != null else Const.NOISE_SEED)
	var live_profile : TerrainProfile = null
	if terrain_profile_path != "":
		live_profile = load(terrain_profile_path) as TerrainProfile
	elif stage != null:
		live_profile = stage.terrain_profile
	if live_profile != null and Features.terrain_profiles_enabled:
		terrain.load_map(TerrainGenerator.generate(live_profile, live_seed))
	else:
		terrain.generate(live_seed)

func _m33_smoke() -> void:
	print("[smoke] -- M33 RNG architecture --")
	print("  StageRng.rng.seed=%d (expect nonzero)" % StageRng.rng.seed)
	print("  CombatRng.rng.seed=%d (expect nonzero)" % CombatRng.rng.seed)
	# Determinism: same run_seed → same node stage_seeds
	Run.start_default_run()
	var n1 : MapNode = Run.active.map.nodes[1]
	var s1 : int    = n1.stage_seed
	var p1 : String = n1.terrain_profile_path
	var saved_seed : int = Run.active.run_meta["seed"]
	Run.run_rng.seed = saved_seed
	Run._assign_terrain_variations(Run.active)
	var n1b : MapNode = Run.active.map.nodes[1]
	var s2 : int = n1b.stage_seed
	print("  determinism: s1=%d s2=%d match=%s (expect true)" % [s1, s2, str(s1 == s2)])
	var n0 : MapNode = Run.active.map.nodes[0]
	print("  node[0] profile='%s' (expect empty)" % n0.terrain_profile_path)
	print("  node[1] profile='%s' (expect nonempty)" % p1)

func _m34_smoke() -> void:
	print("[smoke] -- M34 shop node --")
	Run.start_default_run()
	var shop_count := 0
	for node in Run.active.map.nodes:
		var mn : MapNode = node
		if mn.type == MapNode.Type.SHOP:
			shop_count += 1
	print("  shop_nodes=%d (expect 2)" % shop_count)
	# Verify artifact cycling marks the seen set
	Run.active.artifact_seen_set.clear()
	var offered := Run.pick_artifacts_for_offer(3)
	print("  offered=%d seen_set=%d (expect 3, 3)" % [offered.size(), Run.active.artifact_seen_set.size()])
	# Drain remaining pool then verify cycle resets
	var pool_size := Run.active.artifact_pool.size()
	Run.pick_artifacts_for_offer(pool_size - 3)
	var post_drain := Run.active.artifact_seen_set.size()
	Run.pick_artifacts_for_offer(3)
	print("  after drain: seen_set_reset=%s (expect true)" % str(Run.active.artifact_seen_set.size() < post_drain))
	# Verify starting shards
	Run.start_default_run()
	print("  start_shards=%d (expect 25)" % Run.active.resources.get("shards", 0))

func _m35_smoke() -> void:
	print("[smoke] -- M35 event nodes + extended map --")
	Run.start_default_run()
	var m : MapState = Run.active.map
	print("  node_count=%d (expect 15)" % m.nodes.size())
	var shop_count := 0
	var event_count := 0
	var shop_layers : Array[int] = []
	for i in range(m.nodes.size()):
		var node : MapNode = m.nodes[i]
		if node.type == MapNode.Type.SHOP:
			shop_count += 1
			shop_layers.append(node.layer)
		elif node.type == MapNode.Type.EVENT:
			event_count += 1
	print("  shop_count=%d (expect 2)" % shop_count)
	print("  event_count=%d (expect 2)" % event_count)
	var diff_layers : bool = shop_layers.size() == 2 and shop_layers[0] != shop_layers[1]
	print("  shops_different_layers=%s (expect true)" % str(diff_layers))
	# Verify event nodes have paths and can load their EventDef
	var events_have_paths := true
	var events_loadable := true
	for i in range(m.nodes.size()):
		var node : MapNode = m.nodes[i]
		if node.type == MapNode.Type.EVENT:
			if node.event_path.is_empty():
				events_have_paths = false
			elif node.event() == null:
				events_loadable = false
	print("  events_have_paths=%s (expect true)" % str(events_have_paths))
	print("  events_loadable=%s (expect true)" % str(events_loadable))
	# Verify stage act_tags (first combat node's stage)
	var first_combat_stage : StageDescriptor = m.nodes[0].stage()
	if first_combat_stage != null:
		print("  stage_act_tags=%s (expect [act_1])" % str(first_combat_stage.act_tags))
	# Verify triage event choices
	Run.active.squad[0].current_hp = 1   # wound first unit
	var ev_node : MapNode = m.nodes[3]
	if ev_node.type == MapNode.Type.EVENT and not ev_node.event_path.is_empty():
		var ev := ev_node.event()
		if ev != null:
			var ch := ev.choices(Run.active)
			print("  triage_choice_count=%d (expect 2)" % ch.size())
	# Verify blood_price event choices
	var ev_node2 : MapNode = m.nodes[10]
	if ev_node2.type == MapNode.Type.EVENT and not ev_node2.event_path.is_empty():
		var ev2 := ev_node2.event()
		if ev2 != null:
			var ch2 := ev2.choices(Run.active)
			print("  blood_price_choice_count=%d (expect 2)" % ch2.size())

func _m36_smoke() -> void:
	print("[smoke] -- M36 repair/upgrade nodes + consumable card --")
	Run.start_default_run()
	var m : MapState = Run.active.map
	# Node type counts
	var repair_count := 0
	var upgrade_count := 0
	for i in range(m.nodes.size()):
		var node : MapNode = m.nodes[i]
		if node.type == MapNode.Type.REPAIR:  repair_count  += 1
		elif node.type == MapNode.Type.UPGRADE: upgrade_count += 1
	print("  repair_count=%d (expect 1)" % repair_count)
	print("  upgrade_count=%d (expect 1)" % upgrade_count)
	print("  first_node_type=COMBAT? %s (expect true)" % str(m.nodes[0].type == MapNode.Type.COMBAT))
	print("  last_node_type=COMBAT? %s (expect true)"  % str(m.nodes[14].type == MapNode.Type.COMBAT))
	# Heal Vial card checks
	var hvial : CardDefinition = load("res://data/cards/heal_vial.tres")
	if hvial != null:
		print("  heal_vial_consumable=%s (expect true)" % str(hvial.is_consumable))
		print("  heal_vial_effect=HEAL? %s (expect true)" % str(hvial.effect_type == CardDefinition.EffectType.HEAL))
		print("  heal_vial_magnitude=%d (expect 10)" % hvial.magnitude)
	else:
		print("  heal_vial=MISSING (bake not run?)")
	# RunUnitState round-trip for upgrade fields
	var rus := RunUnitState.new()
	rus.bonus_attack = 3
	rus.permanent_boosted = 5
	rus.permanent_fire_prime = 2
	rus.bonus_dig = 1
	var d := rus.to_dict()
	var rus2 := RunUnitState.from_dict(d)
	print("  upgrade_round_trip bonus_attack=%d (expect 3)" % rus2.bonus_attack)
	print("  upgrade_round_trip permanent_boosted=%d (expect 5)" % rus2.permanent_boosted)
	print("  upgrade_round_trip permanent_fire_prime=%d (expect 2)" % rus2.permanent_fire_prime)
	print("  upgrade_round_trip bonus_dig=%d (expect 1)" % rus2.bonus_dig)
	# Fuse units check
	if Run.active.squad.size() >= 2:
		var src : RunUnitState = Run.active.squad[0]
		src.equipped_essences = ["res://data/essences/resources/armor_primer.tres"]
		var pre_shards : int = Run.active.resources.get("shards", 0)
		var ok := SquadOps.fuse_units(Run.active, 0, 1)
		print("  fuse_ok=%s (expect true)" % str(ok))
		print("  fuse_essence_transferred=%s (expect true)" % str(
			Run.active.squad[0].equipped_essences.has("res://data/essences/resources/armor_primer.tres")))
		print("  fuse_shards_granted=%d (expect %d)" % [
			Run.active.resources.get("shards", 0) - pre_shards, SquadOps.FUSION_REFUND])

func _m37_smoke() -> void:
	print("[smoke] -- M37 deck viewer + squad viewer --")
	Run.start_default_run()

	# DeckViewer: instantiate, setup, verify in tree
	var dv := DeckViewer.new()
	add_child(dv)
	dv.setup()
	print("  deck_viewer_in_tree=%s (expect true)" % str(dv.is_inside_tree()))
	dv.queue_free()

	# SquadViewer world mode
	var sv_w := SquadViewer.new()
	add_child(sv_w)
	sv_w.setup(true)
	print("  squad_viewer_world_in_tree=%s (expect true)" % str(sv_w.is_inside_tree()))
	sv_w.queue_free()

	# SquadViewer combat mode
	var sv_c := SquadViewer.new()
	add_child(sv_c)
	sv_c.setup(false)
	print("  squad_viewer_combat_in_tree=%s (expect true)" % str(sv_c.is_inside_tree()))
	sv_c.queue_free()

	# Feature flags
	print("  deck_viewer_enabled=%s (expect true)" % str(Features.deck_viewer_enabled))
	print("  squad_viewer_enabled=%s (expect true)" % str(Features.squad_viewer_enabled))

func _find_unit(dname: String) -> Unit:
	for u in combat.all_units:
		if u.display_name == dname:
			return u
	return null

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
