# Loader for generated LDtk MapDefinition resources (M48). Lazy cache; call reload() after running
# the importer so sandbox/editor sessions replace ResourceLoader's cached definitions.
class_name MapLibrary

const DIR := "res://data/maps/"

static var _cache : Dictionary = {}   # id -> MapDefinition
static var _loaded := false

static func reload() -> void:
	_cache.clear()
	if not DirAccess.dir_exists_absolute(DIR):
		_loaded = true
		return
	for fname in DirAccess.get_files_at(DIR):
		if not fname.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(
				DIR + fname, "", ResourceLoader.CACHE_MODE_REPLACE)
		if not resource is MapDefinition:
			push_warning("MapLibrary: %s%s is not a MapDefinition" % [DIR, fname])
			continue
		var map : MapDefinition = resource
		if map.id == "":
			push_warning("MapLibrary: %s%s has no id" % [DIR, fname])
			continue
		if _cache.has(map.id):
			push_warning("MapLibrary: duplicate map id '%s' in %s" % [map.id, fname])
			continue
		_cache[map.id] = map
	_loaded = true

static func map_ids() -> Array:
	if not _loaded:
		reload()
	var ids := _cache.keys()
	ids.sort()
	return ids

## M47: ids eligible for the random run pool (excludes `pool: false` maps, e.g. boss arenas).
## The sandbox dropdown still uses map_ids() so every authored map remains loadable there.
static func pool_map_ids() -> Array:
	var ids : Array = []
	for id in map_ids():
		var m : MapDefinition = _cache[id]
		if m.pool:
			ids.append(id)
	return ids

static func get_map(id: String) -> MapDefinition:
	if not _loaded:
		reload()
	return _cache.get(id, null)
