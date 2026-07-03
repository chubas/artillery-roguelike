# Seam pass (M43, terrain-generation v0.2 §6): reconciles each FeatureInstance's edges
# with the surrounding terrain per its declared edge specs. Runs after the placer pass,
# gated by Features.terrain_v2_enabled. Seam tiles are normal-durability connective
# tissue with GenOrigin.SEAM (own visualizer color). Seams never edit footprint interiors.
class_name SeamPass

## Voxels of descent per ramp column — 2 keeps every step climbable (medium max_climb).
const RAMP_STEP := 2
## Safety bound on ramp length (tallest feature / RAMP_STEP is well under this).
const MAX_RAMP_COLS := 32

static func apply(data: MapData) -> void:
	for inst in data.features:
		for side in inst.edge_specs:
			match inst.edge_specs[side]:
				FeatureInstance.EdgeType.RAMP:
					_ramp(data, inst, side)
				FeatureInstance.EdgeType.GAP:
					_gap(data, inst)
				FeatureInstance.EdgeType.FLUSH:
					_flush(data, inst)
				_:
					pass   # CLIFF — leave as generated

# ── RAMP — walkable staircase from the feature's edge top down to the neighbor surface ──

static func _ramp(data: MapData, inst: FeatureInstance, side: String) -> void:
	var dir := -1 if side == "left" else 1
	var edge_col := inst.footprint.position.x if dir == -1 else inst.footprint.end.x - 1
	edge_col = clampi(edge_col, 0, data.width - 1)
	var edge_top := FeaturePlacer.surface_row(data, edge_col)

	for i in range(1, MAX_RAMP_COLS + 1):
		var col := edge_col + dir * i
		if col < 0 or col >= data.width:
			return
		var target_top := edge_top + i * RAMP_STEP   # descend until the ground meets us
		var natural    := FeaturePlacer.surface_row(data, col)
		if natural <= target_top:
			return   # ground already reaches ramp height — connected
		for row in range(target_top, natural):
			data.place_solid(col, row, 3, 0, false, ["FLAMMABLE"], MapData.GenOrigin.SEAM)

# ── GAP — defensively keep the declared isolation volumes void ────────────────

static func _gap(data: MapData, inst: FeatureInstance) -> void:
	for rect in inst.gap_rects:
		var r : Rect2i = rect
		for col in range(maxi(r.position.x, 0), mini(r.end.x, data.width)):
			for row in range(maxi(r.position.y, 0), mini(r.end.y, data.height)):
				data.set_cell(col, row, null)

# ── FLUSH — foundation columns under the feature base down to the local surface ──

static func _flush(data: MapData, inst: FeatureInstance) -> void:
	var bottom := inst.footprint.end.y - 1
	for col in range(maxi(inst.footprint.position.x, 0),
			mini(inst.footprint.end.x, data.width)):
		var base_cell = data.get_cell(col, bottom)
		if base_cell == null:
			continue
		var indestructible := ((base_cell.get("flags", 0) as int) & Tile.FLAG_INDESTRUCTIBLE) != 0
		var row := bottom + 1
		while row < data.height and data.get_cell(col, row) == null:
			data.place_solid(col, row, 3,
					Tile.FLAG_INDESTRUCTIBLE if indestructible else 0,
					false, [], MapData.GenOrigin.SEAM)
			row += 1
