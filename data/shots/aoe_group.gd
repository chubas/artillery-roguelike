# One set of voxel offsets sharing the same damage value (M2 spec §2.1).
# (0,0) is always the impact voxel.
class_name AoEGroup
extends Resource

## Voxel offsets from impact point (col_delta, row_delta).
@export var offsets : Array[Vector2i] = []

## Damage applied to every voxel in this group.
@export var damage : int = 0

# POST-M2: element, push_force, flags, delay_turns
