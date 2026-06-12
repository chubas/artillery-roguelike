# Per-voxel data object (terrain spec §4.1). VOID voxels are null in the grid — no Tile.
class_name Tile

enum TileType { SOLID, RUBBLE, LIQUID }            # only SOLID active in M1
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
	return self
