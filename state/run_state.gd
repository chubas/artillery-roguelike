# The backbone object for a run in progress (run-state spec §3). Single source of truth for
# everything that carries across stages; combat reads from it on entry and writes back on exit.
# RefCounted + to_dict/from_dict keep it serialization-ready without committing to a disk format
# (schema will churn while the run layer is nailed down — disk save/load is a later milestone).
class_name RunState
extends RefCounted

const MAX_SQUAD_CAPACITY := 8

var squad     : Array[RunUnitState] = []
var deck      : Array[String] = []      # canonical card list (resource paths) — edited between stages
var artifacts : Array[String] = []      # active run-level modifiers (resource paths)
var resources : Dictionary = { "gold": 0, "scrap": 0, "intel": 0, "shards": 0 }
var map       : Variant = null          # MapState — placeholder until M14
var run_meta  : Dictionary = { "seed": 0, "act": 1, "stage_index": 0 }
# Reward pools (M16): options offered at reward screens. Units/cards repeat OK; artifacts don't.
var unit_pool     : Array[String] = []
var card_pool     : Array[String] = []
var artifact_pool  : Array[String] = []   # shrinks as artifacts are claimed (no repeats)
var card_upgrades  : Dictionary   = {}    # card.id → upgrade tier (int); seam for card-shop upgrades

func to_dict() -> Dictionary:
	var squad_d : Array = []
	for u in squad:
		squad_d.append(u.to_dict())
	return {
		"squad": squad_d,
		"deck": deck.duplicate(),
		"artifacts": artifacts.duplicate(),
		"resources": resources.duplicate(),
		"run_meta": run_meta.duplicate(),
		"map": (map as MapState).to_dict() if map is MapState else null,
		"unit_pool":     unit_pool.duplicate(),
		"card_pool":     card_pool.duplicate(),
		"artifact_pool": artifact_pool.duplicate(),
	}

static func from_dict(d: Dictionary) -> RunState:
	var rs := RunState.new()
	rs.squad.clear()
	for ud in d.get("squad", []):
		rs.squad.append(RunUnitState.from_dict(ud))
	rs.deck.assign(d.get("deck", []))
	rs.artifacts.assign(d.get("artifacts", []))
	rs.resources = (d.get("resources", {}) as Dictionary).duplicate()
	rs.run_meta = (d.get("run_meta", {}) as Dictionary).duplicate()
	var md = d.get("map", null)
	rs.map = MapState.from_dict(md) if md is Dictionary else null
	rs.unit_pool.assign(d.get("unit_pool", []))
	rs.card_pool.assign(d.get("card_pool", []))
	rs.artifact_pool.assign(d.get("artifact_pool", []))
	return rs
