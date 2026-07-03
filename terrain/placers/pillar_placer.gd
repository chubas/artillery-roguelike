# Isolated pillar (v0.2 §8.8): "elevation advantage is available but exposed."
# Narrow elevated block (indestructible base, carveable top) isolated from the ground by
# carved gaps wider than any climb range on both sides. Edges: GAP (the carved bands are
# gap_rects the seam/validation passes keep clear). Anchor: top_center.
class_name PillarPlacer
extends FeaturePlacer

func place(data: MapData, slot_col: int, def: FeatureDefinition,
		rng: RandomNumberGenerator, instance_id: String, origin: int) -> FeatureInstance:
	var pw   := rng.randi_range(def.width_min,  def.width_max)
	var ph   := rng.randi_range(def.height_min, def.height_max)
	# Isolation must exceed the best climb range (light units: max_climb 3).
	var gap  : int = maxi(def.special_params.get("gap_from_terrain", 8), 4)
	var surf := surface_row(data, slot_col)
	var top_row  := maxi(surf - ph, 0)
	var base_row := top_row + int(ph * 0.40)
	var base_col := slot_col - pw / 2
	var carve_top := maxi(surf - ph - 2, 0)

	# Carve isolation gaps on both sides (down to just below the local surface)
	var gap_rects : Array = []
	for side_range in [range(base_col - gap, base_col), range(base_col + pw, base_col + pw + gap)]:
		for col in side_range:
			if col < 0 or col >= data.width:
				continue
			for row in range(carve_top, surf + 1):
				if row >= 0 and row < data.height:
					data.set_cell(col, row, null)
	gap_rects.append(Rect2i(base_col - gap, carve_top, gap, surf + 1 - carve_top))
	gap_rects.append(Rect2i(base_col + pw, carve_top, gap, surf + 1 - carve_top))

	# Pillar block (fill to the map floor so the pillar itself is grounded)
	for col in range(base_col, base_col + pw):
		if col < 0 or col >= data.width:
			continue
		for row in range(top_row, surface_row(data, col) + 1):
			if row < 0 or row >= data.height:
				continue
			if row >= base_row:
				data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE, false, [], origin)
			else:
				data.place_solid(col, row, 3, 0, true, ["FLAMMABLE"], origin)

	var inst := make_instance(instance_id, def.type,
			Rect2i(base_col - gap, carve_top, pw + gap * 2, surf + 1 - carve_top))
	inst.anchors["top_center"] = Vector2i(slot_col, top_row - 1)
	inst.edge_specs = { "left": FeatureInstance.EdgeType.GAP,
			"right": FeatureInstance.EdgeType.GAP }
	inst.gap_rects = gap_rects
	return inst

func validate(data: MapData, inst: FeatureInstance) -> String:
	var top : Vector2i = inst.anchor("top_center")
	if not is_open(data, top.x, top.y) or data.get_cell(top.x, top.y + 1) == null:
		return "%s: top not standable" % inst.id
	for rect in inst.gap_rects:
		var r : Rect2i = rect
		for col in range(maxi(r.position.x, 0), mini(r.end.x, data.width)):
			for row in range(maxi(r.position.y, 0), mini(r.end.y, data.height)):
				if data.get_cell(col, row) != null:
					return "%s: isolation gap filled at (%d,%d)" % [inst.id, col, row]
	return ""
