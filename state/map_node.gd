# One node on the run map (run-state spec §7): wraps a stage (or, later, an event/shop) plus its
# node type. Holds the stage as a resource path (id-as-path) so it stays serializable like the
# rest of the run state. Only COMBAT is used in M14; the other types reserve the seam.
class_name MapNode
extends RefCounted

enum Type { COMBAT, EVENT, SHOP, BOSS }

var type : Type = Type.COMBAT
var stage_path : String = ""   # res:// to a StageDescriptor

func stage() -> StageDescriptor:
	return load(stage_path)

# Threat tags surfaced to the player for telegraphing — read live from the descriptor.
func threat_tags() -> Array:
	var s := stage()
	return s.threat_tags if s != null else []

func to_dict() -> Dictionary:
	return { "type": type, "stage_path": stage_path }

static func from_dict(d: Dictionary) -> MapNode:
	var n := MapNode.new()
	n.type = d.get("type", Type.COMBAT)
	n.stage_path = d.get("stage_path", "")
	return n

static func make_combat(stage_path: String) -> MapNode:
	var n := MapNode.new()
	n.type = Type.COMBAT
	n.stage_path = stage_path
	return n
