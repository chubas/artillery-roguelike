# Bunker / fortification (v0.2 §8.3): "the enemy is inside a protected structure."
# Reinforced shell (3-voxel walls, hp 8-12), hollow interior, 1-2 apertures in the facing
# (left) wall. By-construction invariants: interior fits a 2x3 unit (width/height clamped),
# at least one aperture. Edges: FLUSH bottom (seam pass builds the foundation).
# Anchors: interior_center + interior (zone), aperture_1..n, core, roof_center.
class_name BunkerPlacer
extends FeaturePlacer

const WALL := 3   # shell thickness in voxels

func place(data: MapData, slot_col: int, def: FeatureDefinition,
		rng: RandomNumberGenerator, instance_id: String, origin: int) -> FeatureInstance:
	# Clamp so the hollow interior (inset WALL on each side) always fits a 2x3 unit.
	var bw := maxi(rng.randi_range(def.width_min, def.width_max), WALL * 2 + 4)
	var bh := maxi(rng.randi_range(def.height_min, def.height_max), WALL + 1 + 5)
	var apertures : int = maxi(def.special_params.get("aperture_count", 1), 1)
	var surf      := surface_row(data, slot_col)
	var top_row   := maxi(surf - bh, 0)
	var base_col  := slot_col - bw / 2

	# Shell block
	for col in range(base_col, base_col + bw):
		if col < 0 or col >= data.width:
			continue
		for row in range(top_row, surf + 1):
			if row < 0 or row >= data.height:
				continue
			var shell_hp := rng.randi_range(8, 12)
			data.set_cell(col, row, {
				"type": 0,
				"hp": shell_hp, "max_hp": shell_hp, "flags": 0,
				"collapsible": true, "status_tags": ["FLAMMABLE"],
				"variant": 0, "gen_origin": origin
			})

	# Hollow interior (WALL inset; floor is 1 voxel above the base row)
	var int_left   := base_col + WALL
	var int_right  := base_col + bw - WALL          # exclusive
	var int_top    := top_row + WALL
	var int_bottom := surf - 1                      # exclusive
	for col in range(int_left, int_right):
		if col < 0 or col >= data.width:
			continue
		for row in range(int_top, int_bottom):
			if row >= 0 and row < data.height:
				data.set_cell(col, row, null)

	# Apertures in the facing (left) wall
	var inst := make_instance(instance_id, def.type, Rect2i(base_col, top_row, bw, surf - top_row + 1))
	var ap_spacing := bh / (apertures + 1)
	for a in range(apertures):
		var ap_row := clampi(top_row + ap_spacing * (a + 1), int_top, int_bottom - 1)
		for c2 in range(base_col, base_col + WALL):
			if c2 >= 0 and c2 < data.width:
				data.set_cell(c2, ap_row, null)
		inst.anchors["aperture_%d" % (a + 1)] = Vector2i(base_col, ap_row)

	var interior := Rect2i(int_left, int_top, int_right - int_left, int_bottom - int_top)
	inst.anchors["interior"] = interior
	inst.anchors["interior_center"] = Vector2i(interior.get_center())
	inst.anchors["core"] = Vector2i(int_right - 2, int_bottom - 1)   # deepest point, far from apertures
	inst.anchors["roof_center"] = Vector2i(slot_col, top_row - 1)
	inst.edge_specs = { "bottom": FeatureInstance.EdgeType.FLUSH }
	return inst

func validate(data: MapData, inst: FeatureInstance) -> String:
	var interior : Rect2i = inst.anchor("interior")
	for col in range(interior.position.x, interior.end.x):
		for row in range(interior.position.y, interior.end.y):
			if data.get_cell(col, row) != null:
				return "%s: interior not hollow at (%d,%d)" % [inst.id, col, row]
	var a := 1
	while inst.anchors.has("aperture_%d" % a):
		var mouth : Vector2i = inst.anchor("aperture_%d" % a)
		for c in range(mouth.x - 3, mouth.x):
			if not is_open(data, c, mouth.y):
				return "%s: aperture_%d blocked outside" % [inst.id, a]
		a += 1
	if a == 1:
		return "%s: no apertures" % inst.id
	return ""
