# Hand-authored ASCII map (M44). Parsed from a plain-text file: `key: value` metadata lines,
# then a `data:` line followed by exactly `height` grid rows (row 0 = top of map).
# Grid chars: '.' void · '1'-'9' SOLID with that hp (FLAMMABLE) · '0' SOLID
# indestructible · 'M' MINERAL (hp 2). Spawn/enemy zones are [x0, y0, x1, y1] voxel rects
# (inclusive corners). Any problem sets `error` — callers must check it before using the map.
#
# Collapse: imported tiles are NON-collapsible (`collapsible = false`) — matching M17's opt-in
# design (the generator defaults false too). So floating platforms stay put when part of them is
# destroyed; nothing falls under gravity. There is no per-tile opt-in to collapse yet — add a tag
# here if undermine-and-drop terrain is wanted later.
#
# M46 auto-fill: `autoFillTerrain: true` + `autoFillTerrainValues: [N, M]` (1 ≤ N ≤ M ≤ 9)
# replaces every '1' with a durability sampled from N..M via seeded Simplex noise (smooth
# patches, not speckle). Explicit digits 2-9 / '0' / 'M' remain authorial overrides.
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
var entities     : Dictionary = {}      # entity name -> MapEntity (M47)
# M47: whether this map is eligible for the random run pool. Boss/special maps set `pool: false`
# so they never appear on a normal combat node; the sandbox dropdown still lists them.
var pool        : bool = true
# M46: noise-fill '1' tiles with durability auto_fill_min..auto_fill_max (inclusive).
# min/max default 0 = "not provided" sentinel; validation requires them when the flag is on.
var auto_fill_terrain : bool = false
var auto_fill_min     : int = 0
var auto_fill_max     : int = 0
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
			"autoFillTerrain": map.auto_fill_terrain = value.to_lower() == "true"
			"autoFillTerrainValues": _parse_fill_values(value, map)
			"pool":        map.pool = value.to_lower() != "false"
			_:
				if key.begins_with("Entity_"):
					var entity_name := key.trim_prefix("Entity_")
					if entity_name == "":
						map.error = "line %d: entity name cannot be empty" % i
					elif map.entities.has(entity_name):
						map.error = "line %d: duplicate entity '%s'" % [i, entity_name]
					else:
						map.entities[entity_name] = _parse_entity(entity_name, value, map, key)
				else:
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
	elif map.auto_fill_terrain and (map.auto_fill_min < 1 or map.auto_fill_max > 9 \
			or map.auto_fill_min > map.auto_fill_max):
		map.error = "autoFillTerrain requires autoFillTerrainValues: [N, M] with 1 <= N <= M <= 9"
	else:
		for zone in map.spawn_zones + map.enemy_zones:
			var z : Rect2i = zone
			if z.position.x < 0 or z.position.y < 0 \
					or z.end.x > map.width or z.end.y > map.height:
				map.error = "zone %s out of bounds (%dx%d)" % [str(z), map.width, map.height]
				break
		if map.error == "":
			for entity_name in map.entities:
				var position : Vector2i = (map.entities[entity_name] as MapEntity).coordinates
				if position.x < 0 or position.y < 0 \
						or position.x >= map.width or position.y >= map.height:
					map.error = "entity '%s' at %s out of bounds (%dx%d)" % [
						entity_name, str(position), map.width, map.height
					]
					break
	return map

## Dynamic `Entity_<name>: [x, y]` metadata -> MapEntity (M47). For now the value is the `[x, y]`
## coordinate shorthand; richer values (a JSON object of arbitrary props) can be added here later
## without changing callers. Entity semantics (what an entity does) belong to callers.
static func _parse_entity(
		entity_name: String, value: String, map: CustomMap, key: String
) -> MapEntity:
	var e := MapEntity.new()
	e.name = entity_name
	var parsed = JSON.parse_string(value)
	if not parsed is Array or (parsed as Array).size() != 2:
		map.error = "%s: expected [x, y]" % key
		return e
	e.coordinates = Vector2i(int(parsed[0]), int(parsed[1]))
	e.props["coordinates"] = e.coordinates
	return e

## M46: "[N, M]" -> auto_fill_min/max. Range validity is checked in the final validation block.
static func _parse_fill_values(value: String, map: CustomMap) -> void:
	var parsed = JSON.parse_string(value)
	if not parsed is Array or (parsed as Array).size() != 2:
		map.error = "autoFillTerrainValues: expected [N, M]"
		return
	map.auto_fill_min = int(parsed[0])
	map.auto_fill_max = int(parsed[1])

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
## noise_seed drives the M46 auto-fill (0 = derive from the map id, so parse-only callers are
## deterministic); combat passes the per-node stage seed for reproducible per-run variety.
func to_map_data(noise_seed: int = 0) -> MapData:
	var data := MapData.new()
	data.width = width
	data.height = height
	data.cells.resize(width * height)
	data.cells.fill(null)
	# M46: smooth durability patches for '1' tiles — Simplex reads as perlin-style coherent
	# noise, so neighboring tiles get similar durability instead of speckle.
	var noise : FastNoiseLite = null
	if auto_fill_terrain:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.08
		noise.seed = noise_seed if noise_seed != 0 else hash(id)
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
					"collapsible": false, "status_tags": ["MINERAL"],
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
				if noise != null and ch == "1":
					var t := (noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
					hp = mini(auto_fill_min + int(t * float(auto_fill_max - auto_fill_min + 1)),
							auto_fill_max)
				cell = {
					"type": Tile.TileType.SOLID,
					"hp": hp, "max_hp": hp, "flags": 0,
					"collapsible": false, "status_tags": ["FLAMMABLE"],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			data.set_cell(col, row, cell)
	return data
