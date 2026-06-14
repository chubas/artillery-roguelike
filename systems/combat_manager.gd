# Combat orchestration (M2 spec §4, §5, §8, §9.2): game state, turn loop, shared
# action bar, unit selection, movement, Gunbound firing, enemy turn, win/loss.
class_name CombatManager
extends Node2D

signal action_bar_changed(current: int, maximum: int)
signal unit_focused(unit: Unit)   # selection changed → CombatScene pans the camera

enum GameState { PLAYER_TURN, ENEMY_TURN, STAGE_CLEAR, GAME_OVER }

const NO_MOVE := Vector2i(-9999, -9999)

var game_state : GameState = GameState.PLAYER_TURN
var actions_left : int = Const.MAX_ACTIONS
var round_index : int = 0

var player_units : Array = []
var enemy_units : Array = []
var all_units : Array = []
var active_unit : Unit = null

var charging : bool = false
var charge_frac : float = 0.0

var _checkpoint_positions : Dictionary = {}  # Unit -> Vector2i
var _checkpoint_actions_left : int = 0

var _terrain : TerrainManager
var _projectiles : ProjectileManager
var _unit_layer : Node2D
var _hud : HUD
var _targeting : TargetingUI

func setup(terrain: TerrainManager, projectiles: ProjectileManager,
		unit_layer: Node2D, hud: HUD, targeting: TargetingUI) -> void:
	_terrain = terrain
	_projectiles = projectiles
	_unit_layer = unit_layer
	_hud = hud
	_targeting = targeting
	_hud.end_turn_pressed.connect(end_player_turn)
	_hud.undo_pressed.connect(try_undo)
	_hud.shot_selected.connect(_select_shot)
	# Auto-advance to the next unit only once a player shot has FULLY resolved (§ resolution
	# routine in ProjectileManager), so the camera lingers on the impact before panning.
	_projectiles.shot_resolved.connect(_on_shot_resolved)
	# Gameplay events route through EventBus (M3): the resolver emits aoe_resolved there.
	EventBus.aoe_resolved.connect(_on_aoe_resolved)
	_spawn_all_units()
	_begin_round()

func get_units() -> Array:
	return all_units

# --- Spawning (M2 spec §9.3, surface-snap + no-overlap per plan §1.5) -----------
func _spawn_all_units() -> void:
	# M3 test scenario (§10), adapted to the 120-wide map: players at 12/15, an
	# ORGANIC enemy (weak to fire) and a MECHANICAL enemy (weak to electric) to the east.
	var heavy : UnitDefinition = load("res://data/units/player_heavy.tres")
	var light : UnitDefinition = load("res://data/units/player_light.tres")
	var organic : UnitDefinition = load("res://data/units/enemy_organic.tres")
	var mechanical : UnitDefinition = load("res://data/units/enemy_mechanical.tres")
	player_units.append(_spawn(heavy, "Unit1", 12, true))
	player_units.append(_spawn(light, "Unit2", 15, true))
	enemy_units.append(_spawn(organic, "EnemyA", Const.MAP_WIDTH - 20, false))
	enemy_units.append(_spawn(mechanical, "EnemyB", Const.MAP_WIDTH - 14, false))
	all_units = player_units + enemy_units

func _spawn(def: UnitDefinition, unit_name: String, col: int, is_player: bool) -> Unit:
	var u := Unit.new()
	u.definition = def
	u.is_player = is_player
	u.display_name = unit_name
	u.aim_angle_deg = 45.0 if is_player else 135.0   # face the opposing side
	var pos := _find_valid_spawn(col, def)
	u.set_vox_position(pos)
	_unit_layer.add_child(u)
	u.unit_died.connect(_on_unit_died)
	return u

func _find_valid_spawn(preferred_col: int, def: UnitDefinition) -> Vector2i:
	# Try the preferred column, then alternate outward (+1, -1, +2, -2, ...).
	for i in range(0, 21):
		var off := (i + 1) / 2 * (1 if i % 2 == 1 else -1) if i > 0 else 0
		var col := preferred_col + off
		if col < 0 or col + def.width_voxels > Const.MAP_WIDTH:
			continue
		var surface := _terrain.get_surface_row(col)
		if surface == -1:
			continue
		var top_left := Vector2i(col, surface - def.height_voxels)
		if top_left.y < 0:
			continue
		if not _bbox_terrain_clear(top_left, def.width_voxels, def.height_voxels):
			continue
		if _overlaps_any_unit(top_left, def, null):
			continue
		return top_left
	push_error("No valid spawn near col %d" % preferred_col)
	return Vector2i(preferred_col, 0)

# --- Turn loop (M2 §4.1 + M3 §6 resolution order) --------------------------------
# Round start → tile statuses tick → player turn (unit statuses tick, shock AP cut) →
# player actions → enemy turn (enemy statuses tick → enemy fire) → next round.
func _begin_round() -> void:
	if _is_terminal():
		return
	round_index += 1
	EventBus.round_started.emit(round_index)
	# 1. Tile statuses tick (burning damages/spreads, electrified chains/decays).
	TileStatusSystem.tick_all(_terrain, all_units)
	if _is_terminal():
		return
	_start_player_turn()

func _start_player_turn() -> void:
	if _is_terminal():
		return
	game_state = GameState.PLAYER_TURN
	# 2. Player unit statuses tick (burn damage); accumulate Shock AP reduction.
	var ap_reduction := 0
	for u in player_units:
		ap_reduction += UnitStatusSystem.tick_all(u)
	if _is_terminal():
		return
	# 3. Shock AP reduction applied to the shared pool for this turn.
	actions_left = maxi(0, Const.MAX_ACTIONS - ap_reduction)
	action_bar_changed.emit(actions_left, Const.MAX_ACTIONS)
	for u in player_units:
		u.reset_for_turn()
	_save_checkpoint()
	_select_first_available()
	EventBus.turn_started.emit("player")

func end_player_turn() -> void:
	if game_state != GameState.PLAYER_TURN:
		return
	charging = false
	charge_frac = 0.0
	for u in player_units:
		if u.hp > 0:
			u.mark_done()
	_set_selection(null)
	EventBus.turn_ended.emit("player")
	game_state = GameState.ENEMY_TURN
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	EventBus.turn_started.emit("enemy")
	# 5. Enemy unit statuses tick (burn on enemies). No enemy action pool in M3, so Shock
	#    AP reduction is moot for enemies (spec §6 step 6 is post-M2).
	for e in enemy_units:
		UnitStatusSystem.tick_all(e)
	if _is_terminal():
		return
	# 7. Enemy actions: fire one at a time; wait for each shot to fully resolve.
	for e in enemy_units:
		if _is_terminal():
			return
		if e.hp <= 0:
			continue
		await get_tree().create_timer(Const.ENEMY_FIRE_DELAY).timeout
		if _is_terminal():
			return
		EnemySystem.fire_enemy(e, player_units, _projectiles)
		# Wait for the shot to fully resolve (flight + resolution routine + settle beat).
		while _projectiles.is_busy():
			await get_tree().create_timer(0.1).timeout
	EventBus.turn_ended.emit("enemy")
	if _is_terminal():
		return
	_begin_round()

func _is_terminal() -> bool:
	return game_state == GameState.STAGE_CLEAR or game_state == GameState.GAME_OVER

# --- Win / loss (M2 spec §8): checked on every death, mid-turn included -----------
func _on_unit_died(_unit: Unit) -> void:
	var enemies_alive := enemy_units.any(func(u): return u.hp > 0)
	var players_alive := player_units.any(func(u): return u.hp > 0)
	if not enemies_alive:
		print("[STAGE CLEAR] All enemies defeated.")
		game_state = GameState.STAGE_CLEAR
		_hud.set_turn_text("STAGE CLEAR")
		_set_selection(null)
	elif not players_alive:
		print("[GAME OVER] All player units destroyed.")
		game_state = GameState.GAME_OVER
		_hud.set_turn_text("GAME OVER")
		_set_selection(null)

# --- Selection (M2 spec §5.1) ------------------------------------------------------
func _set_selection(u: Unit) -> void:
	if active_unit != null and is_instance_valid(active_unit):
		active_unit.set_selected(false)
	active_unit = u
	if u != null:
		u.set_selected(true)
		# Focus = pan the camera to this (allied) unit. Tab cycle, click, first-available
		# and post-fire auto-advance all flow through here, so all of them focus.
		unit_focused.emit(u)

func _select_first_available() -> void:
	for u in player_units:
		if u.hp > 0 and not u.is_done:
			_set_selection(u)
			return
	_set_selection(null)

func _tab_cycle() -> void:
	var living := player_units.filter(func(u): return u.hp > 0)
	if living.is_empty():
		return
	# Skip Done units if at least one is not Done; else cycle all (review mode).
	var pool := living.filter(func(u): return not u.is_done)
	if pool.is_empty():
		pool = living
	var idx := pool.find(active_unit)
	_set_selection(pool[(idx + 1) % pool.size()])

func _try_click_select(world_pos: Vector2) -> void:
	for u in player_units:
		if u.bounds_rect_world().has_point(world_pos):
			_set_selection(u)
			return

# --- Movement (M2 spec §5.2 + unit-collision rule from plan §1.5) -----------------
func try_move(unit: Unit, direction: int) -> void:
	if game_state != GameState.PLAYER_TURN or charging:
		return
	if unit == null or unit.is_done or unit.hp <= 0:
		return
	if actions_left < 1:
		return
	if unit.actions_spent_moving >= unit.definition.move_range:
		return
	var dest := _resolve_move(unit, direction)
	if dest == NO_MOVE:
		return
	unit.set_vox_position(dest)
	unit.actions_spent_moving += 1
	actions_left -= 1
	action_bar_changed.emit(actions_left, Const.MAX_ACTIONS)
	EventBus.unit_moved.emit(unit)

func _resolve_move(unit: Unit, direction: int) -> Vector2i:
	var w := unit.definition.width_voxels
	var h := unit.definition.height_voxels
	var new_x := unit.vox_position.x + direction
	if new_x < 0 or new_x + w > Const.MAP_WIDTH:
		return NO_MOVE
	var foot := unit.vox_position.y + h - 1
	# Flat / fall candidate.
	if _bbox_terrain_clear(Vector2i(new_x, foot - h + 1), w, h):
		var f := foot
		while f < Const.MAP_HEIGHT - 1 and not _grounded(new_x, f, w):
			f += 1
		return _final_if_unit_free(new_x, f, unit)
	# Climb candidate: 1 voxel up (climb_max; 2+ is blocked).
	if unit.definition.climb_max >= 1 \
			and _bbox_terrain_clear(Vector2i(new_x, foot - h), w, h):
		return _final_if_unit_free(new_x, foot - 1, unit)
	return NO_MOVE

func _bbox_terrain_clear(top_left: Vector2i, w: int, h: int) -> bool:
	for col in range(top_left.x, top_left.x + w):
		for row in range(top_left.y, top_left.y + h):
			if _terrain.is_blocked(col, row):
				return false
	return true

func _grounded(x: int, foot: int, w: int) -> bool:
	if foot >= Const.MAP_HEIGHT - 1:
		return true   # map bottom counts as support
	for col in range(x, x + w):
		if _terrain.is_solid(col, foot + 1):
			return true
	return false

func _final_if_unit_free(x: int, foot: int, unit: Unit) -> Vector2i:
	var top_left := Vector2i(x, foot - unit.definition.height_voxels + 1)
	if _overlaps_any_unit(top_left, unit.definition, unit):
		return NO_MOVE
	return top_left

func _overlaps_any_unit(top_left: Vector2i, def: UnitDefinition, exclude: Unit) -> bool:
	var rect := Rect2i(top_left, Vector2i(def.width_voxels, def.height_voxels))
	for u in all_units:
		if u == exclude or u.hp <= 0:   # dead wrecks don't block
			continue
		var other := Rect2i(u.vox_position,
			Vector2i(u.definition.width_voxels, u.definition.height_voxels))
		if rect.intersects(other):
			return true
	return false

# --- Checkpoint save: called at turn start and after each firing event ------------
func _save_checkpoint() -> void:
	_checkpoint_positions.clear()
	_checkpoint_actions_left = actions_left
	for u in player_units:
		if u.hp > 0 and not u.is_done:
			_checkpoint_positions[u] = u.vox_position

# --- Undo: restores ALL unfired player units to the last checkpoint ---------------
func can_undo() -> bool:
	return game_state == GameState.PLAYER_TURN and not charging \
		and actions_left < _checkpoint_actions_left

func try_undo() -> void:
	if not can_undo():
		return
	for u in _checkpoint_positions:
		if is_instance_valid(u) and u.hp > 0 and not u.is_done:
			u.set_vox_position(_checkpoint_positions[u])
			u.actions_spent_moving = 0
			_settle_unit(u)
	actions_left = _checkpoint_actions_left
	action_bar_changed.emit(actions_left, Const.MAX_ACTIONS)

# --- Firing (Gunbound model; ends activation per spec §5.4, M3 §7 action cost) -----
func _fire_active() -> void:
	var u := active_unit
	charging = false
	if u == null or u.is_done or u.hp <= 0:
		charge_frac = 0.0
		return
	var shot := u.get_active_shot()
	# Elemental shells cost action points (basic = 0). Can't afford → abort the shot.
	if actions_left < shot.action_cost:
		charge_frac = 0.0
		return
	# Player full-charge speed is boosted (Const.PLAYER_POWER_MULT); enemies use raw IK.
	var speed := lerpf(Const.MIN_PROJECTILE_SPEED,
			shot.base_speed * Const.PLAYER_POWER_MULT, charge_frac)
	charge_frac = 0.0
	if shot.action_cost > 0:
		actions_left -= shot.action_cost
		action_bar_changed.emit(actions_left, Const.MAX_ACTIONS)
	_projectiles.fire(u.barrel_origin_world(), u.aim_dir(), speed, shot, false)
	EventBus.unit_fired.emit(u, shot)
	u.mark_done()
	_save_checkpoint()
	# NOTE: the next unit is NOT focused here. The camera follows the projectile, then lingers
	# on the impact while the shot resolves; _on_shot_resolved advances once that's done.

# A shot finished its full resolution routine. For player shots, focus the next available
# unit now (camera pans to it); enemy shots are sequenced by _run_enemy_turn's own wait.
func _on_shot_resolved(is_enemy: bool) -> void:
	if is_enemy or game_state != GameState.PLAYER_TURN:
		return
	for next in player_units:
		if next.hp > 0 and not next.is_done:
			_set_selection(next)
			return
	_set_selection(null)   # all player units done → HUD shows the end-turn prompt

# --- Shot selection (M3 §8): keys 1/2/3 or HUD chips set active_unit.selected_shot ----
func _select_shot(idx: int) -> void:
	if game_state != GameState.PLAYER_TURN or charging:
		return
	if active_unit == null or active_unit.is_done or active_unit.hp <= 0:
		return
	var shots := active_unit.available_shots()
	if idx >= 0 and idx < shots.size():
		active_unit.selected_shot = shots[idx]

# --- Settling: units fall when terrain under them is destroyed --------------------
# (Not in the spec; without it units hover over craters. No fall damage in M2.)
func _on_aoe_resolved(_center: Vector2i, _radius: int, _affected: Array) -> void:
	for u in all_units:
		_settle_unit(u)

func _settle_unit(u: Unit) -> void:
	var w := u.definition.width_voxels
	var h := u.definition.height_voxels
	var foot := u.vox_position.y + h - 1
	while foot < Const.MAP_HEIGHT - 1 and not _grounded(u.vox_position.x, foot, w):
		foot += 1
	var new_pos := Vector2i(u.vox_position.x, foot - h + 1)
	if new_pos != u.vox_position:
		u.set_vox_position(new_pos)

# --- Input (M2 spec §5 adapted to Gunbound model) ---------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_state != GameState.PLAYER_TURN:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_LEFT:
				try_move(active_unit, -1)
			KEY_RIGHT:
				try_move(active_unit, 1)
			KEY_TAB:
				if not charging:
					_tab_cycle()
			KEY_1:
				if not charging:
					_select_shot(0)
			KEY_2:
				if not charging:
					_select_shot(1)
			KEY_3:
				if not charging:
					_select_shot(2)
			KEY_SPACE:
				if not charging and active_unit != null \
						and not active_unit.is_done and active_unit.hp > 0:
					charging = true
					charge_frac = 0.0
	elif event is InputEventKey and not event.pressed \
			and event.physical_keycode == KEY_SPACE and charging:
		_fire_active()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not charging:
		_try_click_select(get_global_mouse_position())

func _process(delta: float) -> void:
	if game_state == GameState.PLAYER_TURN and active_unit != null \
			and active_unit.hp > 0 and not active_unit.is_done:
		# Angle adjust (held = continuous).
		var adj := 0.0
		if Input.is_physical_key_pressed(KEY_UP):
			adj += 1.0
		if Input.is_physical_key_pressed(KEY_DOWN):
			adj -= 1.0
		if adj != 0.0:
			active_unit.aim_angle_deg = clampf(
				active_unit.aim_angle_deg + adj * Const.ANGLE_RATE_DEG * delta,
				Const.ANGLE_MIN_DEG, Const.ANGLE_MAX_DEG)
		# Charge: auto-fire at full (Gunbound overcharge).
		if charging:
			charge_frac = minf(charge_frac + delta / Const.CHARGE_TIME, 1.0)
			if charge_frac >= 1.0:
				_fire_active()
	_push_hud_state()
	_targeting.set_aim_state(active_unit, charging, charge_frac)

func _push_hud_state() -> void:
	_hud.set_actions(actions_left, Const.MAX_ACTIONS)
	_hud.set_undo_enabled(can_undo())
	match game_state:
		GameState.PLAYER_TURN:
			_hud.set_turn_text("YOUR TURN")
			var all_done := player_units.all(func(u): return u.hp <= 0 or u.is_done)
			_hud.set_end_turn_alert(all_done)
		GameState.ENEMY_TURN:
			_hud.set_turn_text("ENEMY TURN")
			_hud.set_end_turn_alert(false)
		_:
			pass   # terminal text set on transition
	if active_unit != null and active_unit.hp > 0:
		_hud.set_unit_info("%s — %d / %d" % [active_unit.display_name,
				active_unit.hp, active_unit.definition.max_hp])
		_hud.set_angle(active_unit.aim_angle_deg)
		_hud.set_shots(active_unit.available_shots(), active_unit.get_active_shot(), actions_left)
	else:
		_hud.set_unit_info("")
		_hud.set_angle_none()
		_hud.set_shots([], null, actions_left)
	_hud.set_power(charge_frac, charging)
