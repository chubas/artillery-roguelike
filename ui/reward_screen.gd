# Post-combat (and pre-first-combat) reward screen: three side-by-side option panels.
# The player picks one; reward_chosen fires and the run controller applies the reward.
# Follows the same code-drawn CanvasLayer pattern as MapScreen.
class_name RewardScreen
extends CanvasLayer

signal reward_chosen(path: String)
signal reward_skipped()

enum Category { UNIT, ARTIFACT, CARD }

var _category : Category = Category.UNIT
var _options  : Array[String] = []

func setup(category: Category, options: Array[String]) -> void:
	_category = category
	_options  = options
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.13, 0.96)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title_text : String
	match _category:
		Category.UNIT:     title_text = "Choose a Unit"
		Category.ARTIFACT: title_text = "Choose an Artifact"
		Category.CARD:     title_text = "Choose a Card"
	var title := _make_label(title_text, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)

	for path in _options:
		var card := OptionCard.new()
		card.setup(_category, path)
		card.clicked.connect(_on_option_clicked)
		row.add_child(card)

	var skip_lbl := _make_label("— Skip —", 16)
	skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	skip_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	skip_lbl.gui_input.connect(_on_skip_input)
	col.add_child(skip_lbl)

func _on_option_clicked(path: String) -> void:
	reward_chosen.emit(path)

func _on_skip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		reward_skipped.emit()

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


# A single selectable reward panel. Draws name + relevant stats; gold border on hover.
class OptionCard:
	extends Control

	signal clicked(path: String)

	const W := 190.0
	const H := 230.0

	var _category : int = RewardScreen.Category.UNIT
	var _path     : String = ""
	var _resource : Resource = null
	var _hovered  : bool = false

	func setup(category: int, path: String) -> void:
		_category = category
		_path     = path
		_resource = load(path)
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(_path)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(W, H))
		draw_rect(r, Color(0.12, 0.14, 0.20, 0.95))
		var border := Color(0.85, 0.70, 0.25) if _hovered else Color(1, 1, 1, 0.45)
		draw_rect(r, border, false, 2.0 if _hovered else 1.0)

		if _resource == null:
			return
		var font := ThemeDB.fallback_font
		var y := 22.0

		match _category:
			RewardScreen.Category.UNIT:
				_draw_unit(font, y)
			RewardScreen.Category.ARTIFACT:
				_draw_artifact(font, y)
			RewardScreen.Category.CARD:
				_draw_card(font, y)

	func _draw_unit(font: Font, y: float) -> void:
		var def : UnitDefinition = _resource as UnitDefinition
		if def == null:
			return
		draw_string(font, Vector2(12, y), def.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 16, Color(0.6, 0.9, 1.0))
		y += 24
		draw_line(Vector2(12, y), Vector2(W - 12, y), Color(1, 1, 1, 0.2), 1.0)
		y += 14
		draw_string(font, Vector2(12, y), "ATK   %d" % def.attack,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		y += 20
		draw_string(font, Vector2(12, y), "HP    %d" % def.max_hp,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		y += 20
		draw_string(font, Vector2(12, y), "Shots: %d" % def.available_shots.size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
		y += 20
		draw_string(font, Vector2(12, y), "Capacity: %d" % def.capacity_cost,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.6, 1.0))

	func _draw_artifact(font: Font, y: float) -> void:
		var def : ArtifactDef = _resource as ArtifactDef
		if def == null:
			return
		draw_string(font, Vector2(12, y), def.artifact_name,
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 15, Color(1.0, 0.85, 0.4))
		y += 22
		draw_line(Vector2(12, y), Vector2(W - 12, y), Color(1, 1, 1, 0.2), 1.0)
		y += 12
		draw_multiline_string(font, Vector2(12, y), def.description,
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 12, 7, Color(1, 1, 1, 0.85))

	func _draw_card(font: Font, y: float) -> void:
		var def : CardDefinition = _resource as CardDefinition
		if def == null:
			return
		draw_string(font, Vector2(12, y), def.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 15, Color(0.5, 1.0, 0.6))
		y += 22
		draw_line(Vector2(12, y), Vector2(W - 12, y), Color(1, 1, 1, 0.2), 1.0)
		y += 12
		draw_string(font, Vector2(12, y), "Cost: %d AP" % def.action_cost,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.85, 0.3))
		y += 20
		draw_string(font, Vector2(12, y), "Effect: %s" % CardDefinition.EffectType.keys()[def.effect_type],
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 12, Color(1, 1, 1, 0.85))
		y += 18
		draw_string(font, Vector2(12, y), "Target: %s" % CardDefinition.TargetType.keys()[def.target_type],
				HORIZONTAL_ALIGNMENT_LEFT, W - 24, 12, Color(1, 1, 1, 0.65))
