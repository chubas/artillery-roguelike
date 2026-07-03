# Base class for feature placers (M43, terrain-generation v0.2 §5). One placer per
# FeatureDefinition.FeatureType, registered in TerrainGenerator.PLACERS — adding a new
# terrain structure is one placer script + a registry line + a FeatureDefinition .tres.
#
# A placer stamps its feature into MapData (overwriting the noise surface inside its
# footprint — pass B runs AFTER the noise pass) and returns a FeatureInstance with the
# footprint, named anchors, and edge specs. The placer guarantees its INTERNAL invariants
# by construction (interior clearance, aperture presence, isolation gaps); how edges meet
# the surrounding terrain is the seam pass; whole-map guarantees are the validation pass,
# which calls back into validate() against the final map.
class_name FeaturePlacer
extends RefCounted

## Stamp the feature centered on slot_col; return its FeatureInstance (null on failure).
## origin is the MapData.GenOrigin value for this slot (visualizer coloring).
func place(_data: MapData, _slot_col: int, _def: FeatureDefinition,
		_rng: RandomNumberGenerator, _instance_id: String, _origin: int) -> FeatureInstance:
	push_error("FeaturePlacer.place not implemented")
	return null

## Check the feature still serves its function on the FINAL map (after seams + HP pass).
## Returns "" when valid, else a short failure reason for the reroll log.
func validate(_data: MapData, _inst: FeatureInstance) -> String:
	return ""

## Topmost non-void row in a column (map bottom row if the column is empty).
static func surface_row(data: MapData, col: int) -> int:
	for row in range(data.height):
		if data.get_cell(col, row) != null:
			return row
	return data.height - 1

## True when the voxel is in-bounds and VOID.
static func is_open(data: MapData, col: int, row: int) -> bool:
	if col < 0 or col >= data.width or row < 0 or row >= data.height:
		return false
	return data.get_cell(col, row) == null

static func make_instance(inst_id: String, type: int, footprint: Rect2i) -> FeatureInstance:
	var inst := FeatureInstance.new()
	inst.id = inst_id
	inst.type = type
	inst.footprint = footprint
	return inst
