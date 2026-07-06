# Debug sandbox overlay (M24/M25). Toggled with backtick (`). Sits on top of combat_scene as a
# CanvasLayer; all actions route through CombatManager's public debug_* API — no direct
# internal access. Gated by Features.sandbox_enabled so it adds zero cost when disabled.
extends CanvasLayer

const PANEL_W := 210
const BTN_H   := 22

var _combat   : CombatManager   = null
var _terrain  : TerrainManager  = null
var _renderer : TerrainRenderer = null
var _camera   : Camera2D        = null
var _hud      : Node            = null

# Selection state
var _selected_unit_def     : UnitDefinition = null
var _selected_card_def     : CardDefinition = null
var _selected_artifact_def : ArtifactDef    = null
var _selected_status_def   : StatusEffectDef = null
var _pending_spawn         : bool = false
var _pending_is_player     : bool = true
var _last_spawned          : Unit = null

# Spawn override controls
var _hp_pct_spin   : SpinBox = null
var _shield_spin   : SpinBox = null
var _armor_spin    : SpinBox = null

# Status injection controls
var _status_option : OptionButton = null
var _stacks_spin   : SpinBox = null
var _status_defs   : Array[StatusEffectDef] = []

# Terrain controls
var _seed_field        : LineEdit     = null
var _tv_profile_option : OptionButton = null
var _tv_minimap        : Control      = null
var _tv_profiles       : Array        = []
var _tv_preview_data   : MapData      = null
var _tv_anchors_check  : CheckBox     = null
var _tv_valid_lbl      : Label        = null
var _tv_map_option     : OptionButton = null   # M44: custom map files

# Rounds cheat control
var _rounds_spin   : SpinBox = null

# Labels updated at runtime
var _spawn_status_lbl : Label = null
var _card_status_lbl  : Label = null
var _art_status_lbl   : Label = null
var _invuln_btn       : Button = null
var _passive_btn      : Button = null

func setup(combat: CombatManager, terrain: TerrainManager, renderer: TerrainRenderer, camera: Camera2D, hud: Node = null) -> void:
	_combat   = combat
	_terrain  = terrain
	_renderer = renderer
	_camera   = camera
	_hud      = hud
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

# ── Input: spawn click + inspector click ─────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var world_pos : Vector2 = get_viewport().canvas_transform.affine_inverse() * event.position
	var vox := Const.world_to_voxel(world_pos)

	if _pending_spawn:
		var name := _selected_unit_def.display_name if _selected_unit_def != null else "Debug Unit"
		var u : Unit = _combat.debug_spawn(_selected_unit_def, vox.x, name, _pending_is_player)
		_last_spawned = u
		# Apply spawn overrides
		u.hp     = max(1, int(u.definition.max_hp * _hp_pct_spin.value / 100.0))
		u.shield = int(_shield_spin.value)
		u.armor  = int(_armor_spin.value)
		u.queue_redraw()
		_pending_spawn = false
		_spawn_status_lbl.text = "Placed %s. Select another." % name
		get_viewport().set_input_as_handled()
		return

	# Inspector click: find unit at vox, show in HUD inspector
	if _hud != null:
		var all := _combat.player_units + _combat.enemy_units
		for u in all:
			if (u as Unit).contains_voxel(vox):
				_hud.call("set_inspected_unit", u)
				get_viewport().set_input_as_handled()
				return

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

	# Spawn overrides
	col.add_child(_make_label("HP%  Shield  Armor"))
	var override_row := HBoxContainer.new()
	col.add_child(override_row)
	_hp_pct_spin = _make_spinbox(1.0, 100.0, 100.0)
	_shield_spin = _make_spinbox(0.0, 99.0, 0.0)
	_armor_spin  = _make_spinbox(0.0, 99.0, 0.0)
	override_row.add_child(_hp_pct_spin)
	override_row.add_child(_shield_spin)
	override_row.add_child(_armor_spin)

	# Status injection
	col.add_child(_make_label("Apply status to last spawn:"))
	_status_defs = _load_status_defs()
	_status_option = OptionButton.new()
	_status_option.focus_mode = Control.FOCUS_NONE
	_status_option.add_theme_font_size_override("font_size", 10)
	for sd in _status_defs:
		_status_option.add_item(sd.display_name)
	col.add_child(_status_option)
	var status_row := HBoxContainer.new()
	col.add_child(status_row)
	_stacks_spin = _make_spinbox(1.0, 10.0, 1.0)
	status_row.add_child(_stacks_spin)
	var apply_status_btn := _make_btn("Apply")
	apply_status_btn.pressed.connect(_apply_status_to_last_spawn)
	status_row.add_child(apply_status_btn)

	col.add_child(HSeparator.new())

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

	# ── Terrain ──
	_add_section(col, "TERRAIN")
	# M44: hand-authored map files (res://data/maps + user://maps)
	col.add_child(_make_label("Map:"))
	_tv_map_option = OptionButton.new()
	_tv_map_option.add_theme_font_size_override("font_size", 10)
	_tv_map_option.focus_mode = Control.FOCUS_NONE
	_tv_map_option.add_item("(none)")
	MapLibrary.reload()
	for map_id in MapLibrary.map_ids():
		_tv_map_option.add_item(map_id)
	col.add_child(_tv_map_option)
	var load_map_btn := _make_btn("Load Map")
	load_map_btn.pressed.connect(_load_custom_map)
	col.add_child(load_map_btn)
	col.add_child(_make_label("Profile:"))
	_tv_profile_option = OptionButton.new()
	_tv_profile_option.add_theme_font_size_override("font_size", 10)
	_tv_profile_option.focus_mode = Control.FOCUS_NONE
	_tv_profile_option.add_item("(legacy noise)")
	var profile_dir := "res://data/terrain/profiles/"
	if DirAccess.dir_exists_absolute(profile_dir):
		for fname in DirAccess.get_files_at(profile_dir):
			if fname.ends_with(".tres"):
				var p := load(profile_dir + fname) as TerrainProfile
				if p != null:
					_tv_profiles.append(p)
					_tv_profile_option.add_item(fname.get_basename())
	col.add_child(_tv_profile_option)
	col.add_child(_make_label("Seed:"))
	_seed_field = LineEdit.new()
	_seed_field.text = "12345"
	_seed_field.add_theme_font_size_override("font_size", 11)
	col.add_child(_seed_field)
	var regen_btn := _make_btn("Regenerate")
	regen_btn.pressed.connect(_regenerate_terrain)
	col.add_child(regen_btn)
	_tv_anchors_check = CheckBox.new()
	_tv_anchors_check.text = "Anchors"
	_tv_anchors_check.button_pressed = true
	_tv_anchors_check.add_theme_font_size_override("font_size", 10)
	_tv_anchors_check.focus_mode = Control.FOCUS_NONE
	_tv_anchors_check.toggled.connect(func(_on: bool) -> void:
		if _tv_minimap != null:
			_tv_minimap.queue_redraw())
	col.add_child(_tv_anchors_check)
	_tv_valid_lbl = _make_label("gen: —")
	col.add_child(_tv_valid_lbl)
	var repos_btn := _make_btn("Reposition Units")
	repos_btn.pressed.connect(_reposition_units)
	col.add_child(repos_btn)
	_tv_minimap = _TerrainMinimap.new()
	_tv_minimap.custom_minimum_size = Vector2(PANEL_W - 10, 80)
	_tv_minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_tv_minimap as _TerrainMinimap).overlay = self
	col.add_child(_tv_minimap)

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
	var clear_btn := _make_btn("Clear Stage (Win)")
	clear_btn.pressed.connect(func() -> void: _combat.debug_force_clear())
	col.add_child(clear_btn)
	var rounds_row := HBoxContainer.new()
	col.add_child(rounds_row)
	_rounds_spin = _make_spinbox(1.0, 20.0, 1.0)
	rounds_row.add_child(_rounds_spin)
	var advance_btn := _make_btn("Advance Rounds")
	advance_btn.pressed.connect(func() -> void:
		for _i in int(_rounds_spin.value):
			_combat.debug_advance_round())
	rounds_row.add_child(advance_btn)
	var shards_row := HBoxContainer.new()
	col.add_child(shards_row)
	var shards_field := LineEdit.new()
	shards_field.text = "50"
	shards_field.custom_minimum_size.x = 52
	shards_field.focus_mode = Control.FOCUS_CLICK
	shards_row.add_child(shards_field)
	var give_btn := _make_btn("Give Shards")
	give_btn.pressed.connect(func() -> void:
		var amt := int(shards_field.text) if shards_field.text.is_valid_int() else 0
		if amt > 0 and Run.active != null:
			Run.active.add_currency(amt))
	shards_row.add_child(give_btn)

	# ── Repair (M36) ──
	_add_section(col, "REPAIR (M36)")
	var distribute_btn := _make_btn("Distribute Heal (4)")
	distribute_btn.pressed.connect(func() -> void:
		if Run.active == null: return
		var pool := 4
		for rus in Run.active.squad:
			var u : RunUnitState = rus
			if not u.is_disabled and u.current_hp < u.max_hp:
				u.current_hp = mini(u.current_hp + 1, u.max_hp)
				pool -= 1
				if pool <= 0: break)
	col.add_child(distribute_btn)
	var heal_first_btn := _make_btn("Heal First Unit (6)")
	heal_first_btn.pressed.connect(func() -> void:
		if Run.active == null or Run.active.squad.is_empty(): return
		var u : RunUnitState = Run.active.squad[0]
		u.current_hp = mini(u.current_hp + 6, u.max_hp))
	col.add_child(heal_first_btn)
	var add_vial_btn := _make_btn("Add Heal Vial to Deck")
	add_vial_btn.pressed.connect(func() -> void:
		if Run.active != null:
			Run.active.deck.append("res://data/cards/heal_vial.tres"))
	col.add_child(add_vial_btn)

	# ── Upgrade (M36) ──
	_add_section(col, "UPGRADE (M36)")
	col.add_child(_make_label("Unit index (0-based):"))
	var upg_spin := _make_spinbox(0.0, 9.0, 0.0)
	col.add_child(upg_spin)
	var atk_btn := _make_btn("+2 ATK")
	atk_btn.pressed.connect(func() -> void:
		if Run.active == null: return
		var idx := int(upg_spin.value)
		if idx < Run.active.squad.size():
			(Run.active.squad[idx] as RunUnitState).add_permanent_mod("upgrade:attack", PowerMod.Op.ADD, 2.0, "Upgrade"))
	col.add_child(atk_btn)
	var boost_btn := _make_btn("+3 Boosted")
	boost_btn.pressed.connect(func() -> void:
		if Run.active == null: return
		var idx := int(upg_spin.value)
		if idx < Run.active.squad.size():
			(Run.active.squad[idx] as RunUnitState).permanent_boosted += 3)
	col.add_child(boost_btn)
	var fp_btn := _make_btn("+Fire Prime")
	fp_btn.pressed.connect(func() -> void:
		if Run.active == null: return
		var idx := int(upg_spin.value)
		if idx < Run.active.squad.size():
			(Run.active.squad[idx] as RunUnitState).permanent_fire_prime += 1)
	col.add_child(fp_btn)
	var dig_btn := _make_btn("+1 Dig")
	dig_btn.pressed.connect(func() -> void:
		if Run.active == null: return
		var idx := int(upg_spin.value)
		if idx < Run.active.squad.size():
			(Run.active.squad[idx] as RunUnitState).bonus_dig += 1)
	col.add_child(dig_btn)
	var fuse_btn := _make_btn("Fuse 0 → 1")
	fuse_btn.pressed.connect(func() -> void:
		if Run.active != null and Run.active.squad.size() >= 2:
			SquadOps.fuse_units(Run.active, 0, 1))
	col.add_child(fuse_btn)

	# ── Isolation ──
	_add_section(col, "ISOLATION")
	_invuln_btn = _make_btn("Player Invulnerable: OFF")
	_invuln_btn.pressed.connect(_toggle_invulnerable)
	col.add_child(_invuln_btn)
	_passive_btn = _make_btn("Enemies Passive: OFF")
	_passive_btn.pressed.connect(_toggle_enemy_passive)
	col.add_child(_passive_btn)


class _TerrainMinimap extends Control:
	var overlay : Object = null   # sandbox_overlay reference

	func _draw() -> void:
		if overlay == null:
			return
		var data : MapData = overlay._tv_preview_data
		if data == null:
			return
		var cw := size.x / float(data.width)
		var ch := size.y / float(data.height)
		for row in range(data.height):
			for col in range(data.width):
				var cell = data.get_cell(col, row)
				if cell == null:
					continue
				draw_rect(
					Rect2(col * cw, row * ch, maxf(cw, 1.0), maxf(ch, 1.0)),
					_origin_color(cell.get("gen_origin", 0))
				)
		if overlay._tv_anchors_check != null and overlay._tv_anchors_check.button_pressed:
			_draw_anchors(data, cw, ch)

	# M43: FeatureInstance overlay — footprint outlines, exact anchors as dots + labels,
	# zone anchors as outlined rects.
	func _draw_anchors(data: MapData, cw: float, ch: float) -> void:
		var font := ThemeDB.fallback_font
		for inst in data.features:
			var f : Rect2i = inst.footprint
			draw_rect(Rect2(f.position.x * cw, f.position.y * ch,
					f.size.x * cw, f.size.y * ch), Color(1, 1, 1, 0.5), false, 1.0)
			for name in inst.anchors:
				var value = inst.anchors[name]
				if value is Rect2i:
					var z : Rect2i = value
					draw_rect(Rect2(z.position.x * cw, z.position.y * ch,
							z.size.x * cw, z.size.y * ch), Color(1.0, 0.6, 0.1, 0.9), false, 1.0)
				else:
					var v : Vector2i = value
					var p := Vector2((v.x + 0.5) * cw, (v.y + 0.5) * ch)
					draw_circle(p, 2.0, Color(1.0, 0.3, 0.3))
					draw_string(font, p + Vector2(3, 2), String(name),
							HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.85))

	func _origin_color(origin: int) -> Color:
		match origin:
			MapData.GenOrigin.SPAWN_PLATFORM: return Color(0.2,  0.7,  1.0)
			MapData.GenOrigin.SLOT_LEFT:      return Color(0.9,  0.4,  0.1)
			MapData.GenOrigin.SLOT_CENTER:    return Color(0.95, 0.85, 0.1)
			MapData.GenOrigin.SLOT_RIGHT:     return Color(0.3,  0.85, 0.2)
			MapData.GenOrigin.BACKGROUND:     return Color(0.55, 0.3,  0.85)
			MapData.GenOrigin.CRYSTAL:        return Color(0.2,  0.95, 0.95)
			MapData.GenOrigin.SEAM:           return Color(0.75, 0.55, 0.35)
			_:                                return Color(0.35, 0.35, 0.35)

# ── Terrain regeneration ─────────────────────────────────────────────────────

# M44: load a hand-authored map from the dropdown into the live terrain + minimap.
func _load_custom_map() -> void:
	if _tv_map_option == null or _tv_map_option.selected <= 0:
		return
	var map_id := _tv_map_option.get_item_text(_tv_map_option.selected)
	MapLibrary.reload()   # pick up freshly dropped files without reopening the panel
	var cmap := MapLibrary.get_map(map_id)
	if cmap == null or cmap.error != "":
		if _tv_valid_lbl != null:
			_tv_valid_lbl.text = "map: FAILED\n%s" % (cmap.error if cmap != null else "not found")
		return
	var data := cmap.to_map_data()
	_tv_preview_data = data
	_terrain.load_map(data)
	if _combat != null:
		_combat.set_custom_map(cmap)
	if _tv_valid_lbl != null:
		_tv_valid_lbl.text = "map: %s (%dx%d)" % [cmap.id, cmap.width, cmap.height]
	_renderer.mark_all_dirty()
	if _tv_minimap != null:
		_tv_minimap.queue_redraw()
	_snap_all_entities()

func _regenerate_terrain() -> void:
	var seed_val := int(_seed_field.text) if _seed_field.text.is_valid_int() else 12345
	# Index 0 = "(legacy noise)"; indices 1+ map to _tv_profiles[idx - 1]
	var profile_idx := _tv_profile_option.selected - 1 if _tv_profile_option != null else -1
	if profile_idx >= 0 and profile_idx < _tv_profiles.size():
		var profile : TerrainProfile = _tv_profiles[profile_idx]
		var data := TerrainGenerator.generate(profile, seed_val)
		_tv_preview_data = data
		_terrain.load_map(data)
		if _tv_valid_lbl != null:
			if data.validation_failure == "":
				_tv_valid_lbl.text = "gen: attempt %d/%d OK" \
						% [data.attempts_used, TerrainGenerator.MAX_ATTEMPTS]
			else:
				_tv_valid_lbl.text = "gen: FAILED (seed %d)\n%s" \
						% [seed_val, data.validation_failure]
	else:
		_terrain.generate(seed_val)
		_tv_preview_data = null
		if _tv_valid_lbl != null:
			_tv_valid_lbl.text = "gen: legacy noise"
	_renderer.mark_all_dirty()
	if _tv_minimap != null:
		_tv_minimap.queue_redraw()
	_snap_all_entities()

func _reposition_units() -> void:
	_snap_all_entities()

func _snap_all_entities() -> void:
	var units : Array = _combat.player_units + _combat.enemy_units
	for u in units:
		var unit : Unit = u
		var x := clampi(unit.vox_position.x, 0, _terrain.map_width - unit.definition.width_voxels)
		unit.set_vox_position(UnitMovement.settle_at(
			Vector2i(x, 0), unit.definition.width_voxels, unit.definition.height_voxels, _terrain))
	for d in _combat.deployables:
		var dep : Node = d
		var w   : int  = dep.get("width_voxels")
		var h   : int  = dep.get("height_voxels")
		var x   := clampi(dep.get("vox_position").x, 0, _terrain.map_width - w)
		dep.set_vox_position(UnitMovement.settle_at(Vector2i(x, 0), w, h, _terrain))

# ── Status injection ─────────────────────────────────────────────────────────

func _apply_status_to_last_spawn() -> void:
	if _last_spawned == null or not is_instance_valid(_last_spawned):
		return
	if _status_defs.is_empty():
		return
	var def : StatusEffectDef = _status_defs[_status_option.selected]
	var inst := StatusInstance.new(def, int(_stacks_spin.value))
	_last_spawned.active_statuses[def.id] = inst
	_last_spawned.queue_redraw()

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

func _load_status_defs() -> Array[StatusEffectDef]:
	var out : Array[StatusEffectDef] = []
	var dir := DirAccess.open("res://data/statuses/")
	if dir == null: return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res := load("res://data/statuses/" + f)
			if res is StatusEffectDef:
				out.append(res as StatusEffectDef)
		f = dir.get_next()
	out.sort_custom(func(a, b): return a.display_name < b.display_name)
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

func _make_spinbox(min_val: float, max_val: float, default_val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.value = default_val
	sb.step = 1.0
	sb.focus_mode = Control.FOCUS_NONE
	sb.add_theme_font_size_override("font_size", 10)
	sb.custom_minimum_size.x = 56
	return sb
