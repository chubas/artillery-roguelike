# M36: Upgrade node screen. Three options: upgrade a unit stat, fuse two units, remove cards from deck.
class_name UpgradeScreen
extends CanvasLayer

signal upgrade_completed

enum Phase { MAIN, PICK_UNIT, PICK_UPGRADE, PICK_TARGET, CONFIRM_FUSE, PICK_CARDS }

var _phase          : Phase = Phase.MAIN
var _source_idx     : int   = -1
var _target_idx     : int   = -1
var _cards_removed  : int   = 0

var _content : VBoxContainer = null

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

	var title := _label("UPGRADE", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.35, 0.65, 0.95))
	outer.add_child(title)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	outer.add_child(_content)

	_show_main()

# ── MAIN ──────────────────────────────────────────────────────────────────────

func _show_main() -> void:
	_phase = Phase.MAIN
	_source_idx = -1
	_target_idx = -1
	_clear_content()

	var sub := _label("Choose an upgrade for your squad.", 14)
	sub.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(sub)

	_content.add_child(_make_button("Upgrade Unit  (+ATK / +Boosted / +Fire Prime / +Dig)",
			func() -> void: _show_pick_unit(false)))

	var can_fuse := Run.active.squad.size() >= 2
	var fuse_btn := _make_button("Fuse Two Units  (transfer essences, +%d◆)" % SquadOps.FUSION_REFUND,
			func() -> void: _show_pick_unit(true))
	fuse_btn.disabled = not can_fuse
	_content.add_child(fuse_btn)

	var has_cards := not Run.active.deck.is_empty()
	var remove_btn := _make_button("Remove Cards from Deck  (up to 2)",
			func() -> void: _show_pick_cards())
	remove_btn.disabled = not has_cards
	_content.add_child(remove_btn)

# ── PICK UNIT ─────────────────────────────────────────────────────────────────

func _show_pick_unit(for_fuse: bool) -> void:
	_phase = Phase.PICK_UNIT
	_clear_content()

	var prompt := "Pick a unit to sacrifice:" if for_fuse else "Pick a unit to upgrade:"
	var header := _label(prompt, 14)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	for i in range(Run.active.squad.size()):
		var unit : RunUnitState = Run.active.squad[i]
		var idx := i
		var lbl := "%s  (%d/%d HP)" % [unit.display_name, unit.current_hp, unit.max_hp]
		var btn := _make_button(lbl, Callable())
		if unit.is_disabled:
			btn.disabled = true
		btn.pressed.connect(func() -> void:
			_source_idx = idx
			if for_fuse:
				_show_pick_target()
			else:
				_show_pick_upgrade())
		_content.add_child(btn)

	_content.add_child(_make_button("Back", func() -> void: _show_main()))

# ── PICK UPGRADE ──────────────────────────────────────────────────────────────

func _show_pick_upgrade() -> void:
	_phase = Phase.PICK_UPGRADE
	_clear_content()

	if _source_idx < 0 or _source_idx >= Run.active.squad.size():
		_show_main()
		return
	var unit : RunUnitState = Run.active.squad[_source_idx]
	var header := _label("Upgrade %s:" % unit.display_name, 14)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	_content.add_child(_make_button("+2 Attack Power  (current: %d)" % PowerCalculator.card_attack(unit, load(unit.definition_id)),
			func() -> void: _apply_upgrade(0)))
	_content.add_child(_make_button("+3 Permanent Boosted  (current: %d)" % unit.permanent_boosted,
			func() -> void: _apply_upgrade(1)))
	_content.add_child(_make_button("+Fire Prime  (current: %d)" % unit.permanent_fire_prime,
			func() -> void: _apply_upgrade(2)))
	_content.add_child(_make_button("+1 Digging Power  (current: %d)" % unit.bonus_dig,
			func() -> void: _apply_upgrade(3)))
	_content.add_child(_make_button("Back", func() -> void: _show_pick_unit(false)))

func _apply_upgrade(type: int) -> void:
	if _source_idx < 0 or _source_idx >= Run.active.squad.size():
		_show_main()
		return
	var unit : RunUnitState = Run.active.squad[_source_idx]
	match type:
		0: unit.add_permanent_mod("upgrade:attack", PowerMod.Op.ADD, 2.0, "Upgrade")
		1: unit.permanent_boosted    += 3
		2: unit.permanent_fire_prime += 1
		3: unit.bonus_dig            += 1
	upgrade_completed.emit()

# ── PICK TARGET (fuse) ────────────────────────────────────────────────────────

func _show_pick_target() -> void:
	_phase = Phase.PICK_TARGET
	_clear_content()

	if _source_idx < 0 or _source_idx >= Run.active.squad.size():
		_show_main()
		return
	var src_name : String = Run.active.squad[_source_idx].display_name
	var header := _label("Pick the unit that will receive %s's essences:" % src_name, 14)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	for i in range(Run.active.squad.size()):
		if i == _source_idx:
			continue
		var unit : RunUnitState = Run.active.squad[i]
		var idx := i
		var lbl := "%s  (%d/%d HP)" % [unit.display_name, unit.current_hp, unit.max_hp]
		var btn := _make_button(lbl, Callable())
		btn.pressed.connect(func() -> void:
			_target_idx = idx
			_show_confirm_fuse())
		_content.add_child(btn)

	_content.add_child(_make_button("Back", func() -> void: _show_main()))

# ── CONFIRM FUSE ──────────────────────────────────────────────────────────────

func _show_confirm_fuse() -> void:
	_phase = Phase.CONFIRM_FUSE
	_clear_content()

	if _source_idx < 0 or _target_idx < 0 \
			or _source_idx >= Run.active.squad.size() \
			or _target_idx >= Run.active.squad.size():
		_show_main()
		return
	var src : RunUnitState = Run.active.squad[_source_idx]
	var tgt : RunUnitState = Run.active.squad[_target_idx]
	var msg := "Fuse %s into %s?\n\n%s will be retired. All equipped essences (%d) transfer to %s.\nYou receive +%d◆." % [
		src.display_name, tgt.display_name,
		src.display_name, src.equipped_essences.size(),
		tgt.display_name,
		SquadOps.FUSION_REFUND
	]
	var info := _label(msg, 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(info)

	_content.add_child(_make_button("Confirm Fusion", func() -> void:
		SquadOps.fuse_units(Run.active, _source_idx, _target_idx)
		upgrade_completed.emit()))
	_content.add_child(_make_button("Back", func() -> void: _show_main()))

# ── PICK CARDS ────────────────────────────────────────────────────────────────

func _show_pick_cards() -> void:
	_phase = Phase.PICK_CARDS
	_cards_removed = 0
	_rebuild_card_list()

func _rebuild_card_list() -> void:
	_clear_content()

	if Run.active.deck.is_empty() or _cards_removed >= 2:
		_show_main()
		return

	var header := _label(
		"Select a card to remove from your deck. (%d removed, %d remaining slot)" % [_cards_removed, 2 - _cards_removed], 13)
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_content.add_child(header)

	# Build deduplicated set with counts, then one button per unique card.
	var counts : Dictionary = {}
	for path in Run.active.deck:
		counts[path] = counts.get(path, 0) + 1

	for path in counts:
		var def : CardDefinition = load(path)
		if def == null:
			continue
		var count : int = counts[path]
		var label_txt := def.display_name + (" (x%d)" % count if count > 1 else "")
		var p : String = path
		var btn := _make_button(label_txt, Callable())
		btn.pressed.connect(func() -> void:
			Run.active.deck.erase(p)
			_cards_removed += 1
			if _cards_removed >= 2 or Run.active.deck.is_empty():
				upgrade_completed.emit()
			else:
				_rebuild_card_list())
		_content.add_child(btn)

	if _cards_removed >= 1:
		_content.add_child(_make_button("Skip (keep remaining cards)", func() -> void: upgrade_completed.emit()))
	_content.add_child(_make_button("Cancel", func() -> void: _show_main()))

# ── Helpers ───────────────────────────────────────────────────────────────────

func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()

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
