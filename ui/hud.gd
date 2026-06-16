# Screen-space HUD (M2 spec §10): angle/power readouts, action pips, unit info,
# turn indicator, End Turn + Undo buttons. Placeholder quality by design.
class_name HUD
extends CanvasLayer

signal end_turn_pressed
signal undo_pressed
signal shot_selected(index: int)
signal card_selected(index: int)

var _angle_label : Label
var _power_label : Label
var _power_bar : PowerBar
var _action_pips : ActionPips
var _unit_info_label : Label
var _turn_label : Label
var _end_turn_btn : Button
var _undo_btn : Button
var _shot_box : HBoxContainer
var _shot_buttons : Array = []
var _shot_sig : String = ""   # cache: rebuild chips only when the shot list changes
var _card_box : HBoxContainer
var _card_chips : Array = []
var _card_sig : String = ""   # cache: rebuild chips only when the card list changes
var _inspector : UnitInspector

func _ready() -> void:
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_bottom_right()

func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_angle_label = _make_label(16)
	box.add_child(_angle_label)
	_power_label = _make_label(13)
	box.add_child(_power_label)
	_power_bar = PowerBar.new()
	_power_bar.custom_minimum_size = Vector2(220, 14)
	box.add_child(_power_bar)
	_action_pips = ActionPips.new()
	_action_pips.custom_minimum_size = Vector2(Const.MAX_ACTIONS * 20, 18)
	box.add_child(_action_pips)
	_shot_box = HBoxContainer.new()
	_shot_box.add_theme_constant_override("separation", 4)
	box.add_child(_shot_box)
	_card_box = HBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 4)
	box.add_child(_card_box)
	var hint := _make_label(11)
	hint.text = "↑/↓ angle · ←/→ move · Space charge/fire · 1/2/3 shot · Q/E card · Esc cancel · Tab select · WASD pan"
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)

func _build_top_center() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 8
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_turn_label = _make_label(18)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_turn_label)
	_unit_info_label = _make_label(14)
	_unit_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_unit_info_label)

func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -150
	box.offset_right = -12
	box.offset_top = 10
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.focus_mode = Control.FOCUS_NONE
	_end_turn_btn.pressed.connect(func(): end_turn_pressed.emit())
	box.add_child(_end_turn_btn)
	_undo_btn = Button.new()
	_undo_btn.text = "Undo Move"
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.pressed.connect(func(): undo_pressed.emit())
	box.add_child(_undo_btn)

# Unit Inspector (M5 polish): bottom-right panel showing whichever unit (ally or enemy)
# is currently inspected — name, HP/shield, active shot + description, status effects.
func _build_bottom_right() -> void:
	_inspector = UnitInspector.new()
	_inspector.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inspector.offset_left = -240
	_inspector.offset_right = -12
	_inspector.offset_top = -150
	_inspector.offset_bottom = -12
	_inspector.visible = false
	add_child(_inspector)

func set_inspected_unit(unit: Unit) -> void:
	_inspector.unit = unit
	_inspector.visible = unit != null and is_instance_valid(unit)
	_inspector.queue_redraw()

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

# --- Setters (no-op when unchanged; called every frame by CombatManager) ----------
func set_angle(deg: float) -> void:
	_set_text(_angle_label, "Angle: %d°" % roundi(deg))

func set_angle_none() -> void:
	_set_text(_angle_label, "Angle: —")

# last_frac (0–1) draws a Gunbound-style marker at the unit's previous shot power; < 0 hides it.
func set_power(frac: float, charging: bool, last_frac: float = -1.0) -> void:
	if _power_bar.frac != frac or _power_bar.charging != charging \
			or _power_bar.last_frac != last_frac:
		_power_bar.frac = frac
		_power_bar.charging = charging
		_power_bar.last_frac = last_frac
		_power_bar.queue_redraw()
	_set_text(_power_label, "Power: %d%%" % roundi(frac * 100.0) if charging else "Power: —")

func set_actions(current: int, maximum: int) -> void:
	if _action_pips.current != current or _action_pips.maximum != maximum:
		_action_pips.current = current
		_action_pips.maximum = maximum
		_action_pips.queue_redraw()

func set_unit_info(text: String) -> void:
	_set_text(_unit_info_label, text)

# Shot selector chips (M3 §8). Rebuilds buttons only when the shot list identity changes;
# otherwise just refreshes highlight (active shot) and affordability (greys unaffordable).
func set_shots(shots: Array, active: ShotDefinition, actions_left: int) -> void:
	var sig := ""
	for s in shots:
		sig += (s.id if s != null else "?") + "|"
	if sig != _shot_sig:
		_shot_sig = sig
		for b in _shot_buttons:
			b.queue_free()
		_shot_buttons.clear()
		for i in range(shots.size()):
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_font_size_override("font_size", 11)
			btn.pressed.connect(func(): shot_selected.emit(i))
			_shot_box.add_child(btn)
			_shot_buttons.append(btn)
	for i in range(_shot_buttons.size()):
		var s : ShotDefinition = shots[i]
		var btn : Button = _shot_buttons[i]
		var afford := actions_left >= s.action_cost
		var cost_txt := "" if s.action_cost <= 0 else " (%d)" % s.action_cost
		btn.text = "%d:%s%s" % [i + 1, s.display_name, cost_txt]
		btn.disabled = not afford
		var is_active := active != null and s == active
		btn.modulate = Color(1.0, 0.95, 0.5) if is_active else Color(1, 1, 1, 0.85)

# Card chips (M5). Little card-faces (description + AP cost) instead of text buttons.
# Same rebuild-only-on-identity-change pattern as set_shots(); greys out unaffordable
# cards and draws a green outline on the currently selected (pending) card.
func set_cards(cards: Array, pending: CardDefinition, actions_left: int, used: Array = []) -> void:
	var sig := ""
	for c in cards:
		sig += (c.id if c != null else "?") + "|"
	if sig != _card_sig:
		_card_sig = sig
		for chip in _card_chips:
			chip.queue_free()
		_card_chips.clear()
		for i in range(cards.size()):
			var chip := CardChip.new()
			chip.card = cards[i]
			chip.clicked.connect(func(): card_selected.emit(i))
			_card_box.add_child(chip)
			_card_chips.append(chip)
	for i in range(_card_chips.size()):
		var c : CardDefinition = cards[i]
		var chip : CardChip = _card_chips[i]
		chip.set_state(actions_left >= c.action_cost, pending != null and c == pending, c in used)

func set_turn_text(text: String) -> void:
	_set_text(_turn_label, text)

func set_end_turn_alert(alert: bool) -> void:
	var m := Color(1.0, 0.35, 0.3) if alert else Color.WHITE
	if _end_turn_btn.modulate != m:
		_end_turn_btn.modulate = m

func set_undo_enabled(enabled: bool) -> void:
	if _undo_btn.disabled == enabled:
		_undo_btn.disabled = not enabled

func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


class PowerBar:
	extends Control

	var frac := 0.0
	var charging := false
	var last_frac := -1.0   # previous-shot power memory marker; < 0 = hidden

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		if charging and frac > 0.0:
			var fill := Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2))
			draw_rect(fill, Color(0.2, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.15), frac))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)
		# Last-power marker: a small downward triangle straddling the top edge (M4).
		if last_frac >= 0.0:
			var x := 1.0 + (size.x - 2.0) * last_frac
			var pts := PackedVector2Array([
				Vector2(x, 3), Vector2(x - 4, -4), Vector2(x + 4, -4)])
			draw_colored_polygon(pts, Color(1.0, 0.95, 0.5))


class ActionPips:
	extends Control

	var current := 5
	var maximum := 5

	func _draw() -> void:
		# 20px stride keeps a 10-AP bar (M4) compact; pips shrink to 16px wide.
		for i in range(maximum):
			var rect := Rect2(i * 20, 0, 16, 18)
			if i < current:
				draw_rect(rect, Color(0.95, 0.85, 0.3))
			else:
				draw_rect(rect, Color(0, 0, 0, 0.45))
			draw_rect(rect, Color(1, 1, 1, 0.5), false, 1.0)


# A single card face (M5): a small coloured rectangle showing the card's description and
# its action-point cost. Clicking it selects the card; a green outline marks the selected
# one, and an unaffordable card is greyed out.
class CardChip:
	extends Control

	signal clicked

	const W := 66.0
	const H := 84.0

	var card : CardDefinition
	var _affordable := true
	var _selected := false
	var _used := false   # played this turn → deactivated, unclickable

	func _ready() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = card.display_name

	func set_state(affordable: bool, selected: bool, used: bool) -> void:
		if affordable == _affordable and selected == _selected and used == _used:
			return
		_affordable = affordable
		_selected = selected
		_used = used
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if _used:
			return   # spent cards swallow clicks but don't re-select
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(W, H))
		var face := card.color
		var text_col := Color.WHITE
		if _used:
			face = face.lerp(Color(0.5, 0.5, 0.5), 0.6)   # spent: desaturated like a done unit
			text_col = Color(1, 1, 1, 0.4)
		elif not _affordable:
			face = face.lerp(Color(0.22, 0.22, 0.26), 0.7)
			text_col = Color(1, 1, 1, 0.45)
		# Card body: a darker border frame around the tinted face.
		draw_rect(r, face.darkened(0.45))
		draw_rect(r.grow(-2.0), face.darkened(0.15))
		var font := ThemeDB.fallback_font
		# Description, wrapped within the card width.
		draw_multiline_string(font, Vector2(5, 16), card.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, W - 10, 12, 3, text_col)
		# Action-point cost badge, bottom-left.
		var badge := Rect2(4, H - 22, 18, 18)
		draw_rect(badge, Color(0.08, 0.09, 0.14, 0.92))
		draw_rect(badge, Color(1, 1, 1, 0.35), false, 1.0)
		draw_string(font, Vector2(9, H - 8), str(card.action_cost),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)
		# Spent veil + diagonal slash read as "deactivated" (selection outline suppressed).
		if _used:
			draw_rect(r, Color(0, 0, 0, 0.35))
			draw_line(Vector2(5, 5), Vector2(W - 5, H - 5), Color(0.85, 0.3, 0.25, 0.85), 2.5)
		elif _selected:
			draw_rect(r, Color(0.3, 0.95, 0.4), false, 3.0)


# Unit Inspector panel (M5 polish): text-only readout of whichever unit is currently
# inspected (ally via selection, enemy via click). Drawn rather than Label-based to
# match the rest of this file's placeholder-quality custom-draw widgets.
class UnitInspector:
	extends Control

	var unit : Unit = null

	func _draw() -> void:
		if unit == null or not is_instance_valid(unit):
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.06, 0.07, 0.1, 0.85))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
		var font := ThemeDB.fallback_font
		var y := 18.0
		var name_col := Color(0.4, 0.75, 1.0) if unit.is_player else Color(1.0, 0.45, 0.4)
		draw_string(font, Vector2(10, y), unit.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_col)
		y += 20
		draw_string(font, Vector2(10, y), "HP: %d / %d" % [unit.hp, unit.definition.max_hp],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		y += 16
		var shield_txt := "Shield: %d" % unit.shield if unit.shield > 0 else "Shield: —"
		draw_string(font, Vector2(10, y), shield_txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.85, 1.0))
		y += 18
		var shot := unit.get_active_shot()
		if shot != null:
			draw_string(font, Vector2(10, y), "Shot: %s" % shot.display_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.85, 0.5))
			if shot.aoe_pattern != null:
				_draw_pattern_glyph(shot.aoe_pattern, Rect2(Vector2(size.x - 58, 6), Vector2(50, 50)))
			y += 14
			if shot.description != "":
				draw_multiline_string(font, Vector2(10, y), shot.description,
						HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11, 3, Color(1, 1, 1, 0.75))
				y += 38
		if unit.active_statuses.is_empty():
			draw_string(font, Vector2(10, y), "Status: none",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		else:
			var parts : Array = []
			for id in unit.active_statuses:
				var inst : StatusInstance = unit.active_statuses[id]
				parts.append("%s x%d" % [inst.definition.display_name, inst.stacks])
			draw_string(font, Vector2(10, y), "Status: " + ", ".join(parts),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.4))

	# Pattern-zone glyph (M7): small grid of the active shot's footprint, colored by
	# zone (orange = full strength, yellow = half) via the same palette the in-world
	# targeting preview uses (AoEPattern.zone_color), so both views read consistently.
	func _draw_pattern_glyph(pattern: AoEPattern, rect: Rect2) -> void:
		var aoe_map := pattern.to_map()
		if aoe_map.is_empty():
			return
		var min_c := 0
		var max_c := 0
		var min_r := 0
		var max_r := 0
		for offset in aoe_map:
			min_c = mini(min_c, offset.x)
			max_c = maxi(max_c, offset.x)
			min_r = mini(min_r, offset.y)
			max_r = maxi(max_r, offset.y)
		var span := maxi(max_c - min_c, max_r - min_r) + 1
		var cell := clampf(floorf(minf(rect.size.x, rect.size.y) / span), 3.0, 8.0)
		var origin := rect.position + rect.size * 0.5 - Vector2(cell, cell) * 0.5
		for offset in aoe_map:
			var group : AoEGroup = aoe_map[offset]
			var pos := origin + Vector2(offset.x, offset.y) * cell
			draw_rect(Rect2(pos, Vector2(cell, cell)), AoEPattern.zone_color(group.multiplier))
		draw_rect(Rect2(origin, Vector2(cell, cell)), Color(1, 1, 1, 0.9), false, 1.0)
