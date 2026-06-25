# M36: Repair node screen. Three options: distribute heal, single unit heal, add Heal Vial card.
class_name RepairScreen
extends CanvasLayer

signal repair_completed

const HEAL_POOL    := 4
const SINGLE_HEAL  := 6
const HEAL_VIAL_PATH := "res://data/cards/heal_vial.tres"

var _pool_remaining : int = HEAL_POOL
var _pool_label     : Label = null
var _unit_rows      : Array = []   # [{unit, hp_label, plus_btn}]
var _content        : VBoxContainer = null

func setup() -> void:
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 40)
	root.add_theme_constant_override("margin_top", 30)
	root.add_theme_constant_override("margin_right", 40)
	root.add_theme_constant_override("margin_bottom", 30)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(outer)

	var title := _label("REPAIR", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.85, 0.55, 0.15))
	outer.add_child(title)

	var subtitle := _label("Choose how to restore your squad.", 14)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	outer.add_child(subtitle)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	outer.add_child(_content)

	_show_main_options()

func _show_main_options() -> void:
	_clear_content()

	var opt_a := _make_button("Distribute %d HP among your units" % HEAL_POOL,
			func() -> void: _show_distribute())
	_content.add_child(opt_a)

	var opt_b := _make_button("Heal one unit for %d HP" % SINGLE_HEAL,
			func() -> void: _show_single())
	_content.add_child(opt_b)

	var opt_c := _make_button("Add a Heal Vial card to your deck (CONSUMABLE, heal 10 HP)",
			func() -> void: _apply_heal_vial())
	_content.add_child(opt_c)

func _show_distribute() -> void:
	_clear_content()
	_pool_remaining = HEAL_POOL
	_unit_rows.clear()

	var header := _label("Distribute %d HP — click + to allocate." % HEAL_POOL, 14)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	_pool_label = _label("Remaining: %d" % _pool_remaining, 16)
	_pool_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.15))
	_content.add_child(_pool_label)

	for rus in Run.active.squad:
		var unit : RunUnitState = rus
		if unit.is_disabled:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)

		var name_lbl := _label(unit.display_name, 13)
		name_lbl.custom_minimum_size.x = 100
		row.add_child(name_lbl)

		var hp_lbl := _label("%d / %d HP" % [unit.current_hp, unit.max_hp], 13)
		hp_lbl.custom_minimum_size.x = 80
		row.add_child(hp_lbl)

		var plus_btn := _make_button("+1", Callable())
		plus_btn.custom_minimum_size = Vector2(40, 24)
		plus_btn.disabled = (unit.current_hp >= unit.max_hp)
		_unit_rows.append({ "unit": unit, "hp_label": hp_lbl, "plus_btn": plus_btn })
		var entry : Dictionary = _unit_rows.back()
		plus_btn.pressed.connect(func() -> void: _distribute_add(entry))
		row.add_child(plus_btn)

	var done := _make_button("Done", func() -> void: repair_completed.emit())
	_content.add_child(done)

func _distribute_add(entry: Dictionary) -> void:
	if _pool_remaining <= 0:
		return
	var unit : RunUnitState = entry["unit"]
	if unit.current_hp >= unit.max_hp:
		return
	unit.current_hp = mini(unit.current_hp + 1, unit.max_hp)
	_pool_remaining -= 1
	(entry["hp_label"] as Label).text = "%d / %d HP" % [unit.current_hp, unit.max_hp]
	(entry["plus_btn"] as Button).disabled = (unit.current_hp >= unit.max_hp)
	_pool_label.text = "Remaining: %d" % _pool_remaining
	if _pool_remaining <= 0:
		for e in _unit_rows:
			(e["plus_btn"] as Button).disabled = true

func _show_single() -> void:
	_clear_content()
	var header := _label("Select a unit to heal %d HP." % SINGLE_HEAL, 14)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	for rus in Run.active.squad:
		var unit : RunUnitState = rus
		if unit.is_disabled:
			continue
		var already_full := unit.current_hp >= unit.max_hp
		var lbl := "%s  (%d/%d HP)" % [unit.display_name, unit.current_hp, unit.max_hp]
		var btn := _make_button(lbl, Callable())
		btn.disabled = already_full
		var u := unit
		btn.pressed.connect(func() -> void:
			u.current_hp = mini(u.current_hp + SINGLE_HEAL, u.max_hp)
			repair_completed.emit())
		_content.add_child(btn)

	var cancel := _make_button("Back", func() -> void: _show_main_options())
	_content.add_child(cancel)

func _apply_heal_vial() -> void:
	Run.active.deck.append(HEAL_VIAL_PATH)
	_clear_content()
	var msg := _label("Heal Vial added to your deck.", 16)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(0.2, 0.8, 0.4))
	_content.add_child(msg)
	var done := _make_button("Done", func() -> void: repair_completed.emit())
	_content.add_child(done)

func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	_unit_rows.clear()

func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	if callback != null and callback.is_valid():
		b.pressed.connect(callback)
	return b

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
