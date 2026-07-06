# Hand-authored ASCII map (M44). Parsed from a plain-text file: `key: value` metadata lines,
# then a `data:` line followed by exactly `height` grid rows (row 0 = top of map).
# Grid chars: '.' void · '1'-'9' SOLID with that hp (collapsible, FLAMMABLE) · '0' SOLID
# indestructible · 'M' MINERAL (hp 2). Spawn/enemy zones are [x0, y0, x1, y1] voxel rects
# (inclusive corners). Any problem sets `error` — callers must check it before using the map.
class_name CustomMap
extends RefCounted

var id          : String = ""
var title       : String = ""
var description : String = ""
var notes       : String = ""
var width       : int = 0
var height      : int = 0
var spawn_zones : Array[Rect2i] = []   # player placement zones
var enemy_zones : Array[Rect2i] = []   # enemy/deployable spawn zones
var error       : String = ""          # "" = parsed clean

var _rows : Array = []   # Array[String], one per grid row, padded to width

static func parse(text: String) -> CustomMap:
	var map := CustomMap.new()
	var lines := text.split("\n")
	var i := 0
	# --- Metadata until the `data:` line -------------------------------------
	while i < lines.size():
		var line : String = lines[i].strip_edges()
		i += 1
		if line == "" or line.begins_with("#"):
			continue
		if line == "data:":
			break
		var sep := line.find(":")
		if sep == -1:
			map.error = "line %d: expected 'key: value', got '%s'" % [i, line]
			return map
		var key := line.substr(0, sep).strip_edges()
		var value := line.substr(sep + 1).strip_edges()
		match key:
			"id":          map.id = value
			"title":       map.title = value
			"description": map.description = value
			"notes":       map.notes = value
			"width":       map.width = int(value)
			"height":      map.height = int(value)
			"spawn_zones": map.spawn_zones = _parse_zones(value, map, "spawn_zones")
			"enemy_zones": map.enemy_zones = _parse_zones(value, map, "enemy_zones")
			_:
				map.error = "line %d: unknown key '%s'" % [i, key]
		if map.error != "":
			return map
	# --- Grid rows -------------------------------------------------------------
	if map.width <= 0 or map.height <= 0:
		map.error = "missing or invalid width/height"
		return map
	while i < lines.size() and map._rows.size() < map.height:
		var row : String = lines[i].trim_suffix("\r")
		i += 1
		if row.length() > map.width:
			map.error = "grid row %d: %d chars (width is %d)" % [map._rows.size(), row.length(), map.width]
			return map
		for ch in row:
			if ch != "." and ch != "M" and not (ch >= "0" and ch <= "9"):
				map.error = "grid row %d: unknown char '%s'" % [map._rows.size(), ch]
				return map
		map._rows.append(row.rpad(map.width, "."))
	if map._rows.size() < map.height:
		map.error = "grid has %d rows, expected %d" % [map._rows.size(), map.height]
		return map
	# --- Validation --------------------------------------------------------------
	if map.id == "":
		map.error = "missing id"
	elif map.spawn_zones.is_empty():
		map.error = "no spawn_zones"
	elif map.enemy_zones.is_empty():
		map.error = "no enemy_zones"
	else:
		for zone in map.spawn_zones + map.enemy_zones:
			var z : Rect2i = zone
			if z.position.x < 0 or z.position.y < 0 \
					or z.end.x > map.width or z.end.y > map.height:
				map.error = "zone %s out of bounds (%dx%d)" % [str(z), map.width, map.height]
				break
	return map

## "[[x0, y0, x1, y1], ...]" (inclusive corners) -> Array[Rect2i]. Sets map.error on failure.
static func _parse_zones(value: String, map: CustomMap, key: String) -> Array[Rect2i]:
	var zones : Array[Rect2i] = []
	var parsed = JSON.parse_string(value)
	if not parsed is Array:
		map.error = "%s: not a JSON array" % key
		return zones
	for entry in parsed:
		if not entry is Array or (entry as Array).size() != 4:
			map.error = "%s: each zone needs [x0, y0, x1, y1]" % key
			return zones
		var x0 := int(entry[0]); var y0 := int(entry[1])
		var x1 := int(entry[2]); var y1 := int(entry[3])
		if x1 < x0 or y1 < y0:
			map.error = "%s: corners out of order in %s" % [key, str(entry)]
			return zones
		zones.append(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	return zones

## Build the MapData that TerrainManager.load_map consumes.
func to_map_data() -> MapData:
	var data := MapData.new()
	data.width = width
	data.height = height
	data.cells.resize(width * height)
	data.cells.fill(null)
	for row in range(height):
		var line : String = _rows[row]
		for col in range(width):
			var ch := line[col]
			if ch == ".":
				continue
			var cell : Dictionary
			if ch == "M":
				cell = {
					"type": Tile.TileType.MINERAL,
					"hp": 2, "max_hp": 2, "flags": 0,
					"collapsible": true, "status_tags": ["MINERAL"],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			elif ch == "0":
				cell = {
					"type": Tile.TileType.SOLID,
					"hp": 3, "max_hp": 3, "flags": Tile.FLAG_INDESTRUCTIBLE,
					"collapsible": false, "status_tags": [],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			else:
				var hp := int(ch)
				cell = {
					"type": Tile.TileType.SOLID,
					"hp": hp, "max_hp": hp, "flags": 0,
					"collapsible": true, "status_tags": ["FLAMMABLE"],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			data.set_cell(col, row, cell)
	return data
