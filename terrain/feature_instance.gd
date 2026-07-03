# Result record of a feature placer (M43, terrain-generation v0.2 §5.2): the contract the
# rest of the pipeline consumes. The seam pass reads edge_specs, the validation pass reads
# footprint/anchors/gap_rects, and (M44+) StageDescriptors will place enemies by anchor name.
# Anchors are named positions: exact voxels (Vector2i) or freeform zones (Rect2i). Standable
# anchors point at the OPEN voxel where a unit's base goes, not at the solid tile below it.
class_name FeatureInstance
extends RefCounted

enum EdgeType { RAMP, CLIFF, GAP, FLUSH }

var id         : String = ""         # e.g. "bunker_1" — type name + ordinal, unique per map
var type       : int = 0             # FeatureDefinition.FeatureType
var footprint  : Rect2i = Rect2i()   # claimed voxel region (position = top-left col/row)
var anchors    : Dictionary = {}     # name -> Vector2i (exact) or Rect2i (zone)
var edge_specs : Dictionary = {}     # "left" / "right" / "bottom" -> EdgeType
var gap_rects  : Array = []          # Rect2i regions that must stay VOID (GAP edges)

func anchor(name: String) -> Variant:
	return anchors.get(name, null)
