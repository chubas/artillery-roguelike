# Combat unit (M2 spec §3). Replaces the M1 PlayerUnit placeholder.
# All visuals are code-drawn placeholders: body rect, HP bar, selection border.
class_name Unit
extends Node2D

signal unit_damaged(unit: Unit, dmg: int, remaining_hp: int)
signal unit_died(unit: Unit)
signal anim_done   # M31: emitted by play_anim when the animation finishes

@export var definition : UnitDefinition
@export var is_player : bool = true

var display_name : String = ""          # per-instance (e.g. "EnemyA" / "EnemyB")
var hp : int = 0
# Attack power (M40): definition.base_power folded with source-attributed PowerMods. The unit
# holds no scalar attack field anymore — effective attack is computed on demand via
# PowerCalculator.effective_attack(self). power_mods carries both PERMANENT (run-level, copied
# from run_state at spawn) and COMBAT (per-combat) modifiers; see add_power_mod / adjust_power_mod.
var power_mods : Array[PowerMod] = []
# Base dig value (M16): terrain-only impact strength; mirrors definition.dig at spawn.
var dig : int = 1
# Run-state link (M12): when set, this Unit is the combat representation of a persistent
# RunUnitState — _ready() initializes hp/kills/attack from it (so the unit can spawn damaged),
# and CombatBridge.write_back() copies hp/kills/disabled back to it on combat exit. null in
# pure-combat / smoke contexts (then the unit spawns at full HP).
var run_state : RunUnitState = null
var essences  : Array[EssenceDef] = []   # M22: per-unit essences loaded from run_state at combat start
var kills : int = 0   # persists via run_state; enemies killed by this unit (M12)
# Shield (M5): a flat, per-combat absorb pool above HP. Granted by cards / generators.
var shield : int = 0
# Armor (M20): second flat absorb pool, below shield in the mitigation stack.
var armor : int = 0
var vox_position : Vector2i = Vector2i.ZERO
var aim_angle_deg : float = 45.0        # positive-up convention; preserved per unit
# Gunbound-style power memory (M4): the charge fraction of this unit's last shot. The HUD
# draws a marker on the charge bar at this position so the player can re-dial the same power.
var last_power_frac : float = 0.5
var is_done : bool = false              # true after firing this turn
var primed_elements : Array[ElementDef] = []   # M30: accumulated by prime cards; consumed on next fire
var dig_modifier : int = 0              # M16: flat dig adjustment at fire time (unused in M16 content)
var moved_this_turn : bool = false      # M9: set true by CombatManager.try_move(), reset each round
var move_origin : Vector2i              # vox_position at turn start (for undo)
var actions_spent_moving : int = 0
var selected : bool = false     # the controllable unit (white outline) — see set_selected
var inspected : bool = false    # whichever unit the inspector panel shows — see set_inspected
var debug_invulnerable : bool = false   # M24: set by sandbox overlay; blocks all incoming damage
var stack_visual_offset : Vector2 = Vector2.ZERO   # M29: 2.5D draw-only depth cue; does not affect vox_position or hitbox
var _dying : bool = false   # M31: true while death_fade plays; blocks click/hover interaction

## Active status instances (M3 §4.4). Key = status id, value = StatusInstance.
var active_statuses : Dictionary = {}

## Shot chosen this activation (M3 §8). null = fall back to default_shot.
var selected_shot : ShotDefinition = null

func get_active_shot() -> ShotDefinition:
	return selected_shot if selected_shot != null else definition.default_shot

## Shots the player may pick from; falls back to [default_shot] if none authored.
func available_shots() -> Array:
	if definition.available_shots.is_empty():
		return [definition.default_shot]
	return definition.available_shots

func _ready() -> void:
	if run_state != null:
		# Spawn from persistent run state: current HP (may be damaged), carried kills.
		hp = run_state.current_hp
		kills = run_state.kills
		dig = definition.dig + run_state.bonus_dig
		# Permanent power mods are seeded from run state (combat mods are added later by sources).
		for d in run_state.power_mods:
			power_mods.append(PowerMod.from_dict(d))
	else:
		hp = definition.max_hp
		dig = definition.dig
	armor = definition.base_armor if Features.armor_enabled else 0
	move_origin = vox_position
	if display_name == "":
		display_name = definition.display_name

## Effective attack power (M40): base_power folded with all active PowerMods (two-tier).
func attack_value() -> int:
	return PowerCalculator.effective_attack(self)

## Add a mod, replacing any existing mod from the same source (idempotent registration).
func add_power_mod(mod: PowerMod) -> void:
	remove_power_mod(mod.source)
	power_mods.append(mod)
	queue_redraw()

## Accumulate `delta` onto a same-source ADD mod (creating it if absent). For stacking
## buffs/debuffs that apply repeatedly, e.g. enemy_debuff's -3 per turn. MULT sources should
## use add_power_mod instead — accumulating a product is rarely the intent.
func adjust_power_mod(source: String, op: PowerMod.Op, delta: float,
		tier: PowerMod.Tier, label := "") -> void:
	for m in power_mods:
		if m.source == source:
			m.value += delta
			queue_redraw()
			return
	power_mods.append(PowerMod.new(source, op, delta, tier, label))
	queue_redraw()

func remove_power_mod(source: String) -> void:
	for i in range(power_mods.size() - 1, -1, -1):
		if power_mods[i].source == source:
			power_mods.remove_at(i)
	queue_redraw()

# --- State ---------------------------------------------------------------------
func take_damage(dmg: int, element: ElementDef = null) -> void:
	if debug_invulnerable:
		return
	if hp <= 0:
		return
	var hp_before := hp
	var shield_before := shield
	var armor_before := armor
	var remaining := dmg
	remaining = _absorb_mitigation(remaining, element, ElementDef.MitigationLayer.SHIELD,
			"shield", Features.shields_enabled)
	remaining = _absorb_mitigation(remaining, element, ElementDef.MitigationLayer.ARMOR,
			"armor", Features.armor_enabled)
	if remaining > 0:
		var hp_mult := element.mitigation_mult(ElementDef.MitigationLayer.HP) if element else 1.0
		var hp_hit := _layer_damage(remaining, hp_mult)
		hp = maxi(0, hp - hp_hit)
	var shield_abs := shield_before - shield
	var armor_abs := armor_before - armor
	var hp_lost := hp_before - hp
	var el_tag := " [%s]" % element.id if element else ""
	var mitig := ""
	if shield_abs > 0:
		mitig += " shield-%d" % shield_abs
	if armor_abs > 0:
		mitig += " armor-%d" % armor_abs
	print("[hit] %s: incoming=%d%s%s → HP %d→%d (-%d)" % [
			display_name, dmg, el_tag, mitig, hp_before, hp, hp_lost])
	queue_redraw()
	unit_damaged.emit(self, dmg, hp)
	if hp == 0:
		is_done = true
		active_statuses.clear()
		unit_died.emit(self)
		EventBus.unit_died.emit(self)

func _layer_damage(amount: int, mult: float) -> int:
	return maxi(1, int(round(float(amount) * mult)))

func _absorb_mitigation(remaining: int, element: ElementDef, layer: ElementDef.MitigationLayer,
		pool_name: String, enabled: bool) -> int:
	if not enabled or remaining <= 0:
		return remaining
	var pool : int = armor if pool_name == "armor" else shield
	if pool <= 0:
		return remaining
	var mult := element.mitigation_mult(layer) if element else 1.0
	var hit := _layer_damage(remaining, mult)
	var absorbed := mini(pool, hit)
	if pool_name == "armor":
		armor -= absorbed
		EventBus.unit_armor_changed.emit(self, armor)
	else:
		shield -= absorbed
		EventBus.unit_shield_changed.emit(self, shield)
	return hit - absorbed

# Grants shield (M5 card effect). A method (not direct field access) so the redraw
# always happens — direct field writes were the cause of the "bar doesn't update" bug.
func add_shield(amount: int) -> void:
	shield += amount
	queue_redraw()

func add_armor(amount: int) -> void:
	armor += amount
	queue_redraw()

func reset_for_turn() -> void:
	if hp <= 0:
		return
	is_done = false
	move_origin = vox_position
	actions_spent_moving = 0
	selected_shot = null   # default back to the free basic shell each turn
	queue_redraw()

func mark_done() -> void:
	is_done = true
	queue_redraw()

func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()

# Inspector-panel focus (M5 polish): a distinct cyan outline, separate from the
# white "controllable unit" outline, so allies and enemies can both be inspected.
func set_inspected(v: bool) -> void:
	if inspected == v:
		return
	inspected = v
	queue_redraw()

# Single chokepoint for every position change (move, knockback, gravity pull, fall) —
# emitting unit_moved here (rather than at each call site) lets listeners like mine
# proximity triggers (M6) react uniformly no matter what caused the move.
func set_vox_position(p: Vector2i) -> void:
	var from := vox_position
	vox_position = p
	position = Const.voxel_to_world(p)
	if from != p:
		EventBus.unit_moved.emit(self, from, p)

# --- Geometry --------------------------------------------------------------------
func aim_dir() -> Vector2:
	var r := deg_to_rad(aim_angle_deg)
	return Vector2(cos(r), -sin(r))

func barrel_origin_world() -> Vector2:
	return Const.voxel_to_world(vox_position) \
		+ Vector2(definition.width_voxels * Const.VOXEL_SIZE * 0.5, 0.0) \
		+ Vector2(definition.barrel_offset) * Const.VOXEL_SIZE

func center_world() -> Vector2:
	return Const.voxel_to_world(vox_position) \
		+ Vector2(definition.width_voxels, definition.height_voxels) * Const.VOXEL_SIZE * 0.5

func center_voxel() -> Vector2i:
	return vox_position + Vector2i(definition.width_voxels / 2, definition.height_voxels / 2)

func bounds_rect_world() -> Rect2:
	return Rect2(Const.voxel_to_world(vox_position),
		Vector2(definition.width_voxels, definition.height_voxels) * Const.VOXEL_SIZE)

func contains_voxel(vox: Vector2i) -> bool:
	return vox.x >= vox_position.x and vox.x < vox_position.x + definition.width_voxels \
		and vox.y >= vox_position.y and vox.y < vox_position.y + definition.height_voxels

# --- Visuals (M2 spec §3.3–3.4) --------------------------------------------------
func _draw() -> void:
	draw_set_transform(stack_visual_offset)
	var w := definition.width_voxels * Const.VOXEL_SIZE
	var h := definition.height_voxels * Const.VOXEL_SIZE
	var body := Rect2(0, 0, w, h)
	var col := definition.color
	if hp <= 0:
		col = Color(0.35, 0.08, 0.08)              # dead: dark red wreck
	elif is_done and is_player:
		col = col.lerp(Color(0.5, 0.5, 0.5), 0.6)  # done: desaturated
	elif selected:
		col = col.lightened(0.15)                  # selected: brightened
	draw_rect(body, col)
	draw_rect(body, col.darkened(0.4), false, 1.0)
	if selected and hp > 0:
		draw_rect(body.grow(2.0), Color.WHITE, false, 2.0)
	elif inspected and hp > 0:
		draw_rect(body.grow(2.0), Color(0.3, 0.85, 0.95), false, 2.0)
	if hp > 0:
		_draw_stat_icons(w)      # attack + shield icons, above the HP bar (M10)
		_draw_hp_bar(w)
		_draw_effect_badges(h)   # effect icons, below the body (M10)

func _draw_hp_bar(w: float) -> void:
	var frac := float(hp) / definition.max_hp
	draw_rect(Rect2(0, -7, w, 4), Color(0, 0, 0, 0.7))
	var c := Color(0.25, 0.85, 0.3)        # green above 50%
	if frac < 0.25:
		c = Color(0.9, 0.2, 0.15)          # red below 25%
	elif frac <= 0.5:
		c = Color(0.95, 0.6, 0.15)         # orange 25–50%
	draw_rect(Rect2(1, -6, maxf(0.0, (w - 2) * frac), 2), c)
	_draw_bar_value(w, -7, "%d/%d" % [hp, definition.max_hp])

func _draw_bar_value(w: float, bar_top_y: float, text: String) -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(w + 3.0, bar_top_y + 6.0)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

# Stat icons (M10): attack (always) + shield (when > 0) as placeholder circles with their
# values, laid out left-to-right in a row just above the HP bar.
func _draw_stat_icons(_w: float) -> void:
	var cy := -16.0
	var x := 2.0
	x = _draw_icon_value(x, cy, Color(0.9, 0.4, 0.25), attack_value())   # attack — reddish
	if shield > 0:
		x = _draw_icon_value(x, cy, Color(0.4, 0.75, 1.0), shield)   # shield — blue
	if armor > 0:
		x = _draw_icon_value(x, cy, Color(0.95, 0.82, 0.25), armor)   # armor — yellow

# Effect badges (M10): one placeholder circle + stack value per active effect, in a row just
# below the body. Replaces the M3 top-of-unit status squares. Buffs are green; debuffs use the
# element-tag palette.
func _draw_effect_badges(h: float) -> void:
	if active_statuses.is_empty():
		return
	var cy := h + 9.0
	var x := 2.0
	for id in active_statuses:
		var inst : StatusInstance = active_statuses[id]
		x = _draw_icon_value(x, cy, _effect_color(inst.definition), inst.stacks)

# Shared placeholder glyph: a filled circle (with a faint outline) and its integer value to
# the right. Returns the next free x so callers can pack several in a row.
func _draw_icon_value(x: float, cy: float, fill: Color, value: int) -> float:
	var font := ThemeDB.fallback_font
	var r := 4.5
	draw_circle(Vector2(x + r, cy), r, fill)
	draw_arc(Vector2(x + r, cy), r, 0.0, TAU, 14, Color(0, 0, 0, 0.5), 1.0)
	var txt := str(value)
	var tx := x + 2.0 * r + 2.0
	var ty := cy + 4.0
	draw_string(font, Vector2(tx + 1, ty + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	return tx + tw + 6.0

func _effect_color(def: StatusEffectDef) -> Color:
	if def.is_buff:
		return Color(0.3, 0.85, 0.4)        # buff — green
	if "FIRE" in def.tags:
		return Color(1.0, 0.5, 0.1)
	if "ELECTRIC" in def.tags:
		return Color(0.4, 0.8, 1.0)
	return Color(0.75, 0.75, 0.75)

# --- Animation interface (M31) ------------------------------------------------
func play_anim(anim_id: String, params: Dictionary, duration: float) -> void:
	if duration == 0.0:
		_apply_anim_end_state(anim_id, params)
		anim_done.emit()
		return
	match anim_id:
		"hit_flash":
			var col : Color = params.get("color", Color.WHITE)
			var t := create_tween()
			t.tween_property(self, "modulate", col, duration * 0.4)
			t.tween_property(self, "modulate", Color.WHITE, duration * 0.6)
			await t.finished
			anim_done.emit()
		"death_fade":
			_dying = true
			var t := create_tween()
			t.tween_property(self, "modulate:a", 0.0, duration)
			await t.finished
			anim_done.emit()
		"status_pulse":
			var t := create_tween()
			t.tween_property(self, "modulate:a", 0.5, duration * 0.5)
			t.tween_property(self, "modulate:a", 1.0, duration * 0.5)
			await t.finished
			anim_done.emit()
		_:
			anim_done.emit()

func snap_anim(anim_id: String) -> void:
	match anim_id:
		"death_fade":
			modulate.a = 0.0
			_dying = true
		_:
			modulate = Color.WHITE

func _apply_anim_end_state(anim_id: String, _params: Dictionary) -> void:
	match anim_id:
		"death_fade":
			modulate.a = 0.0
			_dying = true
		_:
			modulate = Color.WHITE
