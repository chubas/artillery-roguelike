# Typed, generated gameplay map imported from LDtk (M48). This is a compact authored definition;
# to_map_data() materializes the mutable runtime grid consumed by TerrainManager.
class_name MapDefinition
extends Resource

const TERRAIN_EMPTY := 0
const TERRAIN_UNBREAKABLE := 10
const TERRAIN_MINERAL := 11

@export var id          : String = ""
@export var title       : String = ""
@export var description : String = ""
@export var notes       : String = ""
@export var pool        : bool = true

@export var width          : int = 0
@export var height         : int = 0
@export var terrain_values : PackedByteArray = PackedByteArray()
@export var spawn_zones    : Array[Rect2i] = []
@export var enemy_zones    : Array[Rect2i] = []
@export var entities       : Array[MapEntity] = []

@export var auto_fill_terrain : bool = false
@export var auto_fill_min     : int = 0
@export var auto_fill_max     : int = 0

@export var source_project   : String = ""
@export var source_level_iid : String = ""
@export var source_hash      : String = ""


func terrain_value(col: int, row: int) -> int:
	if col < 0 or col >= width or row < 0 or row >= height:
		return TERRAIN_EMPTY
	var index := row * width + col
	if index < 0 or index >= terrain_values.size():
		return TERRAIN_EMPTY
	return terrain_values[index]


## Build the mutable runtime grid. Auto-fill is deterministic for a stage seed; seed 0 derives from
## the stable map id for tools and tests that do not have a run seed.
func to_map_data(noise_seed: int = 0) -> MapData:
	var data := MapData.new()
	data.width = width
	data.height = height
	data.cells.resize(width * height)
	data.cells.fill(null)

	var noise : FastNoiseLite = null
	if auto_fill_terrain:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.08
		noise.seed = noise_seed if noise_seed != 0 else hash(id)

	for row in range(height):
		for col in range(width):
			var value := terrain_value(col, row)
			if value == TERRAIN_EMPTY:
				continue

			var cell : Dictionary
			if value == TERRAIN_MINERAL:
				cell = {
					"type": Tile.TileType.MINERAL,
					"hp": 2, "max_hp": 2, "flags": 0,
					"collapsible": false, "status_tags": ["MINERAL"],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			elif value == TERRAIN_UNBREAKABLE:
				cell = {
					"type": Tile.TileType.SOLID,
					"hp": 3, "max_hp": 3, "flags": Tile.FLAG_INDESTRUCTIBLE,
					"collapsible": false, "status_tags": [],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			else:
				var hp := value
				if noise != null and value == 1:
					var t := (noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
					hp = mini(auto_fill_min + int(t * float(auto_fill_max - auto_fill_min + 1)),
							auto_fill_max)
				cell = {
					"type": Tile.TileType.SOLID,
					"hp": hp, "max_hp": hp, "flags": 0,
					"collapsible": false, "status_tags": ["FLAMMABLE"],
					"variant": 0, "gen_origin": MapData.GenOrigin.NOISE_FILL
				}
			data.set_cell(col, row, cell)
	return data
