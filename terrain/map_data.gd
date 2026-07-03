class_name MapData
extends Resource

enum GenOrigin {
	NOISE_FILL = 0, SPAWN_PLATFORM,
	SLOT_LEFT, SLOT_CENTER, SLOT_RIGHT, BACKGROUND, CRYSTAL, SEAM
}

@export var width  : int = 120
@export var height : int = 100
## Flat array size = width*height. null = VOID. Dictionary = tile data.
## Dict keys: type(int), hp(int), max_hp(int), flags(int),
##             collapsible(bool), status_tags(Array), variant(int), gen_origin(int)
@export var cells  : Array = []

## FeatureInstance records exported by the placer pass (M43). Runtime-only — MapData is
## never serialized to disk, so these plain RefCounted objects are safe to carry here.
var features : Array = []

## Generation diagnostics (M43 validation pass): which attempt produced this map and,
## when reroll was exhausted, the last failure reason ("" = validated clean).
var attempts_used      : int = 1
var validation_failure : String = ""

func idx(col: int, row: int) -> int:
	return row * width + col

func get_cell(col: int, row: int) -> Variant:
	if col < 0 or col >= width or row < 0 or row >= height:
		return null
	return cells[idx(col, row)]

func set_cell(col: int, row: int, data: Variant) -> void:
	if col >= 0 and col < width and row >= 0 and row < height:
		cells[idx(col, row)] = data

func place_solid(col: int, row: int, hp: int, flags: int,
		collapsible: bool, tags: Array, origin: int) -> void:
	set_cell(col, row, {
		"type": 0,
		"hp": hp, "max_hp": hp, "flags": flags,
		"collapsible": collapsible,
		"status_tags": tags.duplicate(),
		"variant": 0, "gen_origin": origin
	})
