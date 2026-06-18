# The run map (run-state spec §7): a graph of stage-wrapping nodes with a current position that
# advances as the player clears stages. M14 starts dead simple — a linear sequence of COMBAT
# nodes, no branching. Lives in RunState.map (mutable run state: current/visited change).
class_name MapState
extends RefCounted

var nodes   : Array[MapNode] = []
var current : int = 0
var visited : Array[int] = []   # node indices cleared

func current_node() -> MapNode:
	if current >= 0 and current < nodes.size():
		return nodes[current]
	return null

func is_last() -> bool:
	return current >= nodes.size() - 1

func mark_visited() -> void:
	if not visited.has(current):
		visited.append(current)

func advance() -> void:
	current += 1

func is_complete() -> bool:
	return visited.size() >= nodes.size()

# A linear run: one COMBAT node per stage descriptor path, in order.
static func build_linear(stage_paths: Array) -> MapState:
	var m := MapState.new()
	for p in stage_paths:
		m.nodes.append(MapNode.make_combat(p))
	return m

func to_dict() -> Dictionary:
	var nd : Array = []
	for n in nodes:
		nd.append(n.to_dict())
	return { "nodes": nd, "current": current, "visited": visited.duplicate() }

static func from_dict(d: Dictionary) -> MapState:
	var m := MapState.new()
	for nd in d.get("nodes", []):
		m.nodes.append(MapNode.from_dict(nd))
	m.current = d.get("current", 0)
	m.visited.assign(d.get("visited", []))
	return m
