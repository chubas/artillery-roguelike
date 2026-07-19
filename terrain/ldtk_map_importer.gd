# Raw LDtk JSON -> typed MapDefinition compiler (M48). This class has no editor or filesystem
# output policy; the headless wrapper owns generated-file writes.
class_name LdtkMapImporter
extends RefCounted

const SUPPORTED_JSON_PREFIX := "1.5."
const REQUIRED_FIELDS := ["rl_id", "rl_name", "rl_description", "rl_notes"]
const TERRAIN_VALUES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const SPAWN_VALUES := [0, 1, 2, 3, 4]
const PLAYER_ZONE_VALUES := [1, 2]
const ENEMY_ZONE_VALUES := [3, 4]

var error : String = ""


func import_project(path: String) -> Array[MapDefinition]:
	error = ""
	if not FileAccess.file_exists(path):
		return _fail("LDtk project does not exist: %s" % path)

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _fail("LDtk project is empty: %s" % path)
	var text := bytes.get_string_from_utf8()
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return _fail("invalid LDtk JSON at line %d: %s" % [
			parser.get_error_line(), parser.get_error_message()
		])
	if not parser.data is Dictionary:
		return _fail("LDtk root must be a JSON object")
	var document : Dictionary = parser.data

	var json_version = document.get("jsonVersion")
	if not json_version is String or not (json_version as String).begins_with(SUPPORTED_JSON_PREFIX):
		return _fail("unsupported LDtk jsonVersion %s (expected %s*)" % [
			str(json_version), SUPPORTED_JSON_PREFIX
		])
	if document.get("externalLevels", false) == true:
		return _fail("external LDtk levels are not supported in M48")

	var levels = document.get("levels")
	if not levels is Array or levels.is_empty():
		return _fail("LDtk project contains no embedded levels")

	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var source_hash : String = hashing.finish().hex_encode()
	var source_project := path.get_file()
	var maps : Array[MapDefinition] = []
	var seen_ids : Dictionary = {}
	for level_index in range(levels.size()):
		if not levels[level_index] is Dictionary:
			return _fail("level %d must be an object" % level_index)
		var map := _parse_level(
				levels[level_index], level_index, source_project, source_hash)
		if map == null:
			return []
		if seen_ids.has(map.id):
			return _fail("duplicate rl_id '%s'" % map.id)
		seen_ids[map.id] = true
		maps.append(map)

	maps.sort_custom(func(a: MapDefinition, b: MapDefinition) -> bool: return a.id < b.id)
	return maps


func _parse_level(
		level: Dictionary, level_index: int, source_project: String, source_hash: String
) -> MapDefinition:
	var label := str(level.get("identifier", "level %d" % level_index))
	var fields := _field_values(level.get("fieldInstances"), "%s fieldInstances" % label)
	if error != "":
		return null
	for required in REQUIRED_FIELDS:
		if not fields.has(required) or not fields[required] is String:
			_set_error("%s: missing or invalid String field '%s'" % [label, required])
			return null

	var map_id : String = fields["rl_id"]
	if map_id == "" or not map_id.is_valid_identifier():
		_set_error("%s: rl_id must be a non-empty identifier" % label)
		return null

	var map := MapDefinition.new()
	map.id = map_id
	map.title = fields["rl_name"]
	map.description = fields["rl_description"]
	map.notes = fields["rl_notes"]
	map.source_project = source_project
	map.source_level_iid = str(level.get("iid", ""))
	map.source_hash = source_hash
	if map.source_level_iid == "":
		_set_error("%s: missing level iid" % label)
		return null

	if fields.has("rl_pool"):
		if not fields["rl_pool"] is bool:
			_set_error("%s: rl_pool must be a Bool" % label)
			return null
		map.pool = fields["rl_pool"]

	if fields.has("autoFillTerrain"):
		if not fields["autoFillTerrain"] is bool:
			_set_error("%s: autoFillTerrain must be a Bool" % label)
			return null
		map.auto_fill_terrain = fields["autoFillTerrain"]
	if fields.has("autoFillTerrainValues") and fields["autoFillTerrainValues"] != "":
		if not _parse_auto_fill(fields["autoFillTerrainValues"], map, label):
			return null
	if map.auto_fill_terrain and (map.auto_fill_min == 0 or map.auto_fill_max == 0):
		_set_error("%s: autoFillTerrain requires autoFillTerrainValues" % label)
		return null

	var layer_instances = level.get("layerInstances")
	if not layer_instances is Array:
		_set_error("%s: layerInstances must be an array" % label)
		return null
	var terrain_layer := _find_layer(layer_instances, "Terrain")
	var spawn_layer := _find_layer(layer_instances, "SpawnZones")
	if terrain_layer.is_empty():
		_set_error("%s: missing Terrain IntGrid layer" % label)
		return null
	if spawn_layer.is_empty():
		_set_error("%s: missing SpawnZones IntGrid layer" % label)
		return null
	if terrain_layer.get("__type") != "IntGrid" or spawn_layer.get("__type") != "IntGrid":
		_set_error("%s: Terrain and SpawnZones must be IntGrid layers" % label)
		return null

	map.width = _json_int(terrain_layer.get("__cWid"), "%s Terrain width" % label)
	map.height = _json_int(terrain_layer.get("__cHei"), "%s Terrain height" % label)
	var terrain_grid_size := _json_int(
			terrain_layer.get("__gridSize"), "%s Terrain grid size" % label)
	var spawn_width := _json_int(spawn_layer.get("__cWid"), "%s SpawnZones width" % label)
	var spawn_height := _json_int(spawn_layer.get("__cHei"), "%s SpawnZones height" % label)
	var spawn_grid_size := _json_int(
			spawn_layer.get("__gridSize"), "%s SpawnZones grid size" % label)
	if error != "":
		return null
	if map.width <= 0 or map.height <= 0 or terrain_grid_size <= 0:
		_set_error("%s: IntGrid dimensions and grid size must be positive" % label)
		return null
	if spawn_width != map.width or spawn_height != map.height \
			or spawn_grid_size != terrain_grid_size:
		_set_error("%s: Terrain and SpawnZones dimensions/grid sizes differ" % label)
		return null

	var terrain := _parse_flat_grid(
			terrain_layer.get("intGridCsv"), map.width, map.height,
			TERRAIN_VALUES, "%s Terrain" % label)
	if error != "":
		return null
	map.terrain_values = terrain
	var spawn_grid := _parse_flat_grid(
			spawn_layer.get("intGridCsv"), map.width, map.height,
			SPAWN_VALUES, "%s SpawnZones" % label)
	if error != "":
		return null

	map.spawn_zones = _rectangles_for_values(
			spawn_grid, map.width, map.height, PLAYER_ZONE_VALUES)
	map.enemy_zones = _rectangles_for_values(
			spawn_grid, map.width, map.height, ENEMY_ZONE_VALUES)
	if map.spawn_zones.is_empty():
		_set_error("%s: SpawnZones contains no player zones (values 1 or 2)" % label)
		return null
	if map.enemy_zones.is_empty():
		_set_error("%s: SpawnZones contains no enemy zones (values 3 or 4)" % label)
		return null

	map.entities = _parse_entities(layer_instances, map.width, map.height, label)
	if error != "":
		return null
	return map


func _field_values(raw_fields: Variant, context: String) -> Dictionary:
	var values : Dictionary = {}
	if not raw_fields is Array:
		_set_error("%s must be an array" % context)
		return values
	for raw_field in raw_fields:
		if not raw_field is Dictionary:
			_set_error("%s entries must be objects" % context)
			return {}
		var identifier = raw_field.get("__identifier")
		if not identifier is String or identifier == "":
			_set_error("%s entry has no identifier" % context)
			return {}
		values[identifier] = raw_field.get("__value")
	return values


func _parse_auto_fill(raw_value: Variant, map: MapDefinition, label: String) -> bool:
	var values = raw_value
	if raw_value is String:
		var parser := JSON.new()
		if parser.parse(raw_value) != OK:
			_set_error("%s: autoFillTerrainValues must be JSON [N, M]" % label)
			return false
		values = parser.data
	if not values is Array or values.size() != 2:
		_set_error("%s: autoFillTerrainValues must be [N, M]" % label)
		return false
	map.auto_fill_min = _json_int(values[0], "%s auto-fill minimum" % label)
	map.auto_fill_max = _json_int(values[1], "%s auto-fill maximum" % label)
	if error != "":
		return false
	if map.auto_fill_min < 1 or map.auto_fill_max > 9 \
			or map.auto_fill_min > map.auto_fill_max:
		_set_error("%s: auto-fill range must satisfy 1 <= N <= M <= 9" % label)
		return false
	return true


func _find_layer(layers: Array, identifier: String) -> Dictionary:
	for raw_layer in layers:
		if raw_layer is Dictionary and raw_layer.get("__identifier") == identifier:
			return raw_layer
	return {}


func _parse_flat_grid(
		raw_grid: Variant, width: int, height: int, allowed_values: Array, context: String
) -> PackedByteArray:
	var result := PackedByteArray()
	if not raw_grid is Array:
		_set_error("%s intGridCsv must be an array" % context)
		return result
	if raw_grid.size() != width * height:
		_set_error("%s intGridCsv has %d values; expected %d" % [
			context, raw_grid.size(), width * height
		])
		return result
	result.resize(raw_grid.size())
	for index in range(raw_grid.size()):
		var value := _json_int(raw_grid[index], "%s value %d" % [context, index])
		if error != "":
			return PackedByteArray()
		if not allowed_values.has(value):
			_set_error("%s contains unsupported value %d at index %d" % [
				context, value, index
			])
			return PackedByteArray()
		result[index] = value
	return result


func _rectangles_for_values(
		grid: PackedByteArray, width: int, height: int, values: Array
) -> Array[Rect2i]:
	var rectangles : Array[Rect2i] = []
	for value in values:
		rectangles.append_array(_rectangles_for_value(grid, width, height, value))
	return rectangles


func _rectangles_for_value(
		grid: PackedByteArray, width: int, height: int, value: int
) -> Array[Rect2i]:
	var completed : Array[Rect2i] = []
	var active : Dictionary = {} # "x0:x1" -> Rect2i
	for y in range(height):
		var runs := _horizontal_runs(grid, width, y, value)
		var run_keys : Dictionary = {}
		for run in runs:
			run_keys[_run_key(run.x, run.y)] = run
		for key in active.keys():
			if not run_keys.has(key):
				completed.append(active[key])
		var next_active : Dictionary = {}
		for key in run_keys:
			var run : Vector2i = run_keys[key]
			if active.has(key):
				var rect : Rect2i = active[key]
				rect.size.y += 1
				next_active[key] = rect
			else:
				next_active[key] = Rect2i(run.x, y, run.y - run.x + 1, 1)
		active = next_active
	for key in active:
		completed.append(active[key])
	completed.sort_custom(_rect_less)
	return completed


func _horizontal_runs(
		grid: PackedByteArray, width: int, y: int, value: int
) -> Array[Vector2i]:
	var runs : Array[Vector2i] = []
	var start := -1
	for x in range(width):
		if grid[y * width + x] == value and start == -1:
			start = x
		elif grid[y * width + x] != value and start != -1:
			runs.append(Vector2i(start, x - 1))
			start = -1
	if start != -1:
		runs.append(Vector2i(start, width - 1))
	return runs


func _run_key(x0: int, x1: int) -> String:
	return "%d:%d" % [x0, x1]


func _rect_less(a: Rect2i, b: Rect2i) -> bool:
	if a.position.y != b.position.y:
		return a.position.y < b.position.y
	if a.position.x != b.position.x:
		return a.position.x < b.position.x
	if a.end.y != b.end.y:
		return a.end.y < b.end.y
	return a.end.x < b.end.x


func _parse_entities(
		layers: Array, width: int, height: int, label: String
) -> Array[MapEntity]:
	var entities : Array[MapEntity] = []
	for raw_layer in layers:
		if not raw_layer is Dictionary or raw_layer.get("__type") != "Entities":
			continue
		var layer_name := str(raw_layer.get("__identifier", ""))
		var instances = raw_layer.get("entityInstances")
		if not instances is Array:
			_set_error("%s: entity layer '%s' has invalid entityInstances" % [
				label, layer_name
			])
			return []
		for raw_instance in instances:
			if not raw_instance is Dictionary:
				_set_error("%s: entity in layer '%s' must be an object" % [
					label, layer_name
				])
				return []
			var entity := MapEntity.new()
			entity.name = str(raw_instance.get("__identifier", ""))
			entity.iid = str(raw_instance.get("iid", ""))
			entity.source_layer = layer_name
			if entity.name == "" or entity.iid == "":
				_set_error("%s: entity in layer '%s' is missing identifier/iid" % [
					label, layer_name
				])
				return []
			var grid_position = raw_instance.get("__grid")
			if not grid_position is Array or grid_position.size() != 2:
				_set_error("%s: entity '%s' is missing __grid [x, y]" % [
					label, entity.name
				])
				return []
			entity.coordinates = Vector2i(
					_json_int(grid_position[0], "%s %s grid x" % [label, entity.name]),
					_json_int(grid_position[1], "%s %s grid y" % [label, entity.name]))
			if error != "":
				return []
			if entity.coordinates.x < 0 or entity.coordinates.x >= width \
					or entity.coordinates.y < 0 or entity.coordinates.y >= height:
				_set_error("%s: entity '%s' at %s is outside %dx%d" % [
					label, entity.name, str(entity.coordinates), width, height
				])
				return []
			entity.props = _field_values(
					raw_instance.get("fieldInstances", []),
					"%s entity '%s' fields" % [label, entity.name])
			if error != "":
				return []
			entities.append(entity)
	return entities


func _json_int(value: Variant, context: String) -> int:
	if not (value is int or value is float) or float(value) != floorf(float(value)):
		_set_error("%s must be an integer" % context)
		return 0
	return int(value)


func _fail(message: String) -> Array[MapDefinition]:
	_set_error(message)
	return []


func _set_error(message: String) -> void:
	if error == "":
		error = message
