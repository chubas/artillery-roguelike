# Screen-space HUD (M2 spec §10): angle/power readouts, action pips, unit info,
# turn indicator, End Turn + Undo buttons. Placeholder quality by design.
class_name HUD
extends CanvasLayer

signal end_turn_pressed
signal undo_pressed
signal shot_selected(index: int)

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

func _ready() -> void:
	_build_top_left()
	_build_top_center()
	_build_top_right()

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
	_action_pips.custom_minimum_size = Vector2(5 * 24, 20)
	box.add_child(_action_pips)
	_shot_box = HBoxContainer.new()
	_shot_box.add_theme_constant_override("separation", 4)
	box.add_child(_shot_box)
	var hint := _make_label(11)
	hint.text = "↑/↓ angle · ←/→ move · Space charge/fire · 1/2/3 shot · Tab select · WASD pan"
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

func set_power(frac: float, charging: bool) -> void:
	if _power_bar.frac != frac or _power_bar.charging != charging:
		_power_bar.frac = frac
		_power_bar.charging = charging
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

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		if charging and frac > 0.0:
			var fill := Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2))
			draw_rect(fill, Color(0.2, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.15), frac))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)


class ActionPips:
	extends Control

	var current := 5
	var maximum := 5

	func _draw() -> void:
		for i in range(maximum):
			var rect := Rect2(i * 24, 0, 20, 20)
			if i < current:
				draw_rect(rect, Color(0.95, 0.85, 0.3))
			else:
				draw_rect(rect, Color(0, 0, 0, 0.45))
			draw_rect(rect, Color(1, 1, 1, 0.5), false, 1.0)
