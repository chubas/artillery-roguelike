# A stage as data (run-state spec §5): initial force + telegraphed reinforcement schedule +
# deployables + wind profile + terrain seed + objective. Everything the combat scene used to
# hardcode now lives here, so a stage is data the scene reads — and the map (M14) becomes a graph
# of these. Hand-authored as .tres (baked via scripts/bake_resources.gd); procedural is later.
class_name StageDescriptor
extends Resource

@export var id : String = ""
@export var terrain_seed : int = 12345   # was Const.NOISE_SEED — drives reproducible generation

## Present at turn 0: [{ "unit": res_path, "name": String, "col": int }]
@export var initial_enemies : Array = []
## Telegraphed waves: [{ "round": int, "unit": res_path, "name": String, "col": int }]
@export var reinforcements : Array = []
## Hand-placed deployables: [{ "type": "mine" | "shield_generator", "col": int }]
@export var deployables : Array = []

## Wind profile (mirrors the old _WIND_CONFIG). Gated globally by Features.wind_enabled too.
@export var wind_enabled        : bool = true
@export var wind_start_round    : int = 3
@export var wind_ramp_per_round : float = 0.05
@export var wind_max_strength   : float = 1.0

@export var objective : ObjectiveDescriptor = null

## Pre-combat placement zone (M15): the column band the player may deploy the squad into.
## Default = left half of the map. Column-range only for now; richer zones come with terrain
## variability. Units snap to the surface, so rows are implied.
@export var spawn_min_col : int = 0
@export var spawn_max_col : int = 59   # Const.MAP_WIDTH / 2 - 1

## Reserved seams — not consumed yet.
@export var rewards     : Array[String] = []   # granted on completion (M16)
@export var threat_tags : Array[String] = []   # surfaced by the map for telegraphing (M14)
