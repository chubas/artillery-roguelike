# The backbone object for a run in progress (run-state spec §3). Single source of truth for
# everything that carries across stages; combat reads from it on entry and writes back on exit.
# RefCounted + to_dict/from_dict keep it serialization-ready without committing to a disk format
# (schema will churn while the run layer is nailed down — disk save/load is a later milestone).
class_name RunState
extends RefCounted

var squad     : Array[RunUnitState] = []
var deck      : Array[String] = []      # canonical card list (resource paths) — edited between stages
var artifacts : Array[String] = []      # active run-level modifiers (resource paths)
var resources : Dictionary = { "gold": 0, "scrap": 0, "intel": 0 }
var map       : Variant = null          # MapState — placeholder until M14
var run_meta  : Dictionary = { "seed": 0, "act": 1, "stage_index": 0 }

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
	return rs
