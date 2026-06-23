class_name FeatureDefinition
extends Resource

enum FeatureType { RIDGE, BUNKER, PIT, PILLAR, CRYSTAL_DEPOSIT }

@export var type           : FeatureType = FeatureType.RIDGE
@export var width_min      : int = 10
@export var width_max      : int = 20
@export var height_min     : int = 8
@export var height_max     : int = 14
## Feature-specific params. Keys vary by type:
##   RIDGE: slope_edges (bool)
##   BUNKER: aperture_count (int)
##   PILLAR: gap_from_terrain (int)
@export var special_params : Dictionary = {}
