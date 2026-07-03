# Pit / canyon (v0.2 §8.7): "the terrain gap punishes ground movement."
# Carves the columns to depth; the void IS the gap, so the footprint doubles as the
# gap_rect the seam/validation passes keep clear. Edges: GAP.
# Anchors: rim_left, rim_right (standing spots at the edges), bottom_center (zone).
class_name PitPlacer
extends FeaturePlacer

func place(data: MapData, slot_col: int, def: FeatureDefinition,
		rng: RandomNumberGenerator, instance_id: String, origin: int) -> FeatureInstance:
	var w     := rng.randi_range(def.width_min, def.width_max)
	var depth := rng.randi_range(def.height_min, def.height_max)
	var base_col := slot_col - w / 2
	var surf  := surface_row(data, slot_col)
	var bottom := mini(surf + depth, data.height)

	for col in range(base_col, base_col + w):
		if col < 0 or col >= data.width:
			continue
		# Carve from the local surface (which may sit above surf) down to the pit bottom.
		for row in range(mini(surface_row(data, col), surf), bottom):
			data.set_cell(col, row, null)
		# Mark the rim tiles with the slot origin so the visualizer shows the feature.
		if col == base_col or col == base_col + w - 1:
			for row in range(maxi(surf - 2, 0), surf):
				var cell = data.get_cell(col, row)
				if cell != null:
					cell["gen_origin"] = origin

	var inst := make_instance(instance_id, def.type, Rect2i(base_col, surf, w, bottom - surf))
	var rl_col := clampi(base_col - 1, 0, data.width - 1)
	var rr_col := clampi(base_col + w, 0, data.width - 1)
	inst.anchors["rim_left"]  = Vector2i(rl_col, surface_row(data, rl_col) - 1)
	inst.anchors["rim_right"] = Vector2i(rr_col, surface_row(data, rr_col) - 1)
	inst.anchors["bottom_center"] = Rect2i(base_col + 1, bottom - 4, maxi(w - 2, 1), 4)
	inst.edge_specs = { "left": FeatureInstance.EdgeType.GAP,
			"right": FeatureInstance.EdgeType.GAP }
	inst.gap_rects = [ Rect2i(base_col, surf, w, bottom - surf) ]
	return inst

func validate(data: MapData, inst: FeatureInstance) -> String:
	# The carved volume must remain void (uncrossable on foot without digging/arcing).
	for rect in inst.gap_rects:
		var r : Rect2i = rect
		var mid_col := r.position.x + r.size.x / 2
		for row in range(r.position.y, r.end.y):
			if data.get_cell(mid_col, row) != null:
				return "%s: pit center column filled at row %d" % [inst.id, row]
	return ""
