# Combat orchestration (M2 spec §4, §5, §8, §9.2): game state, turn loop, shared
# action bar, unit selection, movement, Gunbound firing, enemy turn, win/loss.
class_name CombatManager
extends Node2D

signal action_bar_changed(current: int, maximum: int)
signal unit_focused(unit: Unit)   # selection changed → CombatScene pans the camera
signal combat_finished(outcome: String)   # M12: "cleared" / "failed" — drives run write-back

enum GameState { PLACEMENT, PLAYER_TURN, ENEMY_TURN, STAGE_CLEAR, GAME_OVER }

const NO_MOVE := UnitMovement.NO_MOVE

var game_state : GameState = GameState.PLAYER_TURN
var actions_left : int = Const.MAX_ACTIONS
var _turn_max_actions : int = Const.MAX_ACTIONS   # AP at turn start (base + artifact bonus)
var round_index : int = 0

var player_units : Array = []
var enemy_units : Array = []
var all_units : Array = []
var active_unit : Unit = null
# Inspector-panel focus (M5 polish): whichever unit (ally OR enemy) was last clicked,
# shown in the bottom-right info panel. Distinct from active_unit, which is only ever
# the player's controllable unit (move/fire/Tab cycle).
var inspected_unit : Unit = null

var charging : bool = false
var charge_frac : float = 0.0
var _last_firing_unit : Unit = null   # M9: most recent unit to fire, for on_unit_killed

# --- Cards (M5, deck added M11, sourced from RunState M12) ---------------------
# A real deck: shuffled draw pile → 5-card hand drawn fresh each turn → discard pile.
# When the draw pile empties mid-draw, the discard is reshuffled into a new draw pile.
# The canonical card list is the persistent RunState.deck, passed into setup() as `_deck_source`
# (a flat list of card resource paths) — combat seeds a shuffled copy and never edits the original.
const HAND_SIZE := 5
var _deck_source : Array = []               # card resource paths from RunState.deck (M12)
var _deck : Array[CardDefinition] = []      # draw pile (top = last element)
var _hand : Array[CardDefinition] = []
var _discard : Array[CardDefinition] = []
var _pending_card : CardDefinition = null   # non-null while choosing a target
# The hand SLOT being targeted (not the card object): duplicate cards in hand are the same cached
# CardDefinition instance, so highlighting must key off the index, not the card.
var _pending_index : int = -1

# --- Stage (M13): the StageDescriptor this combat is running. Source of enemies, reinforcement
# schedule, deployable placements, wind profile, and the objective. Set in setup().
var _stage : StageDescriptor = null

# --- Reinforcements (M5, now from _stage.reinforcements M13). Landing collision is intentionally
# NOT checked (enemies don't move) — only the surface row is snapped.
var _reinforcements_spawned : Dictionary = {}   # round int -> true

var _checkpoint_positions : Dictionary = {}  # Unit -> Vector2i
var _checkpoint_actions_left : int = 0
# M10: per-unit snapshot of consumed-by-move effect stacks (Boosted) so undo refunds them.
# Unit -> { effect_id: { "def": StatusEffectDef, "stacks": int } }
var _checkpoint_move_tokens : Dictionary = {}
# A free (Boosted) move spends no AP, so undo can't infer "something changed" from the action
# count alone — this flag tracks any undoable move since the last checkpoint.
var _dirty_since_checkpoint : bool = false

# --- Artifacts (M9, sourced from RunState M12): passive squad-wide effects ---------
# Active artifact resource paths come from RunState.artifacts, passed into setup().
var _artifact_paths : Array = []
var artifacts : Array[ArtifactDef] = []
var _artifact_ctx : ArtifactContext = null

# --- Essences (M22): per-unit upgrade hooks. Loaded from each unit's run_state on setup. -----
var _essence_ctx : EssenceContext = null

# --- Wind (M8, profile from _stage M13): environmental force on projectiles + fire spread -----
var wind_strength : float = 0.0   # -1.0..1.0 (negative = left, positive = right)

# --- Deployables (M6, placements from _stage.deployables M13) ----------------------
var deployables : Array = []

var _terrain : TerrainManager
var _projectiles : ProjectileManager
var _unit_layer : Node2D
var _deployable_layer_back : Node2D
var _deployable_layer_front : Node2D
var _hud : HUD
var _targeting : TargetingUI

# Placement drop queue (drop-queue redesign): units start invisible/unpositioned; the player
# places them one at a time by hovering a column indicator and clicking.
var _placement_queue : Array[Unit] = []
var _placement_hover_col : int = -1   # column under the mouse, clamped to spawn zone

func setup(terrain: TerrainManager, projectiles: ProjectileManager,
		unit_layer: Node2D, hud: HUD, targeting: TargetingUI,
		deployable_layer_back: Node2D = null, deployable_layer_front: Node2D = null,
		squad: Array = [], deck_source: Array = [], artifact_paths: Array = [],
		stage: StageDescriptor = null) -> void:
	_terrain = terrain
	_projectiles = projectiles
	_unit_layer = unit_layer
	_stage = stage                    # M13: enemies / reinforcements / wind / deployables / objective
	_deployable_layer_back = deployable_layer_back
	_deployable_layer_front = deployable_layer_front
	_hud = hud
	_targeting = targeting
	_deck_source = deck_source        # RunState.deck (card paths); seeded into _deck below
	_artifact_paths = artifact_paths  # RunState.artifacts (paths); loaded in _init_artifacts
	_hud.end_turn_pressed.connect(end_player_turn)
	_hud.undo_pressed.connect(try_undo)
	_hud.shot_selected.connect(_select_shot)
	_hud.card_selected.connect(_select_card)
	# Auto-advance to the next unit only once a player shot has FULLY resolved (§ resolution
	# routine in ProjectileManager), so the camera lingers on the impact before panning.
	_projectiles._combat = self
	_projectiles.shot_resolved.connect(_on_shot_resolved)
	# Gameplay events route through EventBus (M3): the resolver emits aoe_resolved there.
	EventBus.aoe_resolved.connect(_on_aoe_resolved)
	# Deployables (M6): mine proximity triggers off any unit move; deaths route back here.
	EventBus.unit_moved.connect(_check_mine_triggers)
	EventBus.deployable_died.connect(_on_deployable_died)
	EventBus.mine_detonated.connect(_on_mine_detonated)
	_place_player_squad(squad)
	_spawn_enemies()
	all_units = player_units + enemy_units
	if Features.deployables_enabled:
		_spawn_deployables()
	_init_artifacts()
	_build_deck()
	_hud.start_battle_pressed.connect(_confirm_placement)
	_start_placement()   # M15: position the squad before the turn loop begins

func get_units() -> Array:
	return all_units

func get_deployables() -> Array:
	return deployables

# --- Artifacts (M9): load from loadout, build context, fire combat-start hook ----
func _init_artifacts() -> void:
	_artifact_ctx = ArtifactContext.new()
	_artifact_ctx.terrain = _terrain
	_artifact_ctx.units = all_units
	_artifact_ctx.combat = self
	for path in _artifact_paths:
		var a : ArtifactDef = load(path)
		if a != null:
			artifacts.append(a)
	ArtifactSystem.call_combat_start(artifacts, _artifact_ctx)
	_hud.set_artifacts(artifacts)
	_init_essences()

func _init_essences() -> void:
	_essence_ctx = EssenceContext.new()
	_essence_ctx.terrain  = _terrain
	_essence_ctx.all_units = all_units
	_essence_ctx.combat   = self
	for unit in player_units:
		if unit.run_state == null:
			continue
		for path in unit.run_state.equipped_essences:
			var e := load(path) as EssenceDef
			if e != null:
				unit.essences.append(e)
	for unit in player_units:
		_essence_ctx.unit = unit
		EssenceSystem.call_combat_start(unit.essences, _essence_ctx)

# --- Spawning (M2 spec §9.3, surface-snap + no-overlap per plan §1.5) -----------
# Place the run squad (M12): pre-built Units from CombatBridge.build_squad() — definition +
# run_state already set, just need positioning, tree insertion, and death wiring. Initial columns
# are spread across the stage's spawn zone (M15); the player then repositions during placement.
func _place_player_squad(squad: Array) -> void:
	for u in squad:
		u.is_player = true
		u.aim_angle_deg = 45.0
		u.visible = false   # hidden until the player drops the unit in placement
		_unit_layer.add_child(u)   # triggers Unit._ready() → hp from run_state.current_hp
		u.unit_died.connect(_on_unit_died)
		player_units.append(u)
		_placement_queue.append(u)

# Spawn-zone bounds from the stage descriptor (M15); defaults to the left half if no stage.
func _spawn_min_col() -> int:
	return _stage.spawn_min_col if _stage != null else 0

func _spawn_max_col() -> int:
	return _stage.spawn_max_col if _stage != null else Const.MAP_WIDTH / 2 - 1

# --- Placement (M15): position the squad in the spawn zone before the turn loop ----
func _start_placement() -> void:
	game_state = GameState.PLACEMENT
	_set_selection(null)   # no active unit in drop-queue placement
	_log_phase("PLACEMENT")

# Only valid when the queue is empty (all units placed). Enter/Start Battle call this.
func _confirm_placement() -> void:
	if game_state != GameState.PLACEMENT or not _placement_queue.is_empty():
		return
	_begin_round()

# Drop `unit` at `col`: clamp into spawn zone, snap to surface, validate, make visible.
# Returns true on success. The caller is responsible for removing the unit from the queue.
func _placement_drop(unit: Unit, col: int) -> bool:
	if unit == null:
		return false
	var def := unit.definition
	var lo := _spawn_min_col()
	var hi := maxi(lo, _spawn_max_col() - def.width_voxels + 1)
	col = clampi(col, lo, hi)
	var surface := _terrain.get_surface_row(col)
	if surface == -1:
		return false
	var top_left := Vector2i(col, surface - def.height_voxels)
	if top_left.y < 0:
		return false
	if not UnitMovement.bbox_terrain_clear(_terrain, top_left, def.width_voxels, def.height_voxels):
		return false
	# Only check overlap against already-placed units (invisible queue units are at vox(0,0)).
	var placed := all_units.filter(func(u): return u.visible)
	if UnitMovement.overlaps_any_unit(placed, top_left, def, null):
		return false
	unit.set_vox_position(top_left)
	unit.visible = true
	return true

# Smoke / auto-confirm helper: place every queued unit at the first valid column and confirm.
func _drain_placement_queue() -> void:
	for u in _placement_queue.duplicate():
		for col in range(_spawn_min_col(), _spawn_max_col() + 1):
			if _placement_drop(u, col):
				_placement_queue.erase(u)
				break
	_confirm_placement()

# Placement-phase input: mouse move → update drop indicator column; left-click → drop the
# queue-front unit; Tab → cycle the queue; Enter → confirm when queue is empty.
func _placement_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var col := Const.world_to_voxel(get_global_mouse_position()).x
		_placement_hover_col = clampi(col, _spawn_min_col(), _spawn_max_col())
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB:
				if _placement_queue.size() > 1:
					_placement_queue.append(_placement_queue.pop_front())
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_placement()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _placement_queue.is_empty():
			return
		if _placement_drop(_placement_queue[0], _placement_hover_col):
			_placement_queue.pop_front()

# Initial enemy force from the stage descriptor (M13). Enemies are NOT run state.
func _spawn_enemies() -> void:
	if _stage == null:
		return
	for e in _stage.initial_enemies:
		var def : UnitDefinition = load(e["unit"])
		enemy_units.append(_spawn(def, e["name"], e["col"], false))

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
		if not UnitMovement.bbox_terrain_clear(_terrain, top_left,
				def.width_voxels, def.height_voxels):
			continue
		if UnitMovement.overlaps_any_unit(all_units, top_left, def, null):
			continue
		return top_left
	push_error("No valid spawn near col %d" % preferred_col)
	return Vector2i(preferred_col, 0)

# --- Deployables (M6, placements from _stage M13): mines + shield generators ------
func _spawn_deployables() -> void:
	if _stage == null:
		return
	for entry in _stage.deployables:
		var d : Deployable
		var layer : Node2D
		match entry["type"]:
			"mine":
				d = Mine.new()
				d.explosion_pattern = load("res://data/shots/aoe/diamond_mine.tres")
				layer = _deployable_layer_back
			"shield_generator":
				d = ShieldGenerator.new()
				layer = _deployable_layer_front
			_:
				push_error("Unknown deployable type: %s" % entry["type"])
				continue
		var col : int = entry["col"]
		var surface := _terrain.get_surface_row(col)
		var top_left := Vector2i(col, surface - d.height_voxels) if surface != -1 else Vector2i(col, 0)
		d.set_vox_position(top_left)
		layer.add_child(d)
		deployables.append(d)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _pulse_shield_generators() -> void:
	for d in deployables:
		if d is ShieldGenerator and d.hp > 0:
			for u in player_units:
				if u.hp > 0 and _chebyshev(d.vox_position, u.vox_position) <= d.aura_radius:
					u.add_shield(d.shield_amount)
					EventBus.unit_shield_changed.emit(u, u.shield)

func _check_mine_triggers(unit: Unit, _from: Vector2i, to: Vector2i) -> void:
	if not Features.deployables_enabled:
		return
	if not unit.is_player or unit.hp <= 0:
		return
	for d in deployables:
		if d is Mine and d.hp > 0 and _chebyshev(d.vox_position, to) <= d.trigger_radius:
			d.take_damage(d.hp)

func _on_mine_detonated(mine: Deployable) -> void:
	AoEResolver.resolve(_terrain, all_units, mine.vox_position,
			mine.explosion_pattern, mine.strength, false, deployables,
			mine.dig, mine.dig_pattern)

func _on_deployable_died(d: Deployable) -> void:
	deployables.erase(d)
	d.queue_free()

# --- Reinforcements (M5, schedule from _stage.reinforcements M13) ------------------
func _check_reinforcements() -> void:
	if _stage == null:
		return
	for wave in _stage.reinforcements:
		if wave["round"] == round_index and not _reinforcements_spawned.has(round_index):
			_reinforcements_spawned[round_index] = true
			_spawn_reinforcement(wave)

# Spawns directly at the scheduled column, snapped to the surface row, with NO
# unit-collision avoidance (enemies don't move, so the landing space is assumed
# clear — unlike _spawn()/_find_valid_spawn(), deliberately).
func _spawn_reinforcement(wave: Dictionary) -> void:
	var def : UnitDefinition = load(wave["unit"])
	var u := Unit.new()
	u.definition = def
	u.is_player = false
	u.display_name = wave["name"]
	u.aim_angle_deg = 135.0
	var col : int = wave["col"]
	var surface := _terrain.get_surface_row(col)
	var top_left := Vector2i(col, surface - def.height_voxels) if surface != -1 else Vector2i(col, 0)
	u.set_vox_position(top_left)
	_unit_layer.add_child(u)
	u.unit_died.connect(_on_unit_died)
	enemy_units.append(u)
	all_units.append(u)

# List of not-yet-spawned future waves, for the HUD/overlay countdown indicator.
func _reinforcement_warnings() -> Array:
	var out := []
	if _stage == null:
		return out
	for wave in _stage.reinforcements:
		if not _reinforcements_spawned.has(wave["round"]) and wave["round"] > round_index:
			out.append({ "col": wave["col"], "turns_left": wave["round"] - round_index })
	return out

# --- Wind (M8): update strength each round, drive fire spread when strong enough ------
func _update_wind_for_round(round_n: int) -> void:
	if not Features.wind_enabled or _stage == null or not _stage.wind_enabled:
		return
	if round_n < _stage.wind_start_round:
		return
	var elapsed := round_n - _stage.wind_start_round
	var range_frac := minf((elapsed + 1) * _stage.wind_ramp_per_round, _stage.wind_max_strength)
	wind_strength = randf_range(-range_frac, range_frac)
	_projectiles.current_wind_force = wind_strength * Const.MAX_WIND_FORCE
	EventBus.wind_changed.emit(wind_strength)

func _wind_spread_fire() -> void:
	if not Features.wind_enabled or not Features.tile_statuses_enabled:
		return
	if abs(wind_strength) < Const.WIND_SPREAD_THRESHOLD:
		return
	var wind_dir : int = 1 if wind_strength > 0.0 else -1   # signi() truncates float→int first
	var burning_def : TileStatusDef = load("res://data/tile_statuses/burning.tres")
	# Snapshot burning tiles first — avoid spreading to tiles ignited during this same pass.
	var burning : Array[Vector2i] = []
	for col in range(Const.MAP_WIDTH):
		for row in range(Const.MAP_HEIGHT):
			var tile := _terrain.get_tile(col, row)
			if tile != null and tile.tile_statuses.has("burning"):
				burning.append(Vector2i(col, row))
	for pos in burning:
		var target_col := pos.x + wind_dir
		if target_col < 0 or target_col >= Const.MAP_WIDTH:
			continue
		var target_surface := _terrain.get_surface_row(target_col)
		if target_surface == -1:
			continue
		# Vehicle movement rule: blocked if the adjacent column's surface is more than
		# 1 voxel higher than the burning tile (wall of 2+ voxels stops spread).
		if target_surface < pos.y - 1:
			continue
		var ntile := _terrain.get_tile(target_col, target_surface)
		if ntile == null or not ntile.has_flag_tag("FLAMMABLE"):
			continue
		TileStatusSystem.apply(_terrain, Vector2i(target_col, target_surface), burning_def)

# --- Turn loop (M2 §4.1 + M3 §6 resolution order) --------------------------------
# Round start → tile statuses tick → player turn (unit statuses tick, shock AP cut) →
# player actions → enemy turn (enemy statuses tick → enemy fire) → next round.
func _log_phase(label: String) -> void:
	print("\n=== [PHASE] %s ===" % label)

func _begin_round() -> void:
	if _is_terminal():
		return
	round_index += 1
	_log_phase("ROUND %d START" % round_index)
	EventBus.round_started.emit(round_index)
	_check_reinforcements()
	_update_wind_for_round(round_index)
	ArtifactSystem.call_round_start(artifacts, _artifact_ctx)
	if _essence_ctx != null:
		for unit in player_units:
			_essence_ctx.unit = unit
			EssenceSystem.call_round_start(unit.essences, _essence_ctx)
	# 1. Tile statuses tick (burning damages/spreads, electrified chains/decays).
	TileStatusSystem.tick_all(_terrain, all_units)
	_wind_spread_fire()
	if _is_terminal():
		return
	_start_player_turn()

func _start_player_turn() -> void:
	if _is_terminal():
		return
	game_state = GameState.PLAYER_TURN
	# Survive-N objectives win at the start of the round they reach (M13).
	_check_objective()
	if _is_terminal():
		return
	# 2. Player unit statuses tick (burn damage); accumulate Shock AP reduction.
	var ap_reduction := 0
	for u in player_units:
		ap_reduction += UnitStatusSystem.tick_all(u)
	if _is_terminal():
		return
	# 3. Base AP = MAX_ACTIONS minus Shock reduction; bonus AP from artifacts added on top.
	actions_left = maxi(0, Const.MAX_ACTIONS - ap_reduction)
	# Bonus is read before resetting moved_this_turn so last round's idle state counts.
	actions_left += ArtifactSystem.sum_bonus_actions(artifacts, _artifact_ctx)
	_turn_max_actions = actions_left
	for u in player_units:
		u.moved_this_turn = false
	action_bar_changed.emit(actions_left, _turn_max_actions)
	for u in player_units:
		u.reset_for_turn()
	if Features.card_deck_enabled:
		_draw_hand()   # M11: fresh 5-card hand each turn (old hand discarded)
	_save_checkpoint()
	if Features.deployables_enabled:
		_pulse_shield_generators()
	_select_first_available()
	_log_phase("PLAYER TURN START")
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
	ArtifactSystem.call_player_turn_end(artifacts, _artifact_ctx)
	if _essence_ctx != null:
		for unit in player_units:
			_essence_ctx.unit = unit
			EssenceSystem.call_player_turn_end(unit.essences, _essence_ctx)
	_log_phase("PLAYER TURN END")
	EventBus.turn_ended.emit("player")
	game_state = GameState.ENEMY_TURN
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	_log_phase("ENEMY TURN START")
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
		_last_firing_unit = e
		EnemySystem.fire_enemy(e, player_units, _projectiles)
		# Wait for the shot to fully resolve (flight + resolution routine + settle beat).
		while _projectiles.is_busy():
			await get_tree().create_timer(0.1).timeout
	_log_phase("ENEMY TURN END")
	EventBus.turn_ended.emit("enemy")
	if _is_terminal():
		return
	_begin_round()

func _is_terminal() -> bool:
	return game_state == GameState.STAGE_CLEAR or game_state == GameState.GAME_OVER

# All scheduled reinforcement waves have been spawned (not just the ones due so far) —
# stage clear must wait for this, otherwise killing the current enemies before a later
# wave lands would end the stage with reinforcements never shown.
func _all_waves_spawned() -> bool:
	if _stage == null:
		return true
	for wave in _stage.reinforcements:
		if not _reinforcements_spawned.has(wave["round"]):
			return false
	return true

# --- Win / loss (M2 spec §8, generalized to the objective evaluator M13) -----------
func _on_unit_died(unit: Unit) -> void:
	# Kill credit (M12): a player unit that landed the killing blow on an enemy scores a kill.
	if not unit.is_player and _last_firing_unit != null and is_instance_valid(_last_firing_unit) \
			and _last_firing_unit.is_player:
		_last_firing_unit.kills += 1
	if _artifact_ctx != null:
		ArtifactSystem.call_unit_died(artifacts, _artifact_ctx, unit)
		if _last_firing_unit != null and is_instance_valid(_last_firing_unit):
			ArtifactSystem.call_unit_killed(artifacts, _artifact_ctx, unit, _last_firing_unit)
	if _essence_ctx != null:
		for pu in player_units:
			_essence_ctx.unit = pu
			EssenceSystem.call_unit_died(pu.essences, _essence_ctx, unit)
	_check_objective()

# Run the stage's objective against current combat state; transition + announce on a result.
# Called on every death (defeat-all win / squad-wipe loss) and at round start (survive-N win).
func _check_objective() -> void:
	if _is_terminal() or _stage == null:
		return
	var enemies_alive := enemy_units.any(func(u): return u.hp > 0)
	var players_alive := player_units.any(func(u): return u.hp > 0)
	var result := ObjectiveEvaluator.evaluate(_stage.objective, enemies_alive, players_alive,
			round_index, _all_waves_spawned())
	if result == ObjectiveEvaluator.Result.WON:
		print("[STAGE CLEAR] Objective met.")
		game_state = GameState.STAGE_CLEAR
		_hud.set_turn_text("STAGE CLEAR")
		_set_selection(null)
		combat_finished.emit("cleared")
	elif result == ObjectiveEvaluator.Result.LOST:
		print("[GAME OVER] All player units destroyed.")
		game_state = GameState.GAME_OVER
		_hud.set_turn_text("GAME OVER")
		_set_selection(null)
		combat_finished.emit("failed")

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
		_inspect(u, false)   # the controllable unit is also shown in the inspector panel

# Inspector-panel focus (M5 polish): tracks whichever unit — ally or enemy — the info
# panel currently shows. `pan_camera` is false when _set_selection already emitted
# unit_focused for the same unit (avoids a redundant signal).
func _inspect(u: Unit, pan_camera: bool = true) -> void:
	if inspected_unit != null and is_instance_valid(inspected_unit) and inspected_unit != u:
		inspected_unit.set_inspected(false)
	inspected_unit = u
	if u != null:
		u.set_inspected(true)
		if pan_camera:
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
	# Enemies aren't controllable, but clicking one focuses + inspects it (M5 polish) —
	# Tab still only cycles allies.
	for u in enemy_units:
		if u.bounds_rect_world().has_point(world_pos):
			_inspect(u)
			return

# --- Movement (M2 spec §5.2 + unit-collision rule from plan §1.5) -----------------
func try_move(unit: Unit, direction: int) -> void:
	if game_state != GameState.PLAYER_TURN or charging:
		return
	if unit == null or unit.is_done or unit.hp <= 0:
		return
	# Boosted (M10): a move token makes this move free, bypassing the AP requirement.
	var token := _unit_move_token(unit)
	if token == null and actions_left < 1:
		return
	if unit.actions_spent_moving >= unit.definition.move_range:
		return
	# Movement geometry lives in UnitMovement (shared with effect-driven shoves, M4).
	var dest := UnitMovement.resolve_move(unit, direction, _terrain, all_units)
	if dest == NO_MOVE:
		return
	unit.set_vox_position(dest)
	unit.moved_this_turn = true
	unit.actions_spent_moving += 1
	if token != null:
		_spend_move_token(unit, token)   # Boosted absorbs the cost instead of the AP pool
	else:
		actions_left -= 1
	_dirty_since_checkpoint = true
	action_bar_changed.emit(actions_left, _turn_max_actions)

# Boosted (M10): the first consumed_by_move effect on `unit` with stacks left, or null.
func _unit_move_token(unit: Unit) -> StatusInstance:
	if not Features.unit_statuses_enabled:
		return null
	for id in unit.active_statuses:
		var inst : StatusInstance = unit.active_statuses[id]
		if inst.definition.consumed_by_move and inst.stacks > 0:
			return inst
	return null

func _spend_move_token(unit: Unit, token: StatusInstance) -> void:
	token.stacks -= 1
	if token.stacks <= 0:
		unit.active_statuses.erase(token.definition.id)
		EventBus.status_removed.emit(unit, token.definition.id)
	unit.queue_redraw()

# --- Checkpoint save: called at turn start and after each firing event ------------
func _save_checkpoint() -> void:
	_checkpoint_positions.clear()
	_checkpoint_move_tokens.clear()
	_checkpoint_actions_left = actions_left
	_dirty_since_checkpoint = false
	for u in player_units:
		if u.hp > 0 and not u.is_done:
			_checkpoint_positions[u] = u.vox_position
			var tokens := {}
			for id in u.active_statuses:
				var inst : StatusInstance = u.active_statuses[id]
				if inst.definition.consumed_by_move:
					tokens[id] = { "def": inst.definition, "stacks": inst.stacks }
			_checkpoint_move_tokens[u] = tokens

# --- Undo: restores ALL unfired player units to the last checkpoint ---------------
func can_undo() -> bool:
	return game_state == GameState.PLAYER_TURN and not charging \
		and _dirty_since_checkpoint

func try_undo() -> void:
	if not can_undo():
		return
	for u in _checkpoint_positions:
		if is_instance_valid(u) and u.hp > 0 and not u.is_done:
			u.set_vox_position(_checkpoint_positions[u])
			u.actions_spent_moving = 0
			_restore_move_tokens(u)
			_settle_unit(u)
	actions_left = _checkpoint_actions_left
	_dirty_since_checkpoint = false
	action_bar_changed.emit(actions_left, _turn_max_actions)

# Restore a unit's consumed-by-move effect stacks (Boosted) to their checkpoint values,
# re-creating an instance that was fully spent during the undone moves.
func _restore_move_tokens(unit: Unit) -> void:
	var snap : Dictionary = _checkpoint_move_tokens.get(unit, {})
	for id in snap:
		var entry : Dictionary = snap[id]
		if unit.active_statuses.has(id):
			unit.active_statuses[id].stacks = entry["stacks"]
		else:
			unit.active_statuses[id] = StatusInstance.new(entry["def"], entry["stacks"])
	unit.queue_redraw()

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
	u.last_power_frac = charge_frac   # Gunbound power memory (M4): marker on next charge
	charge_frac = 0.0
	if shot.action_cost > 0:
		actions_left -= shot.action_cost
		action_bar_changed.emit(actions_left, _turn_max_actions)
	_last_firing_unit = u
	_projectiles.fire(u.barrel_origin_world(), u.aim_dir(), speed, shot, false, u)
	EventBus.unit_fired.emit(u, shot)
	if _essence_ctx != null:
		_essence_ctx.unit      = u
		_essence_ctx.last_shot  = shot
		_essence_ctx.last_speed = speed
		EssenceSystem.call_unit_fired(u.essences, _essence_ctx)
	u.mark_done()
	_save_checkpoint()
	# NOTE: the next unit is NOT focused here. The camera follows the projectile, then lingers
	# on the impact while the shot resolves; _on_shot_resolved advances once that's done.

# M22: fired by EssenceDoubleShot — fires the unit again with the same angle/speed after a delay.
# Essence hooks are NOT called on the refire to prevent infinite recursion.
func schedule_refire(unit: Unit, shot: ShotDefinition, speed: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(unit) or unit.hp <= 0:
		return
	_projectiles.fire(unit.barrel_origin_world(), unit.aim_dir(), speed, shot, false, unit)
	EventBus.unit_fired.emit(unit, shot)

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

# --- Deck (M11): build, draw a fresh hand each turn, reshuffle discard when the draw pile runs out.
func _build_deck() -> void:
	_deck.clear()
	_hand.clear()
	_discard.clear()
	for path in _deck_source:
		_deck.append(load(path))
	_deck.shuffle()

# Discard the unplayed hand, then draw HAND_SIZE fresh. If the draw pile empties mid-draw,
# the discard is reshuffled into a new draw pile and drawing continues (user-specified rule).
func _draw_hand() -> void:
	_discard.append_array(_hand)
	_hand.clear()
	for _i in range(HAND_SIZE):
		if _deck.is_empty():
			_reshuffle_discard()
			if _deck.is_empty():
				break   # no cards anywhere (hand smaller than HAND_SIZE)
		_hand.append(_deck.pop_back())

func _reshuffle_discard() -> void:
	_deck = _discard.duplicate()
	_discard.clear()
	_deck.shuffle()

# --- Cards (M5, reworked M11): action-costed effects played from the hand. Distinct from
# firing — playing a card does not require an active unit and does not end any unit's turn.
func _select_card(idx: int) -> void:
	if not Features.card_deck_enabled:
		return
	if game_state != GameState.PLAYER_TURN or charging:
		return
	if idx < 0 or idx >= _hand.size():
		return
	var card : CardDefinition = _hand[idx]
	if actions_left < card.action_cost:
		return
	charging = false   # selecting a card suspends any in-progress shot charge
	# No-target cards (Halve Wind) resolve immediately; targeted cards await a click.
	if card.target_type == CardDefinition.TargetType.NONE:
		_apply_card(card, null, Vector2i.ZERO)
	else:
		_pending_card = card
		_pending_index = idx

func _cancel_pending_card() -> void:
	_pending_card = null
	_pending_index = -1

func _try_click_target_card(world_pos: Vector2) -> void:
	if _pending_card == null:
		return
	match _pending_card.target_type:
		CardDefinition.TargetType.ALLY, CardDefinition.TargetType.ENEMY:
			var pool := player_units if _pending_card.target_type == CardDefinition.TargetType.ALLY \
					else enemy_units
			for u in pool:
				if u.hp > 0 and u.bounds_rect_world().has_point(world_pos):
					_apply_card(_pending_card, u, Vector2i.ZERO)
					return
		CardDefinition.TargetType.TILE:
			var col := Const.world_to_voxel(world_pos).x
			if col >= 0 and col < Const.MAP_WIDTH and _terrain.get_surface_row(col) != -1:
				_apply_card(_pending_card, null, Vector2i(col, 0))

# Dispatch a card's effect. `target` is the unit for ALLY/ENEMY cards; `vox` carries the chosen
# column for TILE cards; both are ignored by NONE cards. Played cards go to the discard pile.
func _apply_card(card: CardDefinition, target: Unit, vox: Vector2i) -> void:
	var cost := ArtifactSystem.apply_card_cost(artifacts, _artifact_ctx, card, card.action_cost)
	actions_left -= cost
	action_bar_changed.emit(actions_left, _turn_max_actions)
	match card.effect_type:
		CardDefinition.EffectType.SHIELD_BUFF:
			target.add_shield(card.magnitude)
			EventBus.unit_shield_changed.emit(target, target.shield)
		CardDefinition.EffectType.ARMOR_BUFF:
			target.add_armor(card.magnitude)
			EventBus.unit_armor_changed.emit(target, target.armor)
		CardDefinition.EffectType.DIRECT_DAMAGE:
			target.take_damage(card.magnitude)   # routes through shield, like any other hit
		CardDefinition.EffectType.ADD_BOOSTED:
			UnitStatusSystem.apply(target, load("res://data/statuses/boosted.tres"), card.magnitude)
		CardDefinition.EffectType.DEPLOY_MINE:
			_deploy_mine_at(vox.x)
		CardDefinition.EffectType.HALVE_WIND:
			_halve_wind()
	_hand.erase(card)
	_discard.append(card)
	_pending_card = null
	_pending_index = -1
	_save_checkpoint()   # AP spend is undoable (deck state is not — card play re-checkpoints)

# Deploy a player mine on the surface of `col` (M11 mine card). Mirrors the mine branch of
# _spawn_deployables().
func _deploy_mine_at(col: int) -> void:
	var m := Mine.new()
	m.explosion_pattern = load("res://data/shots/aoe/diamond_mine.tres")
	var surface := _terrain.get_surface_row(col)
	var top_left := Vector2i(col, surface - m.height_voxels) if surface != -1 else Vector2i(col, 0)
	m.set_vox_position(top_left)
	_deployable_layer_back.add_child(m)
	deployables.append(m)

func _halve_wind() -> void:
	wind_strength *= 0.5
	_projectiles.current_wind_force = wind_strength * Const.MAX_WIND_FORCE
	EventBus.wind_changed.emit(wind_strength)

# --- Settling: units fall when terrain under them is destroyed --------------------
# (Not in the spec; without it units hover over craters. No fall damage in M2.)
func _on_aoe_resolved(_center: Vector2i, _radius: int, _affected: Array) -> void:
	for u in all_units:
		_settle_unit(u)
	for d in deployables:
		_settle_deployable(d)

func _settle_unit(u: Unit) -> void:
	var new_pos := UnitMovement.settle(u, _terrain)
	if new_pos != u.vox_position:
		u.set_vox_position(new_pos)

func _settle_deployable(d: Deployable) -> void:
	var new_pos := UnitMovement.settle_at(d.vox_position, d.width_voxels, d.height_voxels, _terrain)
	if new_pos != d.vox_position:
		d.set_vox_position(new_pos)

# --- Input (M2 spec §5 adapted to Gunbound model) ---------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_state == GameState.PLACEMENT:
		_placement_input(event)
		return
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
			KEY_Q:
				if not charging and Features.card_deck_enabled:
					_select_card(0)
			KEY_E:
				if not charging and Features.card_deck_enabled:
					_select_card(1)
			KEY_ESCAPE:
				_cancel_pending_card()
	elif event is InputEventKey and not event.pressed \
			and event.physical_keycode == KEY_SPACE and charging:
		_fire_active()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not charging:
		if _pending_card != null:
			_try_click_target_card(get_global_mouse_position())
		else:
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
	_targeting.set_card_state(_pending_card)
	_targeting.set_reinforcement_state(_reinforcement_warnings())
	_targeting.set_placement_state(game_state == GameState.PLACEMENT,
			_spawn_min_col(), _spawn_max_col())
	if game_state == GameState.PLACEMENT:
		var dname := _placement_queue[0].definition.display_name \
				if not _placement_queue.is_empty() else ""
		_targeting.set_drop_indicator(
				_placement_hover_col if not _placement_queue.is_empty() else -1, dname)
		_hud.set_placement_unit(dname, _placement_queue.size())

func _push_hud_state() -> void:
	_hud.set_actions(actions_left, _turn_max_actions)
	_hud.set_undo_enabled(can_undo())
	_hud.set_placement_mode(game_state == GameState.PLACEMENT)   # M15
	match game_state:
		GameState.PLACEMENT:
			_hud.set_turn_text("DEPLOY SQUAD")
		GameState.PLAYER_TURN:
			_hud.set_turn_text("YOUR TURN")
			var all_done := player_units.all(func(u): return u.hp <= 0 or u.is_done)
			_hud.set_end_turn_alert(all_done)
		GameState.ENEMY_TURN:
			_hud.set_turn_text("ENEMY TURN")
			_hud.set_end_turn_alert(false)
		_:
			pass   # terminal text set on transition
	var last_power := -1.0   # no marker when nothing is selected
	if active_unit != null and active_unit.hp > 0:
		_hud.set_unit_info("%s — %d / %d" % [active_unit.display_name,
				active_unit.hp, active_unit.definition.max_hp])
		_hud.set_angle(active_unit.aim_angle_deg)
		_hud.set_shots(active_unit.available_shots(), active_unit.get_active_shot(), actions_left)
		last_power = active_unit.last_power_frac
	else:
		_hud.set_unit_info("")
		_hud.set_angle_none()
		_hud.set_shots([], null, actions_left)
	_hud.set_power(charge_frac, charging, last_power)
	var cards := _hand if Features.card_deck_enabled else []
	_hud.set_cards(cards, _pending_index, actions_left, _deck.size(), _discard.size())
	_hud.set_inspected_unit(inspected_unit)
