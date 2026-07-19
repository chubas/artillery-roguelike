# Headless M48 entry point. Reads raw LDtk from LDTK_PROJECT_PATH and generates typed maps.
extends SceneTree

const SOURCE_ENV := "LDTK_PROJECT_PATH"
const OUTPUT_DIR := "res://data/maps/"


func _initialize() -> void:
	var source_path := OS.get_environment(SOURCE_ENV)
	if source_path == "":
		_fail("set %s to the absolute path of an LDtk project" % SOURCE_ENV)
		return
	if not source_path.is_absolute_path():
		_fail("%s must be an absolute path" % SOURCE_ENV)
		return

	var importer := LdtkMapImporter.new()
	var maps := importer.import_project(source_path)
	if importer.error != "":
		_fail(importer.error)
		return

	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if mkdir_error != OK:
		_fail("cannot create output directory %s (error %d)" % [
			output_absolute, mkdir_error
		])
		return

	var expected_files : Dictionary = {}
	for map in maps:
		var filename := "%s.tres" % map.id
		expected_files[filename] = true
		var destination := OUTPUT_DIR + filename
		var save_error := ResourceSaver.save(
				map, destination,
				ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_RELATIVE_PATHS)
		if save_error != OK:
			_fail("cannot save %s (error %d)" % [destination, save_error])
			return
		print("Imported %s -> %s (%dx%d, %d entities)" % [
			map.id, destination, map.width, map.height, map.entities.size()
		])

	if not _remove_stale_generated(source_path.get_file(), expected_files):
		return
	print("LDtk import complete: %d map(s)." % maps.size())
	quit(0)


func _remove_stale_generated(
		source_project: String, expected_files: Dictionary
) -> bool:
	for filename in DirAccess.get_files_at(OUTPUT_DIR):
		if not filename.ends_with(".tres") or expected_files.has(filename):
			continue
		var resource = ResourceLoader.load(OUTPUT_DIR + filename)
		if resource is MapDefinition and resource.source_project == source_project:
			var remove_error := DirAccess.remove_absolute(
					ProjectSettings.globalize_path(OUTPUT_DIR + filename))
			if remove_error != OK:
				_fail("cannot remove stale generated map %s (error %d)" % [
					filename, remove_error
				])
				return false
			print("Removed stale generated map %s" % filename)
	return true


func _fail(message: String) -> void:
	push_error("LDtk import failed: %s" % message)
	quit(1)
