# Per-tile runtime state for one tile status (M3 spec §5.2). Mutable; references an
# immutable TileStatusDef. Lives in Tile.tile_statuses keyed by status id.
class_name TileStatusInstance
extends RefCounted

var definition : TileStatusDef
var turns_left : int

func _init(def: TileStatusDef) -> void:
	definition = def
	turns_left = def.duration

func tick() -> bool:
	turns_left -= 1
	return turns_left <= 0
