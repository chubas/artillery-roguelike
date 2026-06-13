# Data definition of a unit type (M2 spec §2.4).
class_name UnitDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Unit"

## Physical footprint (voxels)
@export var width_voxels : int = 2
@export var height_voxels : int = 3

## Stats
@export var max_hp : int = 6
@export var move_range : int = 4   # voxels per activation
@export var climb_max : int = 1    # max voxel height climbed free

## Firing
@export var default_shot : ShotDefinition = null
@export var barrel_offset : Vector2i = Vector2i(0, -1)
	# offset in voxels from unit top-center to barrel origin

## Prototype visuals (replaced by sprites post-M2)
@export var color : Color = Color(0.5, 0.5, 0.5)

# POST-M2: capacity_cost, action_points, upgrade slots, race, mount type,
#          enemy_launch_angle_deg (spec §11 Q3)
