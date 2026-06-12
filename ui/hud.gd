# Screen-space HUD: angle readout, charge power bar, controls hint.
# Separate CanvasLayer from TargetingUI because that one follows the viewport.
class_name HUD
extends CanvasLayer

var _angle_label : Label
var _power_label : Label
var _power_bar : PowerBar

func _ready() -> void:
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

	var hint := _make_label(11)
	hint.text = "↑/↓ angle · hold Space to charge, release to fire · WASD pan · wheel zoom"
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func set_angle(deg: float) -> void:
	_angle_label.text = "Angle: %d°" % roundi(deg)

func set_power(frac: float, charging: bool) -> void:
	_power_bar.frac = frac
	_power_bar.charging = charging
	_power_bar.queue_redraw()
	_power_label.text = "Power: %d%%" % roundi(frac * 100.0) if charging else "Power: —"


class PowerBar:
	extends Control

	var frac := 0.0
	var charging := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		if charging and frac > 0.0:
			var fill := Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2))
			# Green → orange → red as the charge fills.
			draw_rect(fill, Color(0.2, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.15), frac))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)
