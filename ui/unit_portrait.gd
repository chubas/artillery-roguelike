# Squad portrait card for the map screen (M27). Card-frame placeholder using UnitDefinition.color.
class_name UnitPortrait
extends Control

signal clicked

const W := 56.0
const H := 72.0

var unit_state : RunUnitState
var definition : UnitDefinition

var _hovered : bool = false

func setup(rus: RunUnitState) -> void:
	unit_state = rus
	definition = load(rus.definition_id) as UnitDefinition
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_tooltip()
	queue_redraw()

func refresh_state() -> void:
	if unit_state == null:
		return
	_update_tooltip()
	queue_redraw()

func _update_tooltip() -> void:
	var hp := 0 if unit_state.is_disabled else unit_state.current_hp
	tooltip_text = "%s\nHP: %d / %d" % [unit_state.display_name, hp, unit_state.max_hp]

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
		clicked.emit()
		accept_event()

func _draw() -> void:
	if definition == null or unit_state == null:
		return
	var card := Rect2(Vector2.ZERO, Vector2(W, H))
	draw_rect(card, Color(0.1, 0.11, 0.16, 0.95))
	var body := card.grow(-3.0)
	var col := definition.color
	if unit_state.is_disabled:
		col = col.lerp(Color(0.35, 0.08, 0.08), 0.5)
	elif _hovered:
		col = col.lightened(0.12)
	draw_rect(body, col)
	draw_rect(body, col.darkened(0.35), false, 1.0)
	if unit_state.is_disabled:
		draw_rect(body, Color(0.9, 0.25, 0.2, 0.85), false, 2.0)
	elif _hovered:
		draw_rect(body.grow(-1.0), Color(0.95, 0.95, 1.0, 0.7), false, 1.5)
	var bar_y := H - 10.0
	var bar_w := W - 8.0
	draw_rect(Rect2(4.0, bar_y, bar_w, 5.0), Color(0, 0, 0, 0.65))
	var hp := 0 if unit_state.is_disabled else unit_state.current_hp
	var frac := float(hp) / maxf(1.0, float(unit_state.max_hp))
	var bar_col := Color(0.25, 0.85, 0.3)
	if frac < 0.25:
		bar_col = Color(0.9, 0.2, 0.15)
	elif frac <= 0.5:
		bar_col = Color(0.95, 0.6, 0.15)
	draw_rect(Rect2(5.0, bar_y + 1.0, maxf(0.0, (bar_w - 2.0) * frac), 3.0), bar_col)
