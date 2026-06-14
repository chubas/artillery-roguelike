# One set of voxel offsets sharing the same damage value (M2 spec §2.1).
# (0,0) is always the impact voxel.
class_name AoEGroup
extends Resource

## Voxel offsets from impact point (col_delta, row_delta).
@export var offsets : Array[Vector2i] = []

## Damage applied to every voxel in this group.
@export var damage : int = 0

## Element carried by this group (M3 §3.2). null = physical (no element).
## Each ring may carry its own element (inner fire, outer physical is valid).
@export var element : ElementDef = null

# POST-M3: push_force, flags, delay_turns
