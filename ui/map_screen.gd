# Rough run-map screen (M14, run-state spec §7): shows the linear node sequence, the current
# position, and the upcoming stage's threat tags, with an "Enter Stage" button. Placeholder
# quality — code-drawn like the HUD; its job is to prove run agency and display position, not to
# be pretty. The run controller owns the flow; this screen only reads MapState and emits intent.
class_name MapScreen
extends CanvasLayer

signal stage_selected(node: MapNode)
signal new_run_requested

var _map : MapState
var _node_row : NodeRow
var _detail : Label
var _enter_btn : Button
var _end_box : VBoxContainer
var _banner : Label

func setup(map: MapState) -> void:
	_map = map
	_build()
	_refresh()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := _label("ARTILLERY SPACE — RUN MAP", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_node_row = NodeRow.new()
	_node_row.custom_minimum_size = Vector2(600, 96)
	box.add_child(_node_row)

	_detail = _label("", 15)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail)

	_enter_btn = Button.new()
	_enter_btn.text = "Enter Stage"
	_enter_btn.focus_mode = Control.FOCUS_NONE
	_enter_btn.pressed.connect(func() -> void:
		var n := _map.current_node()
		if n != null:
			stage_selected.emit(n))
	box.add_child(_enter_btn)

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

func _refresh() -> void:
	_node_row.map = _map
	_node_row.queue_redraw()
	var n := _map.current_node()
	if n == null:
		_detail.text = ""
		return
	var s := n.stage()
	var obj := "Defeat all" if s.objective.type == ObjectiveDescriptor.Type.DEFEAT_ALL \
			else "Survive %d rounds" % s.objective.survive_rounds
	_detail.text = "Stage %d / %d — %s   ·   Objective: %s   ·   Threats: %s" % [
			_map.current + 1, _map.nodes.size(), s.id, obj, ", ".join(s.threat_tags)]

# Switch to the run-over / run-complete banner (Enter Stage hidden, New Run shown).
func show_end(text: String) -> void:
	_enter_btn.visible = false
	_detail.visible = false
	_end_box.visible = true
	_banner.text = text
	_node_row.queue_redraw()

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


# The linear node strip: a circle per node (green = cleared, yellow = current, grey = upcoming)
# joined by connector lines, with the node index and its threat tags.
class NodeRow:
	extends Control

	var map : MapState

	func _draw() -> void:
		if map == null or map.nodes.is_empty():
			return
		var n := map.nodes.size()
		var spacing := size.x / float(n)
		var cy := 34.0
		var font := ThemeDB.fallback_font
		# Connectors first (behind the circles).
		for i in range(n - 1):
			draw_line(Vector2(spacing * (i + 0.5), cy), Vector2(spacing * (i + 1.5), cy),
					Color(0.4, 0.4, 0.5), 2.0)
		for i in range(n):
			var cx := spacing * (i + 0.5)
			var col : Color
			if map.visited.has(i):
				col = Color(0.3, 0.8, 0.4)        # cleared
			elif i == map.current:
				col = Color(1.0, 0.85, 0.3)        # current
			else:
				col = Color(0.45, 0.45, 0.55)      # upcoming
			draw_circle(Vector2(cx, cy), 15.0, col)
			draw_arc(Vector2(cx, cy), 15.0, 0.0, TAU, 22, Color(0, 0, 0, 0.5), 1.5)
			draw_string(font, Vector2(cx - 4.5, cy + 5.0), str(i + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)
			var tags : Array = map.nodes[i].threat_tags()
			if not tags.is_empty():
				draw_string(font, Vector2(cx - spacing * 0.5 + 4.0, cy + 36.0), ", ".join(tags),
						HORIZONTAL_ALIGNMENT_LEFT, spacing - 8.0, 9, Color(1, 1, 1, 0.6))
