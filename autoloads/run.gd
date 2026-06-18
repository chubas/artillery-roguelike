# Run autoload (run-state spec §3): the single source of truth for the active run. Mirrors the
# EventBus / Features autoload pattern. Combat reads from `active` on entry (via CombatBridge) and
# writes back on exit. Until squad-select / map exist (later milestones), start_default_run() seeds
# a run that reproduces the historical hardcoded content so the live game is unchanged.
extends Node

var active : RunState = null

# Default starting content (M16: run starts small; rewards grow the squad/loadout).
const _DEFAULT_MAP : Array = [
	"res://data/stages/stage_01.tres",
	"res://data/stages/stage_02.tres",
	"res://data/stages/stage_03.tres",
]
const _DEFAULT_DECK : Array = [   # [path, copies]
	["res://data/cards/direct_strike.tres", 3],
	["res://data/cards/shield_buff.tres",   3],
	["res://data/cards/armor_buff.tres",    3],
	["res://data/cards/mine_card.tres",     2],
	["res://data/cards/boosted_card.tres",  2],
	["res://data/cards/halve_wind.tres",    1],
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
	]
	rs.map = MapState.build_diamond(_DEFAULT_MAP)
	rs.run_meta = { "seed": randi(), "act": 1, "stage_index": 0, "faction": Faction.ARMY }
	active = rs
