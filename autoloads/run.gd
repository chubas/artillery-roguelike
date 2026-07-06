# Run autoload (run-state spec §3): the single source of truth for the active run. Mirrors the
# EventBus / Features autoload pattern. Combat reads from `active` on entry (via CombatBridge) and
# writes back on exit. Until squad-select / map exist (later milestones), start_default_run() seeds
# a run that reproduces the historical hardcoded content so the live game is unchanged.
extends Node

var active  : RunState             = null
var run_rng : RandomNumberGenerator = RandomNumberGenerator.new()

# Default starting content (M16: run starts small; rewards grow the squad/loadout).
const _DEFAULT_MAP : Array = [
	"res://data/stages/stage_01.tres",
	"res://data/stages/stage_02.tres",
	"res://data/stages/stage_03.tres",
]
const _EVENT_PATHS : Array = [
	"res://data/events/resources/event_triage.tres",
	"res://data/events/resources/event_blood_price.tres",
]
const _DEFAULT_DECK : Array = [   # [path, copies]
	["res://data/cards/direct_strike.tres", 3],
	["res://data/cards/shield_buff.tres",   3],
	["res://data/cards/armor_buff.tres",    3],
	["res://data/cards/mine_card.tres",     2],
	["res://data/cards/boosted_card.tres",      2],
	["res://data/cards/halve_wind.tres",        1],
	["res://data/cards/fire_prime.tres",        2],
	["res://data/cards/electric_prime.tres",    2],
]

func start_default_run() -> void:
	var rs := RunState.new()
	# 2 starting units; the other 2 enter via unit rewards.
	rs.squad = [
		RunUnitState.from_definition("res://data/units/player_cluster.tres", "Cluster"),
		RunUnitState.from_definition("res://data/units/player_bypass.tres",  "Bypass"),
	]
	rs.deck.clear()
	for entry in _DEFAULT_DECK:
		for _i in range(entry[1]):
			rs.deck.append(entry[0])
	# 1 starting artifact; the other 7 enter via artifact rewards (no repeats).
	rs.artifacts = ["res://data/artifacts/resources/squad_regen.tres"]
	rs.artifact_pool = [
		"res://data/artifacts/resources/lifesteal.tres",
		"res://data/artifacts/resources/enemy_debuff.tres",
		"res://data/artifacts/resources/free_first_card.tres",
		"res://data/artifacts/resources/idle_actions.tres",
		"res://data/artifacts/resources/death_explosion.tres",
		"res://data/artifacts/resources/long_flight.tres",
		"res://data/artifacts/resources/start_boosted.tres",
	]
	rs.unit_pool = [
		"res://data/units/player_cluster.tres",
		"res://data/units/player_bypass.tres",
		"res://data/units/player_pull.tres",
		"res://data/units/player_spiral.tres",
	]
	rs.card_pool = [
		"res://data/cards/direct_strike.tres",
		"res://data/cards/shield_buff.tres",
		"res://data/cards/armor_buff.tres",
		"res://data/cards/mine_card.tres",
		"res://data/cards/boosted_card.tres",
		"res://data/cards/halve_wind.tres",
		"res://data/cards/fire_prime.tres",
		"res://data/cards/electric_prime.tres",
	]
	rs.map = MapState.build_run_map(_DEFAULT_MAP, _EVENT_PATHS)
	var _run_seed : int = Features.run_seed if Features.run_seed != 0 else randi()
	rs.run_meta = { "seed": _run_seed, "act": 1, "stage_index": 0, "faction": Faction.ARMY }
	rs.currency = 25
	# M22: pre-equip one essence per starting unit for testing. Essences are not unit-specific
	# by design; this wiring will move to the reward/event system in a later milestone.
	rs.squad[0].equipped_essences = ["res://data/essences/resources/armor_primer.tres"]
	rs.squad[1].equipped_essences = ["res://data/essences/resources/double_shot.tres"]
	run_rng.seed = _run_seed
	_assign_terrain_variations(rs)
	active = rs

const _TERRAIN_PROFILES : Array[String] = [
	"res://data/terrain/profiles/open_field.tres",
	"res://data/terrain/profiles/ridge_assault.tres",
	"res://data/terrain/profiles/fortress_siege.tres",
	"res://data/terrain/profiles/pit_crossing.tres",
]

func _assign_terrain_variations(rs: RunState) -> void:
	# M44: hand-authored maps take priority — every combat node (incl. the first) draws a
	# random map from the library. Profiles/legacy remain only as a fallback when the
	# library is empty or the flag is off.
	var map_ids : Array = MapLibrary.map_ids() if Features.custom_maps_enabled else []
	for i in range(rs.map.nodes.size()):
		var node : MapNode = rs.map.nodes[i]
		if node.type != MapNode.Type.COMBAT:
			continue
		node.stage_seed = run_rng.randi()
		if not map_ids.is_empty():
			node.custom_map_id = map_ids[run_rng.randi() % map_ids.size()]
			node.terrain_profile_path = ""
		elif i == 0:
			node.terrain_profile_path = ""
		else:
			node.terrain_profile_path = _TERRAIN_PROFILES[run_rng.randi() % _TERRAIN_PROFILES.size()]

## Sample n artifacts for a reward or shop offer, respecting the seen-set cycle.
## Artifacts already offered (but not bought) won't appear again until all have been offered.
func pick_artifacts_for_offer(n: int) -> Array[String]:
	var available : Array[String] = []
	for a in active.artifact_pool:
		if not active.artifact_seen_set.has(a):
			available.append(a)
	if available.size() < n and not active.artifact_pool.is_empty():
		active.artifact_seen_set.clear()
		available = active.artifact_pool.duplicate()
	var out : Array[String] = []
	var src := available.duplicate()
	for _i in range(mini(n, src.size())):
		var idx := run_rng.randi() % src.size()
		out.append(src[idx])
		src.remove_at(idx)
	active.artifact_seen_set.append_array(out)
	return out
