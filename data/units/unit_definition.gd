# Data definition of a unit type (M2 spec §2.4).
class_name UnitDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Unit"

## Faction tag (M18): stable id from Faction.* — neutral or army/cell/bio. Drives reward pools
## and run identity; no gameplay filtering yet.
@export var faction : String = Faction.NEUTRAL

## Physical footprint (voxels)
@export var width_voxels : int = 2
@export var height_voxels : int = 3

## Stats
@export var max_hp : int = 6
## Starting armor points each combat (M20). Combat-runtime pool; restored from this on spawn.
@export var base_armor : int = 0
@export var move_range : int = 99  # max moves per activation (use 99 = unlimited for now)
@export var weight : int = 2       # 0=weightless, 1=light, 2=medium, 3=heavy

## Card base power (M39/M40): the unit's printed damage output, shown on the card / logbook.
## The base that PowerCalculator folds source-attributed PowerMods over — there is no separate
## flat `attack` stat anymore. Multishot units (Cluster, Splitter) carry a low base_power (1.0).
##
## Default 0.0 is an INVALID sentinel meaning "not authored": every unit must set a positive
## base_power explicitly. The bake validates this (see bake_resources `_validate_unit_definitions`)
## and fails the build if any unit definition is left at 0.
@export var base_power : float = 0.0

## Base dig value (M16): terrain-only blast strength before shot.dig_mult. Does not scale
## with power; decoupled from attack so late-game damage does not dissolve the battlefield.
@export var dig : int = 1

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

## Keyword ids this unit always has (M41). Resolved to descriptions via KeywordRegistry for
## hover tooltips. Distinct from `tags` (structural) — keywords are named mechanics.
@export var keywords : Array[String] = []

## Per-element damage multiplier overrides. Key = element id, value = multiplier.
## Missing element id defaults to 1.0. Takes precedence over tag rules.
## Example: { "fire": 1.5, "electric": 0.5 }
@export var element_affinities : Dictionary = {}

## Prototype visuals (replaced by sprites post-M2)
@export var color : Color = Color(0.5, 0.5, 0.5)

@export var capacity_cost : int = 2
@export var rarity : String = Rarity.COMMON
