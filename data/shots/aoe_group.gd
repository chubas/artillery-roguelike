# One set of voxel offsets sharing the same strength zone (M7: zones replace baked damage).
# (0,0) is always the impact voxel.
class_name AoEGroup
extends Resource

## Voxel offsets from impact point (col_delta, row_delta).
@export var offsets : Array[Vector2i] = []

## Strength multiplier for this zone (core = 1.0, edge = 0.5, more zones possible later).
## Final damage = source strength * multiplier, computed by AoEResolver.
@export var multiplier : float = 1.0

## Element carried by this group (M3 §3.2). null = physical (no element).
## Each ring may carry its own element (inner fire, outer physical is valid).
@export var element : ElementDef = null

# POST-M3: push_force, flags, delay_turns
