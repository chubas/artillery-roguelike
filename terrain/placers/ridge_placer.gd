# Ridge / elevated platform (v0.2 §8.2): "the enemy holds the high ground."
# Indestructible base (bottom 30%), carveable fill (top 70%). Each column fills down to the
# local noise surface, so the ridge merges flush with the ground by construction.
# Anchors: summit_center, reverse_slope (far/right side), foot_left, foot_right.
# Edges: RAMP when slope_edges, else CLIFF.
class_name RidgePlacer
extends FeaturePlacer

func place(data: MapData, slot_col: int, def: FeatureDefinition,
		rng: RandomNumberGenerator, instance_id: String, origin: int) -> FeatureInstance:
	var w := rng.randi_range(def.width_min, def.width_max)
	var h := rng.randi_range(def.height_min, def.height_max)
	var base_col := slot_col - w / 2
	var surf     := surface_row(data, slot_col)
	var top_row  := maxi(surf - h, 0)
	var base_row := top_row + int(h * 0.70)   # bottom 30% = indestructible base
	var slope    : bool = def.special_params.get("slope_edges", false)

	for col in range(base_col, base_col + w):
		if col < 0 or col >= data.width:
			continue
		var col_top := top_row
		if slope:
			var dist_from_edge := mini(col - base_col, (base_col + w - 1) - col)
			col_top += maxi(0, 2 - dist_from_edge)
		# Fill down to the local surface so the ridge never floats over noise dips.
		var col_bottom := surface_row(data, col)
		for row in range(col_top, col_bottom + 1):
			if row < 0 or row >= data.height:
				continue
			if row >= base_row:
				data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE, false, [], origin)
			else:
				data.place_solid(col, row, 3, 0, true, ["FLAMMABLE"], origin)

	var inst := make_instance(instance_id, def.type,
			Rect2i(base_col, top_row, w, surf - top_row + 1))
	inst.anchors["summit_center"] = Vector2i(slot_col, surface_row(data, slot_col) - 1)
	var rev_col := clampi(base_col + w - 2, 0, data.width - 1)
	inst.anchors["reverse_slope"] = Vector2i(rev_col, surface_row(data, rev_col) - 1)
	var fl_col := clampi(base_col - 1, 0, data.width - 1)
	var fr_col := clampi(base_col + w, 0, data.width - 1)
	inst.anchors["foot_left"]  = Vector2i(fl_col, surface_row(data, fl_col) - 1)
	inst.anchors["foot_right"] = Vector2i(fr_col, surface_row(data, fr_col) - 1)
	var edge := FeatureInstance.EdgeType.RAMP if slope else FeatureInstance.EdgeType.CLIFF
	inst.edge_specs = { "left": edge, "right": edge }
	return inst

func validate(data: MapData, inst: FeatureInstance) -> String:
	var summit : Vector2i = inst.anchor("summit_center")
	if not is_open(data, summit.x, summit.y) or not is_open(data, summit.x, summit.y - 1):
		return "%s: summit not standable" % inst.id
	if data.get_cell(summit.x, summit.y + 1) == null:
		return "%s: no ground under summit" % inst.id
	return ""
