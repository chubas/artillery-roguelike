# Combat unit (M2 spec §3). Replaces the M1 PlayerUnit placeholder.
# All visuals are code-drawn placeholders: body rect, HP bar, selection border.
class_name Unit
extends Node2D

signal unit_damaged(unit: Unit, dmg: int, remaining_hp: int)
signal unit_died(unit: Unit)

@export var definition : UnitDefinition
@export var is_player : bool = true

var display_name : String = ""          # per-instance (e.g. "EnemyA" / "EnemyB")
var hp : int = 0
# Shield (M5): a flat, per-combat absorb pool that sits above HP in the mitigation
# stack. Granted by cards for now (no baseline/regen yet). Armor would slot in
# above shield later — see the seam comment in take_damage().
var shield : int = 0
var max_shield : int = 0
var vox_position : Vector2i = Vector2i.ZERO
var aim_angle_deg : float = 45.0        # positive-up convention; preserved per unit
# Gunbound-style power memory (M4): the charge fraction of this unit's last shot. The HUD
# draws a marker on the charge bar at this position so the player can re-dial the same power.
var last_power_frac : float = 0.5
var is_done : bool = false              # true after firing this turn
var move_origin : Vector2i              # vox_position at turn start (for undo)
var actions_spent_moving : int = 0
var selected : bool = false

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
	hp = definition.max_hp
	move_origin = vox_position
	if display_name == "":
		display_name = definition.display_name

# --- State ---------------------------------------------------------------------
func take_damage(dmg: int) -> void:
	if hp <= 0:
		return
	var remaining := dmg
	# Mitigation pipeline (card-engine doc §5): armor → shield → HP.
	# POST-M5 SEAM: an Armor layer would reduce `remaining` here, before shield.
	# Not implemented yet — Shield is the only mitigation layer this milestone adds.
	if Features.shields_enabled and shield > 0:
		var absorbed := mini(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		EventBus.unit_shield_changed.emit(self, shield, max_shield)
	hp = maxi(0, hp - remaining)
	queue_redraw()
	unit_damaged.emit(self, dmg, hp)
	if hp == 0:
		is_done = true
		active_statuses.clear()
		unit_died.emit(self)
		EventBus.unit_died.emit(self)

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

func set_vox_position(p: Vector2i) -> void:
	vox_position = p
	position = Const.voxel_to_world(p)

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
	if hp > 0:
		_draw_hp_bar(w)
		_draw_shield_bar(w)
		_draw_status_badges(w)

func _draw_hp_bar(w: float) -> void:
	var frac := float(hp) / definition.max_hp
	draw_rect(Rect2(0, -7, w, 4), Color(0, 0, 0, 0.7))
	var c := Color(0.25, 0.85, 0.3)        # green above 50%
	if frac < 0.25:
		c = Color(0.9, 0.2, 0.15)          # red below 25%
	elif frac <= 0.5:
		c = Color(0.95, 0.6, 0.15)         # orange 25–50%
	draw_rect(Rect2(1, -6, maxf(0.0, (w - 2) * frac), 2), c)

# Shield bar (M5): a thin strip above the HP bar, only drawn while shield > 0.
func _draw_shield_bar(w: float) -> void:
	if shield <= 0:
		return
	var frac := clampf(float(shield) / maxf(1.0, float(max_shield)), 0.0, 1.0)
	draw_rect(Rect2(0, -11, w, 3), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(1, -10.5, maxf(0.0, (w - 2) * frac), 2), Color(0.4, 0.75, 1.0))

# Placeholder status badges (M3 §15): a small colour-coded square per active status with
# its stack count. Colour by element tag — fire = orange, electric = cyan.
func _draw_status_badges(w: float) -> void:
	if active_statuses.is_empty():
		return
	var font := ThemeDB.fallback_font
	var bx := 0.0
	for id in active_statuses:
		var inst : StatusInstance = active_statuses[id]
		var c := Color(0.7, 0.7, 0.7)
		if "FIRE" in inst.definition.tags:
			c = Color(1.0, 0.5, 0.1)
		elif "ELECTRIC" in inst.definition.tags:
			c = Color(0.4, 0.8, 1.0)
		var r := Rect2(bx, -22, 11, 11)
		draw_rect(r, c)
		draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
		draw_string(font, Vector2(bx + 2.5, -13), str(inst.stacks),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.BLACK)
		bx += 13.0
