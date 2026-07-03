# Crystal deposit (v0.2 §8.9): "resources are buried here — worth reaching?"
# Background feature: ignores its slot column and seeds a small CRYSTAL-tagged vein in the
# left-center zone at a depth band, reachable by digging from the player's side.
# Anchor: vein_center. (Ambient MINERAL scatter from M42 is separate; this is the authored
# vein for profile-driven deposits.)
class_name CrystalPlacer
extends FeaturePlacer

func place(data: MapData, _slot_col: int, def: FeatureDefinition,
		rng: RandomNumberGenerator, instance_id: String, _origin: int) -> FeatureInstance:
	var tile_count := rng.randi_range(3, 8)
	var vein_col := rng.randi_range(int(data.width * 0.10), int(data.width * 0.40))
	var vein_row := rng.randi_range(def.height_min, mini(def.height_max, data.height - 2))

	var placed := 0
	for _i in range(tile_count):
		var col := vein_col + rng.randi_range(-2, 2)
		var row := vein_row + rng.randi_range(-1, 1)
		if col < 0 or col >= data.width or row < 0 or row >= data.height:
			continue
		data.set_cell(col, row, {
			"type": 0,
			"hp": 5, "max_hp": 5, "flags": 0,
			"collapsible": true, "status_tags": ["CRYSTAL"],
			"variant": 0, "gen_origin": MapData.GenOrigin.CRYSTAL
		})
		placed += 1

	var inst := make_instance(instance_id, def.type,
			Rect2i(vein_col - 2, vein_row - 1, 5, 3))
	inst.anchors["vein_center"] = Vector2i(vein_col, vein_row)
	return inst

func validate(data: MapData, inst: FeatureInstance) -> String:
	var f := inst.footprint
	for col in range(maxi(f.position.x, 0), mini(f.end.x, data.width)):
		for row in range(maxi(f.position.y, 0), mini(f.end.y, data.height)):
			var cell = data.get_cell(col, row)
			if cell != null and (cell.get("status_tags", []) as Array).has("CRYSTAL"):
				return ""
	return "%s: no crystal tiles placed" % inst.id
