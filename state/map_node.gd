# One node on the run map (run-state spec §7): wraps a stage (or, later, an event/shop) plus its
# node type. Holds the stage as a resource path (id-as-path) so it stays serializable like the
# rest of the run state. M19: forward edges live on each node (`next_nodes`).
class_name MapNode
extends RefCounted

enum Type { COMBAT, EVENT, SHOP, BOSS }

var type : Type = Type.COMBAT
var stage_path : String = ""   # res:// to a StageDescriptor
## Forward edges: indices into MapState.nodes (M19 DAG). Empty = terminal node.
var next_nodes : Array[int] = []
## UI layout row (0 = top of diamond). Gameplay ignores this — graph edges are authoritative.
var layer : int = 0
## M33: run-assigned terrain profile (empty = legacy generator) and per-stage RNG seed.
var terrain_profile_path : String = ""
var stage_seed           : int    = 0

func stage() -> StageDescriptor:
	if stage_path.is_empty():
		return null
	return load(stage_path)

func threat_tags() -> Array:
	var s := stage()
	return s.threat_tags if s != null else []

func to_dict() -> Dictionary:
	return {
		"type": type,
		"stage_path": stage_path,
		"next_nodes": next_nodes.duplicate(),
		"layer": layer,
		"terrain_profile_path": terrain_profile_path,
		"stage_seed": stage_seed,
	}

static func from_dict(d: Dictionary) -> MapNode:
	var n := MapNode.new()
	n.type = d.get("type", Type.COMBAT)
	n.stage_path = d.get("stage_path", "")
	n.next_nodes.assign(d.get("next_nodes", []))
	n.layer = d.get("layer", 0)
	n.terrain_profile_path = d.get("terrain_profile_path", "")
	n.stage_seed           = d.get("stage_seed", 0)
	return n

static func make_combat(stage_path: String) -> MapNode:
	var n := MapNode.new()
	n.type = Type.COMBAT
	n.stage_path = stage_path
	return n
