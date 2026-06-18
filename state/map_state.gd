# The run map (run-state spec §7): a forward-only DAG of stage nodes. M14 started linear;
# M19 generalizes to explicit `next_nodes` edges (diamond prototype: 1-2-3-2-1).
class_name MapState
extends RefCounted

var nodes   : Array[MapNode] = []
var current : int = 0
var visited : Array[int] = []   # cleared node indices

func current_node() -> MapNode:
	if current >= 0 and current < nodes.size():
		return nodes[current]
	return null

func node_index(node: MapNode) -> int:
	return nodes.find(node)

## True when the current node has no forward edges (run ends after clearing it).
func is_terminal() -> bool:
	var n := current_node()
	return n != null and n.next_nodes.is_empty()

## Run is finished once a terminal node has been cleared.
func is_complete() -> bool:
	for idx in visited:
		if idx >= 0 and idx < nodes.size() and nodes[idx].next_nodes.is_empty():
			return true
	return false

func mark_visited() -> void:
	if not visited.has(current):
		visited.append(current)

## Legal next picks for the map UI. Unvisited current → must fight current; visited → forward edges.
func next_choice_indices() -> Array[int]:
	if nodes.is_empty():
		return []
	if not visited.has(current):
		return [current]
	var out : Array[int] = []
	for idx in current_node().next_nodes:
		if not visited.has(idx):
			out.append(idx)
	return out

func next_choices() -> Array:
	var out : Array = []
	for idx in next_choice_indices():
		out.append(nodes[idx])
	return out

func can_select(node_index: int) -> bool:
	return node_index in next_choice_indices()

## Move to a legal next node (sets current before entering combat).
func select_next(node_index: int) -> void:
	if not can_select(node_index):
		push_error("MapState.select_next: illegal pick %d" % node_index)
		return
	current = node_index

# --- Builders ------------------------------------------------------------------

## Linear run (smoke / regression): sequential edges 0→1→2→…
static func build_linear(stage_paths: Array) -> MapState:
	var m := MapState.new()
	for i in range(stage_paths.size()):
		var n := MapNode.make_combat(stage_paths[i])
		n.layer = i
		if i < stage_paths.size() - 1:
			n.next_nodes = [i + 1]
		m.nodes.append(n)
	return m

## Diamond prototype: 9 nodes, layers 1-2-3-2-1, forward-only branching.
static func build_diamond(stage_paths: Array) -> MapState:
	var m := MapState.new()
	if stage_paths.is_empty():
		return m
	var layers := [[0], [1, 2], [3, 4, 5], [6, 7], [8]]
	var edges := {
		0: [1, 2],
		1: [3, 4],
		2: [4, 5],
		3: [6],
		4: [6, 7],
		5: [7],
		6: [8],
		7: [8],
		8: [],
	}
	for layer_i in range(layers.size()):
		for idx in layers[layer_i]:
			var n := MapNode.make_combat(stage_paths[idx % stage_paths.size()])
			n.layer = layer_i
			n.next_nodes.assign(edges.get(idx, []))
			while m.nodes.size() <= idx:
				m.nodes.append(MapNode.make_combat(""))
			m.nodes[idx] = n
	return m

# --- Legacy aliases (linear-only callers) --------------------------------------

func is_last() -> bool:
	return is_terminal()

func advance() -> void:
	# Linear compat: jump to the sole forward edge if exactly one choice after visiting.
	if visited.has(current) and current_node().next_nodes.size() == 1:
		current = current_node().next_nodes[0]

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
