# Run-map screen (M14+M19+M27): branching DAG, squad bar, Shards HUD, repair/retire.
# RunController owns flow; this screen reads MapState and Run.active for squad actions.
class_name MapScreen
extends CanvasLayer

signal stage_selected(node: MapNode)
signal new_run_requested

var _map : MapState
var _graph : MapGraphView
var _shards_label : Label
var _capacity_label : Label
var _squad_bar : HBoxContainer
var _detail : Label
var _hint : Label
var _end_box : VBoxContainer
var _banner : Label
var _action_menu : PopupPanel
var _repair_btn : Button
var _retire_btn : Button
var _selected_index : int = -1

func setup(map: MapState) -> void:
	_map = map
	_build()
	_refresh()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	root.add_child(outer)

	var top_row := HBoxContainer.new()
	_shards_label = _label("", 14)
	_shards_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	top_row.add_child(_shards_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	_capacity_label = _label("", 14)
	_capacity_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	top_row.add_child(_capacity_label)
	outer.add_child(top_row)

	_squad_bar = HBoxContainer.new()
	_squad_bar.add_theme_constant_override("separation", 8)
	outer.add_child(_squad_bar)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := _label("ARTILLERY SPACE — RUN MAP", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_graph = MapGraphView.new()
	_graph.custom_minimum_size = Vector2(640, 320)
	_graph.node_clicked.connect(_on_node_clicked)
	box.add_child(_graph)

	_detail = _label("", 14)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail)

	_hint = _label("Click a highlighted stage to continue.", 13)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	box.add_child(_hint)

	_end_box = VBoxContainer.new()
	_end_box.add_theme_constant_override("separation", 10)
	_end_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_box.visible = false
	_banner = _label("", 30)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_box.add_child(_banner)
	var newrun := Button.new()
	newrun.text = "New Run"
	newrun.focus_mode = Control.FOCUS_NONE
	newrun.pressed.connect(func() -> void: new_run_requested.emit())
	_end_box.add_child(newrun)
	box.add_child(_end_box)

	_build_action_menu()

func _build_action_menu() -> void:
	_action_menu = PopupPanel.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_action_menu.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_repair_btn = Button.new()
	_repair_btn.text = "Repair (5 ◆)"
	_repair_btn.focus_mode = Control.FOCUS_NONE
	_repair_btn.pressed.connect(_on_repair_pressed)
	box.add_child(_repair_btn)
	_retire_btn = Button.new()
	_retire_btn.text = "Retire (+2 ◆)"
	_retire_btn.focus_mode = Control.FOCUS_NONE
	_retire_btn.pressed.connect(_on_retire_pressed)
	box.add_child(_retire_btn)
	add_child(_action_menu)

func _on_node_clicked(node_index: int) -> void:
	if not _map.can_select(node_index):
		return
	if _map.visited.has(_map.current) and node_index != _map.current:
		_map.select_next(node_index)
	stage_selected.emit(_map.nodes[node_index])

func _on_portrait_clicked(index: int, portrait: UnitPortrait) -> void:
	_selected_index = index
	var unit : RunUnitState = Run.active.squad[index]
	_repair_btn.visible = unit.is_disabled
	_repair_btn.disabled = not SquadOps.can_repair(Run.active, unit)
	var pos : Vector2 = portrait.global_position + Vector2(0.0, portrait.size.y + 4.0)
	_action_menu.popup(Rect2i(int(pos.x), int(pos.y), 1, 1))

func _on_repair_pressed() -> void:
	if _selected_index >= 0:
		SquadOps.repair_unit(Run.active, _selected_index)
	_action_menu.hide()
	_refresh()

func _on_retire_pressed() -> void:
	if _selected_index >= 0:
		SquadOps.retire_unit(Run.active, _selected_index)
	_action_menu.hide()
	_selected_index = -1
	_refresh()

func _refresh() -> void:
	_shards_label.text = "◆ Shards: %d" % Run.active.resources.get("shards", 0)
	_capacity_label.text = "Squad Capacity: %d / %d" % [
			SquadOps.used_capacity(Run.active), RunState.MAX_SQUAD_CAPACITY]
	_rebuild_squad_bar()
	_graph.map = _map
	_graph.queue_redraw()
	var choices := _map.next_choice_indices()
	if choices.is_empty() and _map.visited.has(_map.current):
		_detail.text = "Run path complete."
		_hint.text = ""
		return
	var preview_idx := choices[0] if choices.size() == 1 else _map.current
	if preview_idx >= 0 and preview_idx < _map.nodes.size():
		var s := _map.nodes[preview_idx].stage()
		if s != null:
			var obj := "Defeat all" if s.objective.type == ObjectiveDescriptor.Type.DEFEAT_ALL \
					else "Survive %d rounds" % s.objective.survive_rounds
			_detail.text = "%s   ·   Objective: %s   ·   Threats: %s" % [
					s.id, obj, ", ".join(s.threat_tags)]
	if choices.size() == 1:
		_hint.text = "Click a highlighted stage to continue."
	else:
		_hint.text = "Choose your next stage (%d paths)." % choices.size()

func _rebuild_squad_bar() -> void:
	for child in _squad_bar.get_children():
		child.queue_free()
	for i in range(Run.active.squad.size()):
		var rus : RunUnitState = Run.active.squad[i]
		var portrait : UnitPortrait = UnitPortrait.new()
		portrait.setup(rus)
		var idx := i
		portrait.clicked.connect(func() -> void: _on_portrait_clicked(idx, portrait))
		_squad_bar.add_child(portrait)

func show_end(text: String) -> void:
	_refresh()
	_detail.visible = false
	_hint.visible = false
	_end_box.visible = true
	_banner.text = text
	_graph.queue_redraw()

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


# Diamond / DAG map: nodes laid out by layer, edges from next_nodes, click-to-select.
class MapGraphView:
	extends Control

	signal node_clicked(node_index: int)

	const NODE_R := 18.0
	const ROW_H := 64.0

	var map : MapState
	var _positions : Dictionary = {}   # index -> Vector2 center

	func _draw() -> void:
		_positions.clear()
		if map == null or map.nodes.is_empty():
			return
		_compute_positions()
		for i in range(map.nodes.size()):
			var from : Vector2 = _positions[i]
			for tgt in map.nodes[i].next_nodes:
				if _positions.has(tgt):
					draw_line(from, _positions[tgt], Color(0.38, 0.4, 0.52, 0.85), 2.0)
		for i in range(map.nodes.size()):
			_draw_node(i)

	func _compute_positions() -> void:
		var by_layer : Dictionary = {}
		var max_layer := 0
		for i in range(map.nodes.size()):
			var ly : int = map.nodes[i].layer
			max_layer = maxi(max_layer, ly)
			if not by_layer.has(ly):
				by_layer[ly] = []
			by_layer[ly].append(i)
		for ly in range(max_layer + 1):
			if not by_layer.has(ly):
				continue
			var row : Array = by_layer[ly]
			var row_w := size.x
			var spacing := row_w / float(row.size() + 1)
			var y := ROW_H * 0.5 + ly * ROW_H
			for j in range(row.size()):
				var idx : int = row[j]
				_positions[idx] = Vector2(spacing * (j + 1), y)

	func _draw_node(index: int) -> void:
		if not _positions.has(index):
			return
		var c : Vector2 = _positions[index]
		var font := ThemeDB.fallback_font
		var fill : Color
		if map.visited.has(index):
			fill = Color(0.28, 0.78, 0.42)
		elif map.can_select(index):
			fill = Color(0.55, 0.58, 0.72)
		else:
			fill = Color(0.32, 0.33, 0.4, 0.65)
		draw_circle(c, NODE_R, fill)
		if index == map.current:
			draw_arc(c, NODE_R + 3.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.28, 0.95), 2.5)
		if map.can_select(index):
			draw_arc(c, NODE_R + 1.0, 0.0, TAU, 32, Color(0.95, 0.95, 1.0, 0.9), 2.0)
		draw_string(font, Vector2(c.x - 4.0, c.y + 5.0), str(index + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.05, 0.08))
		var tags : Array = map.nodes[index].threat_tags()
		if not tags.is_empty():
			var tw := font.get_string_size(", ".join(tags), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(font, Vector2(c.x - tw * 0.5, c.y + NODE_R + 14.0), ", ".join(tags),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.55))

	func _gui_input(event: InputEvent) -> void:
		if map == null or map.nodes.is_empty():
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			if _positions.is_empty():
				_compute_positions()
			var mp : Vector2 = event.position
			for idx in _positions:
				if mp.distance_to(_positions[idx]) <= NODE_R + 6.0:
					node_clicked.emit(idx)
					accept_event()
					return
