# Run-level scene-flow controller (M14+M16). The game's main scene. Persists for the
# whole run and swaps its single active child between MapScreen, RewardScreen, and a freshly-
# instanced combat_scene. The run state lives in the Run autoload; this controller reads it to
# decide flow and never touches combat internals. Re-instancing combat_scene per stage IS the
# per-stage reset (fresh Unit nodes — M12), so HP/kills/disabled carry only via RunState.
extends Node

const _COMBAT_SCENE := "res://world/combat_scene.tscn"

var _current : Node = null

# Reward-sequence state (M16):
var _reward_queue       : Array = []   # RewardScreen.Category values still to show
var _reward_post_combat : bool  = false
var _current_reward_cat : int   = -1

func _ready() -> void:
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		# Smoke: backfill squad + artifacts to match pre-M16 test expectations (4 units, all 8 artifacts).
		if Run.active == null:
			Run.start_default_run()
		Run.active.squad.append(RunUnitState.from_definition(
				"res://data/units/player_pull.tres",   "Magnet"))
		Run.active.squad.append(RunUnitState.from_definition(
				"res://data/units/player_spiral.tres", "Spiral"))
		Run.active.artifacts.append_array(Run.active.artifact_pool)
		Run.active.artifact_pool.clear()
		_enter_combat(null)
		return
	if Run.active == null:
		Run.start_default_run()
	_start_reward_sequence(false)   # pre-first-combat rewards before showing the map

func _swap(node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = node
	add_child(node)

# --- Map -------------------------------------------------------------------------

func _show_map() -> void:
	var map_screen := MapScreen.new()
	map_screen.stage_selected.connect(_on_node_selected)
	map_screen.new_run_requested.connect(_restart_run)
	_swap(map_screen)
	map_screen.setup(Run.active.map)

func _show_map_end(text: String) -> void:
	var map_screen := MapScreen.new()
	map_screen.new_run_requested.connect(_restart_run)
	_swap(map_screen)
	map_screen.setup(Run.active.map)
	map_screen.show_end(text)

# --- Node selection --------------------------------------------------------------

func _on_node_selected(node: MapNode) -> void:
	if node.type == MapNode.Type.SHOP and Features.shop_enabled:
		_enter_shop(node)
	elif node.type == MapNode.Type.EVENT and Features.events_enabled:
		_enter_event(node)
	elif node.type == MapNode.Type.REPAIR and Features.repair_enabled:
		_enter_repair(node)
	elif node.type == MapNode.Type.UPGRADE and Features.upgrade_enabled:
		_enter_upgrade(node)
	else:
		_enter_combat(node)

# --- Shop ------------------------------------------------------------------------

func _enter_shop(_node: MapNode) -> void:
	var ss := ShopScreen.new()
	ss.shop_closed.connect(_on_shop_closed)
	_swap(ss)
	ss.setup()

func _on_shop_closed() -> void:
	_on_node_screen_completed()

# --- Event -----------------------------------------------------------------------

func _enter_event(node: MapNode) -> void:
	var ev := node.event()
	if ev == null:
		_enter_combat(node)   # fallback: no event resource on this node
		return
	var es := EventScreen.new()
	es.event_completed.connect(_on_event_completed)
	_swap(es)
	es.setup(ev)

func _on_event_completed() -> void:
	_on_node_screen_completed()

# --- Repair ----------------------------------------------------------------------

func _enter_repair(_node: MapNode) -> void:
	var rs := RepairScreen.new()
	rs.repair_completed.connect(_on_node_screen_completed)
	_swap(rs)
	rs.setup()

# --- Upgrade ---------------------------------------------------------------------

func _enter_upgrade(_node: MapNode) -> void:
	var us := UpgradeScreen.new()
	us.upgrade_completed.connect(_on_node_screen_completed)
	_swap(us)
	us.setup()

func _on_node_screen_completed() -> void:
	Run.active.map.mark_visited()
	if Run.active.map.is_complete():
		_show_map_end("RUN COMPLETE")
	else:
		_show_map()

# --- Combat ----------------------------------------------------------------------

# `node` null = smoke / standalone (combat_scene picks its own default stage_01).
func _enter_combat(node: MapNode) -> void:
	var cs : Node = (load(_COMBAT_SCENE) as PackedScene).instantiate()
	if node != null:
		cs.stage = node.stage()
		cs.terrain_profile_path = node.terrain_profile_path
		cs.active_stage_seed    = node.stage_seed
	cs.combat_exited.connect(_on_combat_exited)
	_swap(cs)

func _on_combat_exited(outcome: String) -> void:
	var any_alive := Run.active.squad.any(func(u): return not u.is_disabled)
	if outcome == "cleared" and any_alive:
		Run.active.resources["shards"] += 20
		_start_reward_sequence(true)   # rewards before advancing the map
	else:
		_show_map_end("RUN OVER")

# --- Rewards (M16) -----------------------------------------------------------

func _start_reward_sequence(post_combat: bool) -> void:
	_reward_post_combat = post_combat
	_reward_queue = [
		RewardScreen.Category.UNIT,
		RewardScreen.Category.ARTIFACT,
		RewardScreen.Category.CARD,
	]
	_show_next_reward()

func _show_next_reward() -> void:
	while not _reward_queue.is_empty():
		var cat : int = _reward_queue.pop_front()
		var opts := _pick_reward_options(cat)
		if opts.is_empty():
			continue   # skip category (e.g. artifact pool exhausted)
		_current_reward_cat = cat
		var rs := RewardScreen.new()
		rs.setup(cat, opts)
		rs.reward_chosen.connect(_on_reward_chosen)
		rs.reward_skipped.connect(_on_reward_skipped)
		_swap(rs)
		return   # wait for player selection
	_on_all_rewards_done()

func _on_reward_skipped() -> void:
	_show_next_reward()

func _on_reward_chosen(path: String) -> void:
	match _current_reward_cat:
		RewardScreen.Category.UNIT:
			var def : UnitDefinition = load(path)
			Run.active.squad.append(RunUnitState.from_definition(path, def.display_name))
		RewardScreen.Category.ARTIFACT:
			Run.active.artifacts.append(path)
			Run.active.artifact_pool.erase(path)
		RewardScreen.Category.CARD:
			Run.active.deck.append(path)
	_show_next_reward()

func _on_all_rewards_done() -> void:
	if _reward_post_combat:
		var m : MapState = Run.active.map
		m.mark_visited()
		if m.is_complete():
			_show_map_end("RUN COMPLETE")
		else:
			_show_map()
	else:
		_show_map()   # pre-first-combat: pick first stage from the map

# Sample `count` entries from `pool`. `allow_repeat` true = with replacement (units/cards);
# false = without replacement (artifacts — no duplicates in the same offer or across runs).
func _used_capacity() -> int:
	return SquadOps.used_capacity(Run.active)

func _pick_reward_options(cat: int) -> Array[String]:
	match cat:
		RewardScreen.Category.UNIT:
			if _used_capacity() >= RunState.MAX_SQUAD_CAPACITY:
				return []
			return _sample(Run.active.unit_pool, 3, true)
		RewardScreen.Category.ARTIFACT:
			return Run.pick_artifacts_for_offer(3)
		RewardScreen.Category.CARD:
			return _sample(Run.active.card_pool, 3, true)
		_:
			return []

func _sample(pool: Array[String], count: int, allow_repeat: bool) -> Array[String]:
	if pool.is_empty():
		return []
	var src := pool.duplicate()
	var out : Array[String] = []
	var limit := count if allow_repeat else mini(count, src.size())
	for _i in range(limit):
		var idx := Run.run_rng.randi() % src.size()
		out.append(src[idx])
		if not allow_repeat:
			src.remove_at(idx)
	return out

# --- Restart ---------------------------------------------------------------------

func _restart_run() -> void:
	Run.start_default_run()
	_start_reward_sequence(false)
