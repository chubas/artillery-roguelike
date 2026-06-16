# Non-unit, on-map entity (M6 spec): mines, shield generators, future artifacts.
# Lives on its own voxel footprint, can be damaged and can fall like a unit, but has
# none of Unit's action economy, statuses, or shot loadout. Subclasses add behavior
# (Mine's proximity/explosion, ShieldGenerator's aura) on top of this HP/position shell.
class_name Deployable
extends Node2D

var max_hp : int = 1
var hp : int = 1
var vox_position : Vector2i = Vector2i.ZERO
var width_voxels : int = 1
var height_voxels : int = 1
var display_name : String = "Deployable"
var color : Color = Color.GRAY

func set_vox_position(p: Vector2i) -> void:
	vox_position = p
	position = Const.voxel_to_world(p)

func bounds_rect_world() -> Rect2:
	return Rect2(Const.voxel_to_world(vox_position),
		Vector2(width_voxels, height_voxels) * Const.VOXEL_SIZE)

func contains_voxel(vox: Vector2i) -> bool:
	return vox.x >= vox_position.x and vox.x < vox_position.x + width_voxels \
		and vox.y >= vox_position.y and vox.y < vox_position.y + height_voxels

func take_damage(dmg: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - dmg)
	queue_redraw()
	if hp == 0:
		_die()

# Overridden by subclasses that need a special death trigger (e.g. Mine's explosion).
func _die() -> void:
	EventBus.deployable_died.emit(self)

func _draw() -> void:
	var w := width_voxels * Const.VOXEL_SIZE
	var h := height_voxels * Const.VOXEL_SIZE
	var body := Rect2(0, 0, w, h)
	draw_rect(body, color)
	draw_rect(body, color.darkened(0.4), false, 1.0)
