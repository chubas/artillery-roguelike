# Shop screen (M34): spend Shards on cards, artifacts, and units.
# Follows the code-drawn CanvasLayer pattern. RunController swaps this in
# when the player selects a SHOP node; emits shop_closed when they leave.
class_name ShopScreen
extends CanvasLayer

signal shop_closed

const PRICE_CARD    := 10
const PRICE_ARTIFACT := 15
const PRICE_UNIT    := 20
const REROLL_BASE   := 5

var _card_offer     : Array[String] = []
var _artifact_offer : Array[String] = []
var _unit_offer     : String = ""
var _bought         : Dictionary = {}   # path → true (cleared on re-roll for unbought)
var _reroll_cost    : int = REROLL_BASE

var _shards_label   : Label
var _reroll_btn     : Button
var _items_root     : VBoxContainer   # rebuilt on re-roll

func setup() -> void:
	_sample_offers()
	_build()

func _sample_offers() -> void:
	_card_offer     = _sample_cards(5)
	_artifact_offer = Run.pick_artifacts_for_offer(3)
	_unit_offer     = _sample_unit()

func _sample_cards(n: int) -> Array[String]:
	var pool := Run.active.card_pool
	if pool.is_empty():
		return []
	var src := pool.duplicate()
	var out : Array[String] = []
	for _i in range(mini(n, src.size())):
		var idx := Run.run_rng.randi() % src.size()
		out.append(src[idx])
		src.remove_at(idx)
	return out

func _sample_unit() -> String:
	var pool := Run.active.unit_pool
	if pool.is_empty():
		return ""
	return pool[Run.run_rng.randi() % pool.size()]

# ── Build ──────────────────────────────────────────────────────────────────────

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.06, 0.12, 0.97)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	root.add_child(outer)

	# Header row: shards + title
	var header := HBoxContainer.new()
	_shards_label = _make_label("", 15)
	_shards_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	header.add_child(_shards_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var title := _make_label("SHOP", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	header.add_child(title)
	outer.add_child(header)

	# Items area (rebuilt on re-roll)
	_items_root = VBoxContainer.new()
	_items_root.add_theme_constant_override("separation", 0)
	outer.add_child(_items_root)

	_build_items()

	# Footer: re-roll + leave
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	_reroll_btn = Button.new()
	_reroll_btn.focus_mode = Control.FOCUS_NONE
	_reroll_btn.pressed.connect(_on_reroll)
	footer.add_child(_reroll_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.pressed.connect(func() -> void: shop_closed.emit())
	footer.add_child(leave_btn)
	outer.add_child(footer)

	_refresh_header()

func _build_items() -> void:
	for c in _items_root.get_children():
		c.queue_free()

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_root.add_child(cols)

	# Cards column
	var card_col := _make_column("CARDS (%d ◆)" % PRICE_CARD)
	for path in _card_offer:
		card_col.add_child(_make_item_row(path, PRICE_CARD, _item_label_for(path)))
	cols.add_child(card_col)

	# Artifacts column
	var art_col := _make_column("ARTIFACTS (%d ◆)" % PRICE_ARTIFACT)
	for path in _artifact_offer:
		art_col.add_child(_make_item_row(path, PRICE_ARTIFACT, _item_label_for(path)))
	cols.add_child(art_col)

	# Units column
	var unit_col := _make_column("UNITS (%d ◆)" % PRICE_UNIT)
	if not _unit_offer.is_empty():
		unit_col.add_child(_make_item_row(_unit_offer, PRICE_UNIT, _item_label_for(_unit_offer)))
	cols.add_child(unit_col)

func _make_column(header_text: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var h := _make_label(header_text, 13)
	h.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	col.add_child(h)
	var sep := HSeparator.new()
	col.add_child(sep)
	return col

func _make_item_row(path: String, price: int, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := _make_label(label_text, 13)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Buy (%d ◆)" % price
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = _bought.has(path) or Run.active.resources.get("shards", 0) < price
	var p := path
	var pr := price
	btn.pressed.connect(func() -> void: _on_buy(p, pr, btn))
	row.add_child(btn)
	row.set_meta("buy_btn", btn)
	row.set_meta("path", path)
	row.set_meta("price", price)
	return row

func _item_label_for(path: String) -> String:
	var res := load(path)
	if res is UnitDefinition:
		return (res as UnitDefinition).display_name
	if res is ArtifactDef:
		return (res as ArtifactDef).artifact_name
	if res is CardDefinition:
		return (res as CardDefinition).display_name
	return path.get_file()

# ── Actions ────────────────────────────────────────────────────────────────────

func _on_buy(path: String, price: int, btn: Button) -> void:
	if Run.active.resources.get("shards", 0) < price or _bought.has(path):
		return
	Run.active.resources["shards"] -= price
	_bought[path] = true

	var res := load(path)
	if res is UnitDefinition:
		Run.active.squad.append(RunUnitState.from_definition(path, (res as UnitDefinition).display_name))
	elif res is ArtifactDef:
		Run.active.artifacts.append(path)
		Run.active.artifact_pool.erase(path)
		Run.active.artifact_seen_set.erase(path)
	elif res is CardDefinition:
		Run.active.deck.append(path)

	btn.disabled = true
	_refresh_header()
	_refresh_buy_buttons()

func _on_reroll() -> void:
	var cost := _reroll_cost
	if Run.active.resources.get("shards", 0) < cost:
		return
	Run.active.resources["shards"] -= cost
	_reroll_cost += REROLL_BASE

	# Re-sample: cards and unit allow repeats; artifacts respect cycling.
	_card_offer     = _sample_cards(5)
	_artifact_offer = Run.pick_artifacts_for_offer(3)
	_unit_offer     = _sample_unit()
	_bought.clear()

	_build_items()
	_refresh_header()

func _refresh_header() -> void:
	_shards_label.text = "◆ Shards: %d" % Run.active.resources.get("shards", 0)
	if _reroll_btn != null:
		_reroll_btn.text = "Re-roll (%d ◆)" % _reroll_cost
		_reroll_btn.disabled = Run.active.resources.get("shards", 0) < _reroll_cost

func _refresh_buy_buttons() -> void:
	var shards : int = Run.active.resources.get("shards", 0)
	for col in _items_root.get_children():
		for row in col.get_children():
			if row.has_meta("buy_btn"):
				var btn : Button = row.get_meta("buy_btn")
				var path : String = row.get_meta("path")
				var price : int = row.get_meta("price")
				if not _bought.has(path):
					btn.disabled = shards < price

# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l
