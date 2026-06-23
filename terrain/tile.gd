# Per-voxel data object (terrain spec §4.1). VOID voxels are null in the grid — no Tile.
class_name Tile

enum TileType { SOLID, RUBBLE, LIQUID, LAVA }      # LAVA: visual-only, no mechanics (M33)
enum Element  { NONE, FIRE, ELECTRIC, EXPLOSIVE, CORROSIVE }  # schema only in M1

# Flags bitmask (terrain spec §4.2) — none are set on any tile in M1.
const FLAG_CLIMBABLE     : int = 1 << 0
const FLAG_LOS_CLEAR     : int = 1 << 1
const FLAG_CONDUCTIVE    : int = 1 << 2
const FLAG_EXPLOSIVE     : int = 1 << 3
const FLAG_INDESTRUCTIBLE: int = 1 << 4
const FLAG_PASSABLE      : int = 1 << 5
const FLAG_SLOWING       : int = 1 << 6

var type    : TileType = TileType.SOLID
var hp      : int      = 3
var max_hp  : int      = 3
var element : Element  = Element.NONE
var flags   : int      = 0
var variant : int      = 0   # visual variant 0–3; cosmetic only

## Whether this tile participates in gravity collapse (M17). Mutable so transmutation
## effects can flip terrain to/from collapsible at runtime. Indestructible tiles never fall.
var collapsible : bool = false

## Active tile status instances (M3 §5.4). Key = status id, value = TileStatusInstance.
var tile_statuses : Dictionary = {}

## String tags for tile-status interaction (FLAMMABLE, CONDUCTIVE, LIQUID, ...).
## DISTINCT from the integer `flags` bitmask: flags govern terrain gameplay (passable,
## climbable, indestructible); status_tags govern status interaction rules (§5.4). Do not merge.
var status_tags : Array[String] = []

func has_flag_tag(tag: String) -> bool:
	return tag in status_tags

# 0 pristine, 1 cracked, 2 heavily damaged — derived, not stored.
func damage_state() -> int:
	if hp >= max_hp:        return 0
	if hp > max_hp * 0.33:  return 1
	return 2

func has_flag(f: int) -> bool:
	return (flags & f) != 0

# Fluent constructor: Tile.new().setup(...)
func setup(t: TileType, hp_val: int, var_idx: int) -> Tile:
	type = t
	hp = hp_val
	max_hp = hp_val
	variant = var_idx
	# Standard solid terrain burns by default (M3 §5.4); generation overrides reinforced
	# (CONDUCTIVE) and the indestructible platform (no tags).
	if t == TileType.SOLID:
		status_tags = ["FLAMMABLE"]
	elif t == TileType.LAVA:
		status_tags = ["LAVA"]
		flags |= FLAG_PASSABLE   # no physics interaction; purely cosmetic
	else:
		status_tags = []
	return self
