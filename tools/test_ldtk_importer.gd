# Headless unit + actual-project parity checks for M48.
extends SceneTree

const FIXTURE_PATH := "user://m48_ldtk_fixture.json"

var _failures := 0


func _initialize() -> void:
	_test_valid_fixture()
	_test_validation_failures()
	_test_actual_project()
	DirAccess.remove_absolute(FIXTURE_PATH)
	if _failures == 0:
		print("M48 importer tests: PASS")
		quit(0)
	else:
		push_error("M48 importer tests: %d failure(s)" % _failures)
		quit(1)


func _test_valid_fixture() -> void:
	var project := _fixture_project()
	var maps := _import_document(project)
	_check(maps.size() == 1, "valid fixture imports one map")
	if maps.is_empty():
		return
	var map : MapDefinition = maps[0]
	_check(map.id == "fixture", "rl_id imported")
	_check(map.width == 4 and map.height == 3, "IntGrid dimensions imported")
	_check(map.terrain_values == PackedByteArray([
		0, 1, 10, 11,
		2, 3, 4, 5,
		6, 7, 8, 9,
	]), "Terrain intGridCsv preserved")
	_check(map.spawn_zones == [Rect2i(0, 0, 2, 1)], "player zone cover imported")
	_check(map.enemy_zones == [Rect2i(2, 2, 2, 1)], "enemy zone cover imported")
	_check(not map.pool, "rl_pool imported")
	_check(map.auto_fill_terrain and map.auto_fill_min == 2 and map.auto_fill_max == 5,
			"auto-fill fields imported")
	_check(map.entities.size() == 2, "duplicate entity identifiers are preserved as instances")
	if map.entities.size() == 2:
		_check(map.entities[0].name == "Marker"
				and map.entities[0].coordinates == Vector2i(1, 1),
				"entity identity and __grid imported")
		_check(map.entities[0].props.get("kind") == "alpha",
				"entity custom fields preserved")


func _test_validation_failures() -> void:
	var external := _fixture_project()
	external["externalLevels"] = true
	_expect_error(external, "external LDtk levels", "external levels rejected")

	var missing_layer := _fixture_project()
	missing_layer["levels"][0]["layerInstances"].remove_at(1)
	_expect_error(missing_layer, "missing SpawnZones", "missing layer rejected")

	var short_grid := _fixture_project()
	short_grid["levels"][0]["layerInstances"][0]["intGridCsv"].pop_back()
	_expect_error(short_grid, "expected 12", "incorrect flat grid length rejected")

	var bad_terrain := _fixture_project()
	bad_terrain["levels"][0]["layerInstances"][0]["intGridCsv"][0] = 99
	_expect_error(bad_terrain, "unsupported value 99", "unknown terrain value rejected")

	var reserved_spawn := _fixture_project()
	reserved_spawn["levels"][0]["layerInstances"][1]["intGridCsv"][0] = 5
	_expect_error(reserved_spawn, "unsupported value 5", "reserved spawn value rejected")

	var bad_fill := _fixture_project()
	_set_level_field(bad_fill["levels"][0], "autoFillTerrainValues", "[8, 3]")
	_expect_error(bad_fill, "auto-fill range", "invalid auto-fill range rejected")

	var bad_entity := _fixture_project()
	bad_entity["levels"][0]["layerInstances"][2]["entityInstances"][0]["__grid"] = [9, 9]
	_expect_error(bad_entity, "outside 4x3", "out-of-bounds entity rejected")

	var duplicate := _fixture_project()
	duplicate["levels"].append(duplicate["levels"][0].duplicate(true))
	_expect_error(duplicate, "duplicate rl_id", "duplicate map id rejected")


func _test_actual_project() -> void:
	var source := OS.get_environment("LDTK_PROJECT_PATH")
	_check(source != "", "LDTK_PROJECT_PATH provided for parity test")
	if source == "":
		return
	var importer := LdtkMapImporter.new()
	var maps := importer.import_project(source)
	_check(importer.error == "", "actual LDtk project imports: %s" % importer.error)
	var by_id : Dictionary = {}
	for map in maps:
		by_id[map.id] = map
	_check(by_id.has("hills") and by_id.has("boss1"), "actual project contains Hills and Boss1")
	if not by_id.has("hills") or not by_id.has("boss1"):
		return
	var hills : MapDefinition = by_id["hills"]
	var boss : MapDefinition = by_id["boss1"]
	_check(hills.width == 89 and hills.height == 35, "Hills dimensions match")
	_check(hills.spawn_zones == [Rect2i(8, 2, 30, 28)]
			and hills.enemy_zones == [Rect2i(49, 2, 34, 28)], "Hills zones match")
	_check(boss.width == 126 and boss.height == 56, "Boss1 dimensions match")
	_check(boss.spawn_zones.size() == 4 and boss.enemy_zones.size() == 6,
			"Boss1 zone cover matches")
	_check(not boss.pool, "Boss1 rl_pool is false")
	_check(boss.entities.size() == 1
			and boss.entities[0].name == "Boss1"
			and boss.entities[0].coordinates == Vector2i(61, 22),
			"Boss1 entity matches")


func _fixture_project() -> Dictionary:
	var terrain := [
		0, 1, 10, 11,
		2, 3, 4, 5,
		6, 7, 8, 9,
	]
	var spawn := [
		1, 1, 0, 0,
		0, 0, 0, 0,
		0, 0, 3, 3,
	]
	var entity_a := {
		"__identifier": "Marker", "iid": "entity-a", "__grid": [1, 1],
		"fieldInstances": [
			{"__identifier": "kind", "__value": "alpha"},
		],
	}
	var entity_b := {
		"__identifier": "Marker", "iid": "entity-b", "__grid": [2, 1],
		"fieldInstances": [],
	}
	return {
		"jsonVersion": "1.5.3",
		"externalLevels": false,
		"levels": [{
			"identifier": "Fixture",
			"iid": "fixture-level",
			"fieldInstances": [
				{"__identifier": "rl_id", "__value": "fixture"},
				{"__identifier": "rl_name", "__value": "Fixture"},
				{"__identifier": "rl_description", "__value": "Importer fixture"},
				{"__identifier": "rl_notes", "__value": ""},
				{"__identifier": "rl_pool", "__value": false},
				{"__identifier": "autoFillTerrain", "__value": true},
				{"__identifier": "autoFillTerrainValues", "__value": "[2, 5]"},
			],
			"layerInstances": [
				{"__identifier": "Terrain", "__type": "IntGrid",
					"__cWid": 4, "__cHei": 3, "__gridSize": 16, "intGridCsv": terrain},
				{"__identifier": "SpawnZones", "__type": "IntGrid",
					"__cWid": 4, "__cHei": 3, "__gridSize": 16, "intGridCsv": spawn},
				{"__identifier": "MapDefinitions", "__type": "Entities",
					"entityInstances": [entity_a, entity_b]},
			],
		}],
	}


func _set_level_field(level: Dictionary, identifier: String, value: Variant) -> void:
	for field in level["fieldInstances"]:
		if field["__identifier"] == identifier:
			field["__value"] = value
			return


func _import_document(document: Dictionary) -> Array[MapDefinition]:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	var importer := LdtkMapImporter.new()
	var maps := importer.import_project(FIXTURE_PATH)
	if importer.error != "":
		_check(false, "unexpected import error: %s" % importer.error)
	return maps


func _expect_error(document: Dictionary, fragment: String, label: String) -> void:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	var importer := LdtkMapImporter.new()
	importer.import_project(FIXTURE_PATH)
	_check(fragment in importer.error, "%s (got: %s)" % [label, importer.error])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		_failures += 1
		push_error("  FAIL: %s" % label)
