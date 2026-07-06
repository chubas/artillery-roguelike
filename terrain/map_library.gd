# Loader for hand-authored ASCII maps (M44). Scans `res://data/maps/*.txt` plus
# `user://maps/*.txt` — drop a file in the user directory and it appears without touching the
# project; a user:// map with the same id overrides the res:// one. Lazy cache; call reload()
# to rescan (the sandbox does this when opening its Map dropdown).
#
# Export note: plain .txt under res:// needs an export include filter (*.txt) once the project
# gets an export preset — none exists yet.
class_name MapLibrary

const DIRS := ["res://data/maps/", "user://maps/"]

static var _cache : Dictionary = {}   # id -> CustomMap
static var _loaded := false

static func reload() -> void:
	_cache.clear()
	for dir in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for fname in DirAccess.get_files_at(dir):
			if not fname.ends_with(".txt"):
				continue
			var text := FileAccess.get_file_as_string(dir + fname)
			var map := CustomMap.parse(text)
			if map.error != "":
				push_warning("MapLibrary: %s%s failed to parse: %s" % [dir, fname, map.error])
				continue
			_cache[map.id] = map   # later dirs (user://) override earlier ids
	_loaded = true

static func map_ids() -> Array:
	if not _loaded:
		reload()
	var ids := _cache.keys()
	ids.sort()
	return ids

static func get_map(id: String) -> CustomMap:
	if not _loaded:
		reload()
	return _cache.get(id, null)
