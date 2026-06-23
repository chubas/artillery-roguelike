class_name TerrainProfile
extends Resource

@export var story               : String = ""
@export var act_min             : int = 1
@export var act_max             : int = 3
@export var map_width_min       : int = 100
@export var map_width_max       : int = 130
@export var map_height_min      : int = 90
@export var map_height_max      : int = 110
@export var noise_max_amplitude : int = 6
@export var left_slot           : FeatureDefinition = null
@export var center_slot         : FeatureDefinition = null
@export var right_slot          : FeatureDefinition = null
@export var background          : Array[FeatureDefinition] = []
@export var enemy_zone_start    : float = 0.55
@export var enemy_zone_end      : float = 0.90
