# M37: Modal squad viewer. Works in both world map (retire enabled) and combat (read-only).
class_name SquadViewer
extends Control

signal closed
signal retired   # emitted after a unit is retired in world mode

var _world_mode   : bool = false
var _selected_idx : int  = -1
var _retire_btn   : Button = null
var _row_btns     : Array = []   # Array of Button

func setup(world_mode: bool) -> void:
	_world_mode = world_mode
	set_as_top_level(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			closed.emit())

	var panel_root := MarginContainer.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_theme_constant_override("margin_left",   160)
	panel_root.add_theme_constant_override("margin_top",     60)
	panel_root.add_theme_constant_override("margin_right",  160)
	panel_root.add_theme_constant_override("margin_bottom",  60)
	add_child(panel_root)

	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.07, 0.08, 0.12)
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(panel_bg)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel_root.add_child(outer)

	# ── Title row ────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var title := _label("SQUAD", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title_row.add_child(title)

	var close_btn := _make_button("✕  Close", func() -> void: closed.emit())
	title_row.add_child(close_btn)

	# ── Unit list ─────────────────────────────────────────────────────────────
	var squad : Array = Run.active.squad if Run.active != null else []
	if squad.is_empty():
		outer.add_child(_label("(No units)", 14))
	else:
		for i in range(squad.size()):
			var rus : RunUnitState = squad[i]
			var row_text : String
			if rus.is_disabled:
				row_text = "%s  [DISABLED]" % rus.display_name
			else:
				row_text = "%s  [%d / %d HP]" % [rus.display_name, rus.current_hp, rus.max_hp]
			var row_btn := _make_button(row_text, Callable())
			row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if rus.is_disabled:
				row_btn.modulate = Color(1, 1, 1, 0.45)
			var idx := i
			row_btn.pressed.connect(func() -> void: _on_row_pressed(idx))
			_row_btns.append(row_btn)
			outer.add_child(row_btn)

	# ── Retire button (world mode only) ──────────────────────────────────────
	if _world_mode:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		outer.add_child(spacer)

		var hint := _label("Select a unit to retire it from the run (+2◆).", 12)
		hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.78))
		outer.add_child(hint)

		_retire_btn = _make_button("Retire Unit", func() -> void: _on_retire_pressed())
		_retire_btn.disabled = true
		_retire_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		outer.add_child(_retire_btn)

func _on_row_pressed(idx: int) -> void:
	if _selected_idx == idx:
		_selected_idx = -1
	else:
		_selected_idx = idx
	_update_selection()

func _update_selection() -> void:
	for i in range(_row_btns.size()):
		var btn : Button = _row_btns[i]
		if i == _selected_idx:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		else:
			btn.remove_theme_color_override("font_color")
	if _retire_btn != null:
		_retire_btn.disabled = (_selected_idx < 0)

func _on_retire_pressed() -> void:
	if _selected_idx < 0 or Run.active == null:
		return
	SquadOps.retire_unit(Run.active, _selected_idx)
	retired.emit()

func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
