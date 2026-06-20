# Debug sandbox overlay (M24). Toggled with backtick (`). Sits on top of combat_scene as a
# CanvasLayer; all actions route through CombatManager's public debug_* API — no direct
# internal access. Gated by Features.sandbox_enabled so it adds zero cost when disabled.
extends CanvasLayer

const PANEL_W := 210
const BTN_H   := 22

var _combat  : CombatManager  = null
var _terrain : TerrainManager = null
var _camera  : Camera2D       = null

# Selection state
var _selected_unit_def     : UnitDefinition = null
var _selected_card_def     : CardDefinition = null
var _selected_artifact_def : ArtifactDef    = null
var _pending_spawn         : bool = false
var _pending_is_player     : bool = true

# Labels updated at runtime
var _spawn_status_lbl : Label = null
var _card_status_lbl  : Label = null
var _art_status_lbl   : Label = null
var _invuln_btn       : Button = null
var _passive_btn      : Button = null

func setup(combat: CombatManager, terrain: TerrainManager, camera: Camera2D) -> void:
	_combat  = combat
	_terrain = terrain
	_camera  = camera
	layer    = 10
	_build_panel()
	visible  = false

# ── Toggle ──────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_QUOTELEFT:
		visible = not visible
		if not visible:
			_pending_spawn = false

# ── Spawn click (world coordinates from a CanvasLayer) ──────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _pending_spawn:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos : Vector2 = get_viewport().canvas_transform.affine_inverse() \
				* event.position
		var vox := Const.world_to_voxel(world_pos)
		var name := _selected_unit_def.display_name if _selected_unit_def != null else "Debug Unit"
		_combat.debug_spawn(_selected_unit_def, vox.x, name, _pending_is_player)
		_pending_spawn = false
		_spawn_status_lbl.text = "Placed %s. Select another." % name
		get_viewport().set_input_as_handled()

# ── Panel construction ───────────────────────────────────────────────────────

func _build_panel() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12, 0.93)
	bg.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	bg.offset_left = -PANEL_W
	bg.offset_right = 0
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_left = -PANEL_W
	scroll.offset_right = 0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = PANEL_W
	scroll.add_child(col)

	_add_header(col, "═══ SANDBOX ═══")

	# ── Spawn ──
	_add_section(col, "SPAWN")
	var spawn_row := HBoxContainer.new()
	col.add_child(spawn_row)
	var as_player_btn := _make_btn("As Player")
	as_player_btn.pressed.connect(func() -> void:
		if _selected_unit_def == null: return
		_pending_is_player = true
		_pending_spawn = true
		_spawn_status_lbl.text = "Click terrain to place (player)")
	spawn_row.add_child(as_player_btn)
	var as_enemy_btn := _make_btn("As Enemy")
	as_enemy_btn.pressed.connect(func() -> void:
		if _selected_unit_def == null: return
		_pending_is_player = false
		_pending_spawn = true
		_spawn_status_lbl.text = "Click terrain to place (enemy)")
	spawn_row.add_child(as_enemy_btn)
	_spawn_status_lbl = _make_label("Select a unit below.")
	col.add_child(_spawn_status_lbl)
	for def in _load_unit_defs():
		var d : UnitDefinition = def
		var b := _make_btn(d.display_name)
		b.pressed.connect(func() -> void:
			_selected_unit_def = d
			_spawn_status_lbl.text = "Ready: %s" % d.display_name)
		col.add_child(b)

	# ── Cards ──
	_add_section(col, "CARDS")
	var card_row := HBoxContainer.new()
	col.add_child(card_row)
	var to_hand_btn := _make_btn("→ Hand")
	to_hand_btn.pressed.connect(func() -> void:
		if _selected_card_def == null: return
		_combat.debug_inject_card_to_hand(_selected_card_def)
		_card_status_lbl.text = "Added to hand.")
	card_row.add_child(to_hand_btn)
	var to_deck_btn := _make_btn("→ Deck")
	to_deck_btn.pressed.connect(func() -> void:
		if _selected_card_def == null: return
		_combat.debug_inject_card_to_deck(_selected_card_def)
		_card_status_lbl.text = "Added to deck.")
	card_row.add_child(to_deck_btn)
	_card_status_lbl = _make_label("Select a card below.")
	col.add_child(_card_status_lbl)
	for def in _load_card_defs():
		var d : CardDefinition = def
		var b := _make_btn(d.display_name)
		b.pressed.connect(func() -> void:
			_selected_card_def = d
			_card_status_lbl.text = "Ready: %s" % d.display_name)
		col.add_child(b)

	# ── Artifacts ──
	_add_section(col, "ARTIFACTS")
	var act_btn := _make_btn("Activate")
	act_btn.pressed.connect(func() -> void:
		if _selected_artifact_def == null: return
		_combat.debug_inject_artifact(_selected_artifact_def)
		_art_status_lbl.text = "Activated.")
	col.add_child(act_btn)
	_art_status_lbl = _make_label("Select an artifact below.")
	col.add_child(_art_status_lbl)
	for def in _load_artifact_defs():
		var d : ArtifactDef = def
		var b := _make_btn(d.artifact_name)
		b.pressed.connect(func() -> void:
			_selected_artifact_def = d
			_art_status_lbl.text = "Ready: %s" % d.artifact_name)
		col.add_child(b)

	# ── Cheats ──
	_add_section(col, "CHEATS")
	var refill_btn := _make_btn("Refill AP")
	refill_btn.pressed.connect(func() -> void: _combat.debug_refill_ap())
	col.add_child(refill_btn)
	var end_turn_btn := _make_btn("End Player Turn")
	end_turn_btn.pressed.connect(func() -> void: _combat.end_player_turn())
	col.add_child(end_turn_btn)
	var wave_btn := _make_btn("Force Wave")
	wave_btn.pressed.connect(func() -> void: _combat.debug_force_next_wave())
	col.add_child(wave_btn)

	# ── Isolation ──
	_add_section(col, "ISOLATION")
	_invuln_btn = _make_btn("Player Invulnerable: OFF")
	_invuln_btn.pressed.connect(_toggle_invulnerable)
	col.add_child(_invuln_btn)
	_passive_btn = _make_btn("Enemies Passive: OFF")
	_passive_btn.pressed.connect(_toggle_enemy_passive)
	col.add_child(_passive_btn)

# ── Isolation toggles ────────────────────────────────────────────────────────

func _toggle_invulnerable() -> void:
	var on := false
	if _combat.player_units.size() > 0:
		on = not (_combat.player_units[0] as Unit).debug_invulnerable
	for u in _combat.player_units:
		(u as Unit).debug_invulnerable = on
	_invuln_btn.text = "Player Invulnerable: %s" % ("ON" if on else "OFF")
	_invuln_btn.modulate = Color(0.6, 1.0, 0.6) if on else Color.WHITE

func _toggle_enemy_passive() -> void:
	_combat.debug_enemies_passive = not _combat.debug_enemies_passive
	var on := _combat.debug_enemies_passive
	_passive_btn.text = "Enemies Passive: %s" % ("ON" if on else "OFF")
	_passive_btn.modulate = Color(0.6, 1.0, 0.6) if on else Color.WHITE

# ── Resource loaders ─────────────────────────────────────────────────────────

func _load_unit_defs() -> Array[UnitDefinition]:
	var out : Array[UnitDefinition] = []
	var dir := DirAccess.open("res://data/units/")
	if dir == null: return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res := load("res://data/units/" + f)
			if res is UnitDefinition:
				out.append(res as UnitDefinition)
		f = dir.get_next()
	out.sort_custom(func(a, b): return a.display_name < b.display_name)
	return out

func _load_card_defs() -> Array[CardDefinition]:
	var out : Array[CardDefinition] = []
	var dir := DirAccess.open("res://data/cards/")
	if dir == null: return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res := load("res://data/cards/" + f)
			if res is CardDefinition:
				out.append(res as CardDefinition)
		f = dir.get_next()
	out.sort_custom(func(a, b): return a.display_name < b.display_name)
	return out

func _load_artifact_defs() -> Array[ArtifactDef]:
	var out : Array[ArtifactDef] = []
	var dir := DirAccess.open("res://data/artifacts/resources/")
	if dir == null: return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res := load("res://data/artifacts/resources/" + f)
			if res is ArtifactDef:
				out.append(res as ArtifactDef)
		f = dir.get_next()
	out.sort_custom(func(a, b): return a.artifact_name < b.artifact_name)
	return out

# ── UI helpers ───────────────────────────────────────────────────────────────

func _add_header(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	parent.add_child(lbl)

func _add_section(parent: Control, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = "─ %s ─" % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	parent.add_child(lbl)

func _make_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = BTN_H
	b.add_theme_font_size_override("font_size", 11)
	return b

func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
