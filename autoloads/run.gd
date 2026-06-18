# Run autoload (run-state spec §3): the single source of truth for the active run. Mirrors the
# EventBus / Features autoload pattern. Combat reads from `active` on entry (via CombatBridge) and
# writes back on exit. Until squad-select / map exist (later milestones), start_default_run() seeds
# a run that reproduces the historical hardcoded content so the live game is unchanged.
extends Node

var active : RunState = null

# Canonical default content (moved here out of CombatManager's old _DECK_LIST / _ARTIFACT_LOADOUT).
const _DEFAULT_SQUAD : Array = [
	["res://data/units/player_cluster.tres", "Cluster"],
	["res://data/units/player_bypass.tres",  "Drill"],
	["res://data/units/player_pull.tres",    "Magnet"],
	["res://data/units/player_spiral.tres",  "Spiral"],
]
const _DEFAULT_DECK : Array = [   # [card path, copies] — expanded into a flat path list
	["res://data/cards/direct_strike.tres", 3],
	["res://data/cards/shield_buff.tres",   3],
	["res://data/cards/mine_card.tres",     2],
	["res://data/cards/boosted_card.tres",  2],
	["res://data/cards/halve_wind.tres",    1],
]
const _DEFAULT_MAP : Array = [   # linear run of stage descriptor paths (M14)
	"res://data/stages/stage_01.tres",
	"res://data/stages/stage_02.tres",
	"res://data/stages/stage_03.tres",
]
const _DEFAULT_ARTIFACTS : Array = [
	"res://data/artifacts/resources/squad_regen.tres",
	"res://data/artifacts/resources/lifesteal.tres",
	"res://data/artifacts/resources/enemy_debuff.tres",
	"res://data/artifacts/resources/free_first_card.tres",
	"res://data/artifacts/resources/idle_actions.tres",
	"res://data/artifacts/resources/death_explosion.tres",
	"res://data/artifacts/resources/long_flight.tres",
	"res://data/artifacts/resources/start_boosted.tres",
]

func start_default_run() -> void:
	var rs := RunState.new()
	for entry in _DEFAULT_SQUAD:
		rs.squad.append(RunUnitState.from_definition(entry[0], entry[1]))
	rs.deck.clear()
	for entry in _DEFAULT_DECK:
		for _i in range(entry[1]):
			rs.deck.append(entry[0])
	rs.artifacts.assign(_DEFAULT_ARTIFACTS)
	rs.map = MapState.build_linear(_DEFAULT_MAP)   # M14: linear 3-stage run
	rs.run_meta = { "seed": randi(), "act": 1, "stage_index": 0 }
	active = rs
