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
@export var move_range : int = 99  # max moves per activation (use 99 = unlimited for now)
@export var climb_max : int = 1    # max voxel height climbed free

## Multiplies every shot's strength when this unit fires (M7). 1.0 = no change;
## future upgrades scale Unit.power at runtime without touching any AoE pattern.
@export var base_power : float = 1.0

## Firing
@export var default_shot : ShotDefinition = null
## All shots this unit may select before firing (M3 §8). default_shot is the always-free
## fallback; elemental shells cost action points. Empty = only default_shot available.
@export var available_shots : Array[ShotDefinition] = []
@export var barrel_offset : Vector2i = Vector2i(0, -1)
	# offset in voxels from unit top-center to barrel origin

## Structural tags used by element and keyword systems (M3 §3.3).
## Valid values: ORGANIC, MECHANICAL, SHIELDED, HEAVY, FLYING
@export var tags : Array[String] = []

## Per-element damage multiplier overrides. Key = element id, value = multiplier.
## Missing element id defaults to 1.0. Takes precedence over tag rules.
## Example: { "fire": 1.5, "electric": 0.5 }
@export var element_affinities : Dictionary = {}

## Prototype visuals (replaced by sprites post-M2)
@export var color : Color = Color(0.5, 0.5, 0.5)

# POST-M3: capacity_cost, action_points, upgrade slots, race, mount type
