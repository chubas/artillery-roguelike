# Screen-space HUD (M2 spec §10): angle/power readouts, action pips, unit info,
# turn indicator, End Turn + Undo buttons. Placeholder quality by design.
class_name HUD
extends CanvasLayer

signal end_turn_pressed
signal undo_pressed
signal card_selected(index: int)
signal start_battle_pressed   # M15: confirm pre-combat placement

var _angle_label : Label
var _power_label : Label
var _power_bar : PowerBar
var _action_pips : ActionPips
var _unit_info_label : Label
var _turn_label : Label
var _end_turn_btn : Button
var _undo_btn : Button
var _card_box : HBoxContainer
var _card_chips : Array = []
var _card_sig : String = ""   # cache: rebuild chips only when the card list changes
var _deck_btn : Button        # M11/M37: draw-pile/discard counts; clickable → DeckViewer
var _inspector     : UnitInspector
var _dep_inspector : DeployableInspector   # M28
var _wind_indicator : WindIndicator
var _currency_label : Label   # M42: in-combat "◆ Shards" readout
var _artifact_bar : HBoxContainer
var _placement_box : VBoxContainer   # M15: instruction + Start Battle, shown only in placement
var _placement_hint : Label          # updated each frame with the current queue-front unit name
var _start_battle_btn : Button       # disabled while the queue is non-empty

func _ready() -> void:
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_bottom_right()
	_build_placement()

func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	# M42: currency counter at the top of the bar, mirroring the world-map "◆ Shards" readout.
	_currency_label = _make_label(14)
	_currency_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	box.add_child(_currency_label)
	refresh_currency()
	EventBus.ore_collected.connect(func(_v): refresh_currency())
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
	_card_box = HBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 4)
	box.add_child(_card_box)
	_deck_btn = Button.new()
	_deck_btn.focus_mode = Control.FOCUS_NONE
	_deck_btn.add_theme_font_size_override("font_size", 12)
	_deck_btn.modulate = Color(1, 1, 1, 0.8)
	_deck_btn.pressed.connect(_on_deck_viewer_pressed)
	box.add_child(_deck_btn)
	var hint := _make_label(11)
	hint.text = "↑/↓ angle · ←/→ move · Space charge/fire · Q/E card · Esc cancel · Tab select · WASD pan"
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
	# Artifact bar floats independently so its width is never constrained by the button column.
	# It spans a generous range leftward from the right edge; ALIGNMENT_END keeps icons flush right.
	_artifact_bar = HBoxContainer.new()
	_artifact_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_artifact_bar.offset_left  = -500
	_artifact_bar.offset_right = -12
	_artifact_bar.offset_top   = 10
	_artifact_bar.offset_bottom = 10 + ArtifactIcon.SIZE
	_artifact_bar.alignment = BoxContainer.ALIGNMENT_END
	_artifact_bar.add_theme_constant_override("separation", 4)
	_artifact_bar.mouse_filter = Control.MOUSE_FILTER_PASS   # don't block clicks on the game below
	add_child(_artifact_bar)

	# Button column sits below the artifact bar with matching right edge.
	const ICON_ROW_H := ArtifactIcon.SIZE + 10   # icon height + gap
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left  = -150
	box.offset_right = -12
	box.offset_top   = 10 + ICON_ROW_H
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
	# M37: Squad viewer button
	var squad_btn := Button.new()
	squad_btn.text = "Squad"
	squad_btn.focus_mode = Control.FOCUS_NONE
	squad_btn.add_theme_font_size_override("font_size", 13)
	squad_btn.pressed.connect(_on_squad_viewer_pressed)
	box.add_child(squad_btn)
	# Wind indicator lives in the same column, below the buttons.
	_wind_indicator = WindIndicator.new()
	_wind_indicator.custom_minimum_size = Vector2(0, 34)
	box.add_child(_wind_indicator)

func refresh_currency() -> void:
	if _currency_label != null:
		_currency_label.text = "◆ Shards: %d" % (Run.active.currency if Run.active != null else 0)

# Unit Inspector (M5 polish): bottom-right panel showing whichever unit (ally or enemy)
# is currently inspected — name, HP/shield, active shot + description, status effects.
func _build_bottom_right() -> void:
	_inspector = UnitInspector.new()
	_inspector.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inspector.offset_left = -240
	_inspector.offset_right = -12
	_inspector.offset_top = -195
	_inspector.offset_bottom = -12
	_inspector.visible = false
	add_child(_inspector)
	_dep_inspector = DeployableInspector.new()
	_dep_inspector.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dep_inspector.offset_left   = -240
	_dep_inspector.offset_right  = -12
	_dep_inspector.offset_top    = -195
	_dep_inspector.offset_bottom = -12
	_dep_inspector.visible = false
	add_child(_dep_inspector)

func set_inspected_unit(unit: Unit) -> void:
	_inspector.unit = unit
	_inspector.visible = unit != null and is_instance_valid(unit)
	_inspector.queue_redraw()
	if _inspector.visible:
		_dep_inspector.visible = false

func set_inspected_deployable(d: Deployable) -> void:
	_dep_inspector.deployable = d
	var show := d != null and is_instance_valid(d)
	_dep_inspector.visible = show
	_dep_inspector.queue_redraw()
	if show:
		_inspector.visible = false

# Placement controls (M15): a bottom-center instruction + Start Battle button, shown only while
# deploying the squad (set_placement_mode), hidden during the fight.
func _build_placement() -> void:
	_placement_box = VBoxContainer.new()
	_placement_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_placement_box.offset_left = -200
	_placement_box.offset_right = 200
	_placement_box.offset_top = -78
	_placement_box.offset_bottom = -12
	_placement_box.alignment = BoxContainer.ALIGNMENT_END
	_placement_box.add_theme_constant_override("separation", 6)
	_placement_box.visible = false
	_placement_hint = _make_label(13)
	_placement_hint.text = "Hover over the zone and click to deploy · Tab to cycle unit · Enter when done"
	_placement_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_hint.modulate = Color(1, 1, 1, 0.8)
	_placement_box.add_child(_placement_hint)
	_start_battle_btn = Button.new()
	_start_battle_btn.text = "Start Battle"
	_start_battle_btn.focus_mode = Control.FOCUS_NONE
	_start_battle_btn.disabled = true   # enabled once all units are dropped
	_start_battle_btn.pressed.connect(func(): start_battle_pressed.emit())
	_placement_box.add_child(_start_battle_btn)
	add_child(_placement_box)

func set_placement_mode(active: bool) -> void:
	if _placement_box.visible != active:
		_placement_box.visible = active

# Updates the drop-queue instruction and enables/disables Start Battle based on remaining count.
func set_placement_unit(unit_name: String, remaining: int) -> void:
	var txt : String
	if remaining > 0:
		txt = "Click to deploy: %s  (%d left) · Tab to cycle" % [unit_name, remaining]
	else:
		txt = "All units deployed — press Start Battle or Enter"
	_set_text(_placement_hint, txt)
	var should_disable := remaining > 0
	if _start_battle_btn.disabled != should_disable:
		_start_battle_btn.disabled = should_disable

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

# Card chips (M5). Little card-faces (description + AP cost) instead of text buttons.
# Same rebuild-only-on-identity-change pattern as set_shots(); greys out unaffordable
# cards and draws a green outline on the currently selected (pending) card.
# `pending_index` is the selected hand SLOT (-1 = none). Index-based, not card-based: duplicate
# cards in hand share one cached CardDefinition, so comparing by object would highlight every copy.
func set_cards(cards: Array, pending_index: int, actions_left: int,
		deck_count: int = 0, discard_count: int = 0) -> void:
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
		chip.set_state(actions_left >= c.action_cost, i == pending_index)
	_deck_btn.text = "Deck %d  ·  Discard %d" % [deck_count, discard_count]

func set_artifacts(artifacts: Array) -> void:
	for c in _artifact_bar.get_children():
		c.queue_free()
	for i in range(artifacts.size()):
		var icon := ArtifactIcon.new()
		icon.artifact = artifacts[i]
		icon.index = i
		_artifact_bar.add_child(icon)

func set_turn_text(text: String) -> void:
	_set_text(_turn_label, text)

func set_end_turn_alert(alert: bool) -> void:
	var m := Color(1.0, 0.35, 0.3) if alert else Color.WHITE
	if _end_turn_btn.modulate != m:
		_end_turn_btn.modulate = m

func set_undo_enabled(enabled: bool) -> void:
	if _undo_btn.disabled == enabled:
		_undo_btn.disabled = not enabled

func _on_deck_viewer_pressed() -> void:
	if not Features.deck_viewer_enabled:
		return
	var v := DeckViewer.new()
	add_child(v)
	v.setup()
	v.closed.connect(func() -> void: v.queue_free())

func _on_squad_viewer_pressed() -> void:
	if not Features.squad_viewer_enabled:
		return
	var v := SquadViewer.new()
	add_child(v)
	v.setup(false)  # combat — no retire
	v.closed.connect(func() -> void: v.queue_free())

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
		# 20px stride; 16px pip width. Scales with MAX_ACTIONS — currently 5 pips.
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

	func _ready() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = card.display_name
		var kw := KeywordRegistry.tooltip(KeywordRegistry.for_card(card))
		if kw != "":
			tooltip_text += "\n\n" + kw

	func set_state(affordable: bool, selected: bool) -> void:
		if affordable == _affordable and selected == _selected:
			return
		_affordable = affordable
		_selected = selected
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(W, H))
		var face := card.color
		var text_col := Color.WHITE
		if not _affordable:
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
		if _selected:
			draw_rect(r, Color(0.3, 0.95, 0.4), false, 3.0)


# Unit Inspector panel (M5 polish): text-only readout of whichever unit is currently
# inspected (ally via selection, enemy via click). Drawn rather than Label-based to
# match the rest of this file's placeholder-quality custom-draw widgets.
class UnitInspector:
	extends Control

	var unit : Unit = null

	# Live keyword tooltip (M41): recomputed each hover so effects applied mid-combat (e.g. Boosted
	# from a card) appear immediately without re-inspecting.
	func _get_tooltip(_at_position: Vector2) -> String:
		if unit == null or not is_instance_valid(unit):
			return ""
		var kw := KeywordRegistry.tooltip(KeywordRegistry.for_unit(unit))
		# M45: enemy targeting telegraph — show who this enemy will shoot this round.
		var tgt := unit.targeting_summary() if not unit.is_player else ""
		var body := ""
		if tgt != "":
			body = "Targeting: %s" % tgt
		if kw != "":
			body = "%s\n\n%s" % [body, kw] if body != "" else kw
		return "%s\n\n%s" % [unit.display_name, body] if body != "" else ""

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
		var eff_atk := PowerCalculator.effective_attack(unit)
		draw_string(font, Vector2(10, y), "★ %d" % eff_atk,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.65, 0.25))
		y += 16
		# Breakdown sub-lines: each active mod (base row skipped — it's the ★ total's seed).
		var rows := PowerCalculator.breakdown(unit)
		for i in range(1, rows.size()):
			var row : Dictionary = rows[i]
			var sym := "×" if int(row["op"]) == PowerMod.Op.MULT else ("+" if row["value"] >= 0 else "")
			var val_txt : String = ("%.2g" % row["value"]) if int(row["op"]) == PowerMod.Op.MULT \
					else ("%d" % int(row["value"]))
			draw_string(font, Vector2(20, y), "%s%s %s" % [sym, val_txt, row["label"]],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.6, 0.4))
			y += 13
		var shield_txt := "Shield: %d" % unit.shield if unit.shield > 0 else "Shield: —"
		draw_string(font, Vector2(10, y), shield_txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.85, 1.0))
		y += 16
		var armor_txt := "Armor: %d" % unit.armor if unit.armor > 0 else "Armor: —"
		draw_string(font, Vector2(10, y), armor_txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.82, 0.25))
		y += 18
		var shot := unit.get_active_shot()
		if shot != null:
			draw_string(font, Vector2(10, y), "Shot: %s" % shot.display_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.85, 0.5))
			if shot.aoe_pattern != null:
				_draw_pattern_glyph(shot.aoe_pattern, Rect2(Vector2(size.x - 58, 6), Vector2(50, 50)))
			y += 14
			var shot_desc := shot.resolve_description(unit)
			if shot_desc != "":
				draw_multiline_string(font, Vector2(10, y), shot_desc,
						HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11, 3, Color(1, 1, 1, 0.75))
				y += 38
		if unit.active_statuses.is_empty():
			draw_string(font, Vector2(10, y), "Effects: none",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		else:
			var parts : Array = []
			for id in unit.active_statuses:
				var inst : StatusInstance = unit.active_statuses[id]
				parts.append("%s x%d" % [inst.definition.display_name, inst.stacks])
			draw_string(font, Vector2(10, y), "Effects: " + ", ".join(parts),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.4))
		y += 18
		# M45: enemy targeting telegraph line.
		if not unit.is_player:
			var tgt_sum := unit.targeting_summary()
			var tgt_txt := "Targeting: %s" % tgt_sum if tgt_sum != "" else "Targeting: —"
			draw_string(font, Vector2(10, y), tgt_txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.35))
			y += 16
		if not unit.primed_elements.is_empty():
			var font_size := 11
			var line_h := 14.0
			for el in unit.primed_elements:
				var col := Color(1.0, 0.45, 0.1) if el.id == "fire" else Color(0.3, 0.85, 0.95)
				draw_string(font, Vector2(10, y), "PRIMED: " + el.display_name.to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
				y += line_h
		var used_slots := 0
		for e in unit.essences:
			used_slots += (e as EssenceDef).slot_cost
		var total_slots := unit.run_state.upgrade_slots if unit.run_state != null else 2
		var slot_col := Color(0.75, 0.5, 1.0)
		draw_string(font, Vector2(10, y), "[%d/%d] Slots" % [used_slots, total_slots],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, slot_col)
		y += 14
		for e in unit.essences:
			draw_string(font, Vector2(10, y), "  " + (e as EssenceDef).essence_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, slot_col)
			y += 13

	# Pattern-zone glyph (M7): small grid of the active shot's footprint, colored by
	# zone (orange = full strength, yellow = half) via the same palette the in-world
	# targeting preview uses (AoEPattern.zone_color), so both views read consistently.
	func _draw_pattern_glyph(pattern: AoEPattern, rect: Rect2) -> void:
		PatternGlyph.draw(self, pattern, rect)

# Wind Indicator (M8): compact readout in the top-right column, below the action buttons.
# Hidden when wind_strength ≈ 0. Color: 0–20% white, 20–50% orange, >50% red.
class WindIndicator:
	extends Control

	var strength : float = 0.0   # -1.0..1.0; 0 = calm (hidden)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		EventBus.wind_changed.connect(func(s: float) -> void:
			strength = s
			queue_redraw())

	func _draw() -> void:
		if is_zero_approx(strength):
			return
		var pct : float = abs(strength) * 100.0
		var col : Color
		if pct > 50.0:
			col = Color(1.0, 0.25, 0.2)   # red
		elif pct > 20.0:
			col = Color(1.0, 0.5,  0.1)   # orange
		else:
			col = Color(1.0, 1.0,  1.0)   # white
		var font := ThemeDB.fallback_font
		var arrow := "→" if strength > 0.0 else "←"
		draw_string(font, Vector2(0, 14), "Wind  %s  %.0f%%" % [arrow, pct],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		var bar_max : float = size.x
		var bar_w : float = bar_max * abs(strength)
		var bar_x : float = 0.0 if strength > 0.0 else size.x - bar_w
		draw_rect(Rect2(bar_x, 22, bar_w, 5), col * Color(1, 1, 1, 0.6))


# Artifact icon (M9): a small placeholder square for one squad artifact.
# Displays a generic number label and shows the artifact name + effect on hover via tooltip.
class ArtifactIcon:
	extends Control

	const SIZE := 32.0

	var artifact : ArtifactDef
	var index : int   # 0-based; tooltip shows "Artifact(index+1)"

	func _ready() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Artifact%d\n%s" % [index + 1, artifact.resolve_description()]
		var kw := KeywordRegistry.tooltip(KeywordRegistry.for_artifact(artifact))
		if kw != "":
			tooltip_text += "\n\n" + kw

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
		draw_rect(r, Color(0.1, 0.12, 0.2, 0.88))
		draw_rect(r, Color(0.65, 0.65, 0.75, 0.7), false, 1.5)
		var font := ThemeDB.fallback_font
		# Placeholder glyph: a small star/diamond shape in muted gold.
		var cx : float = SIZE * 0.5
		var cy : float = SIZE * 0.5
		var pts := PackedVector2Array([
			Vector2(cx, cy - 9), Vector2(cx + 3, cy - 3),
			Vector2(cx + 9, cy), Vector2(cx + 3, cy + 3),
			Vector2(cx, cy + 9), Vector2(cx - 3, cy + 3),
			Vector2(cx - 9, cy), Vector2(cx - 3, cy - 3),
		])
		draw_colored_polygon(pts, Color(0.75, 0.65, 0.3, 0.85))
		# Index number, bottom-right corner.
		draw_string(font, Vector2(SIZE - 11, SIZE - 3), str(index + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))


# Deployable Inspector (M28): bottom-right panel for a selected deployable.
# Type-specific stats via `is ShieldGenerator` / `is Mine` checks.
# Mutually exclusive with UnitInspector — set_inspected_deployable() hides the other.
class DeployableInspector:
	extends Control

	var deployable : Deployable = null

	func _draw() -> void:
		if deployable == null or not is_instance_valid(deployable):
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.06, 0.07, 0.1, 0.85))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
		var font := ThemeDB.fallback_font
		var y := 18.0
		draw_string(font, Vector2(10, y), deployable.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(deployable.color.r, deployable.color.g, deployable.color.b))
		y += 20
		draw_string(font, Vector2(10, y), "HP: %d / %d" % [deployable.hp, deployable.max_hp],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		y += 18
		if deployable is ShieldGenerator:
			var sg := deployable as ShieldGenerator
			draw_string(font, Vector2(10, y), "Shield / turn: %d" % sg.shield_amount,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.85, 1.0))
			y += 16
			draw_string(font, Vector2(10, y), "Radius: %d voxels" % sg.aura_radius,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
		elif deployable is Mine:
			var m := deployable as Mine
			draw_string(font, Vector2(10, y), "Damage: %d" % m.strength,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.5, 0.4))
			y += 16
			draw_string(font, Vector2(10, y), "Terrain dmg: %d" % m.dig,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.4))
