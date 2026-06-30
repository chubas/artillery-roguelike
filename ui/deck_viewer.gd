# M37: Modal deck viewer. Works in both world map and combat contexts.
# Opened from MapScreen (Deck [N] button) or HUD (clickable deck label).
class_name DeckViewer
extends Control

signal closed

func setup() -> void:
	set_as_top_level(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Click outside panel to close
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			closed.emit())

	var panel_root := MarginContainer.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_theme_constant_override("margin_left",   80)
	panel_root.add_theme_constant_override("margin_top",    50)
	panel_root.add_theme_constant_override("margin_right",  80)
	panel_root.add_theme_constant_override("margin_bottom", 50)
	add_child(panel_root)

	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.07, 0.08, 0.12)
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(panel_bg)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel_root.add_child(outer)

	# ── Title row ────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var deck : Array = Run.active.deck if Run.active != null else []
	var title := _label("DECK  [%d cards]" % deck.size(), 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title_row.add_child(title)

	var close_btn := _make_button("✕  Close", func() -> void: closed.emit())
	title_row.add_child(close_btn)

	# ── Body: card list (left) + detail panel (right) ────────────────────────
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Detail panel (right) — built first so card buttons can reference it
	var detail_panel := VBoxContainer.new()
	detail_panel.custom_minimum_size = Vector2(240, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_constant_override("separation", 8)

	var detail_name := _label("", 18)
	detail_name.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	detail_panel.add_child(detail_name)

	var detail_body := _label("", 13)
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_body.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	detail_panel.add_child(detail_body)

	# Card list (left)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# Deduplicate deck by path
	var counts : Dictionary = {}
	for path in deck:
		counts[path] = counts.get(path, 0) + 1

	if counts.is_empty():
		var empty_lbl := _label("(Deck is empty)", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		list.add_child(empty_lbl)
	else:
		for path in counts:
			var def : CardDefinition = load(path)
			if def == null:
				continue
			var count : int = counts[path]
			var suffix := "  (x%d)" % count if count > 1 else ""
			var row_text := "[%d AP]  %s%s" % [def.action_cost, def.display_name, suffix]
			if def.is_consumable:
				row_text += "  ◇"
			var row_btn := _make_button(row_text, Callable())
			row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var kw := KeywordRegistry.tooltip(KeywordRegistry.for_card(def))
			if kw != "":
				row_btn.tooltip_text = kw
			var d := def
			row_btn.mouse_entered.connect(func() -> void:
				detail_name.text = d.display_name
				detail_body.text = _card_detail(d))
			list.add_child(row_btn)

	body.add_child(detail_panel)

func _card_detail(def: CardDefinition) -> String:
	var lines : Array[String] = []
	lines.append("Cost: %d AP" % def.action_cost)
	lines.append("Effect: %s" % CardDefinition.EffectType.keys()[def.effect_type])
	lines.append("Target: %s" % CardDefinition.TargetType.keys()[def.target_type])
	if def.magnitude != 0:
		lines.append("Magnitude: %d" % def.magnitude)
	if def.is_consumable:
		lines.append("")
		lines.append("CONSUMABLE — removed from deck after use")
	var kw := KeywordRegistry.tooltip(KeywordRegistry.for_card(def))
	if kw != "":
		lines.append("")
		lines.append("Keywords:")
		lines.append(kw)
	return "\n".join(lines)

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
