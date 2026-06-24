# Event screen (M35): presents an out-of-combat event with choice buttons.
# Follows the code-drawn CanvasLayer pattern. RunController swaps this in when the player
# selects an EVENT node; emits event_completed when a choice is made.
class_name EventScreen
extends CanvasLayer

signal event_completed

var _event : EventDef = null

func setup(ev: EventDef) -> void:
	_event = ev
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.08, 0.10, 0.97)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 60)
	root.add_theme_constant_override("margin_top", 60)
	root.add_theme_constant_override("margin_right", 60)
	root.add_theme_constant_override("margin_bottom", 60)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 28)
	root.add_child(outer)

	# Title
	var title := _make_label(_event.title if _event != null else "EVENT", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	outer.add_child(title)

	# Description
	if _event != null and not _event.description.is_empty():
		var desc := _make_label(_event.description, 15)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.78, 0.80, 0.85))
		outer.add_child(desc)

	# Choice buttons
	var choice_list : Array[Dictionary] = []
	if _event != null:
		choice_list = _event.choices(Run.active)

	var btn_box := VBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 14)
	outer.add_child(btn_box)

	for i in range(choice_list.size()):
		var choice : Dictionary = choice_list[i]
		var btn := Button.new()
		btn.text = choice.get("label", "Choice %d" % (i + 1))
		btn.disabled = not choice.get("available", true)
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(360, 0)
		var idx := i
		btn.pressed.connect(func() -> void: _on_choice(idx))
		btn_box.add_child(btn)

func _on_choice(idx: int) -> void:
	if _event != null:
		_event.resolve(idx, Run.active)
	event_completed.emit()

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l
