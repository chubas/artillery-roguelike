# Profile-driven terrain generation (M32, rebuilt in M43 to the v0.2 pipeline):
#   A  base fill + noise surface everywhere (spawn platform stamped over it)
#   B  skeletal features via placer modules (terrain/placers/*), anchored to the REAL
#      surface, each exporting a FeatureInstance (footprint / anchors / edge specs)
#   C  seam pass — reconciles feature edges with the surrounding terrain (SeamPass)
#   D  HP sprinkle + visual variants (never mutates feature-tile durability)
#   E  validation + bounded seed-reroll (MapValidator)
# Stages C and E are gated by Features.terrain_v2_enabled.
class_name TerrainGenerator

const MAX_ATTEMPTS := 5

## FeatureType -> placer script. Adding a construct = new placer + one line here.
const PLACERS := {
	FeatureDefinition.FeatureType.RIDGE:           preload("res://terrain/placers/ridge_placer.gd"),
	FeatureDefinition.FeatureType.BUNKER:          preload("res://terrain/placers/bunker_placer.gd"),
	FeatureDefinition.FeatureType.PIT:             preload("res://terrain/placers/pit_placer.gd"),
	FeatureDefinition.FeatureType.PILLAR:          preload("res://terrain/placers/pillar_placer.gd"),
	FeatureDefinition.FeatureType.CRYSTAL_DEPOSIT: preload("res://terrain/placers/crystal_placer.gd"),
}

# ── Public API ────────────────────────────────────────────────────────────────

static func generate(profile: TerrainProfile, seed: int) -> MapData:
	var data : MapData = null
	var max_attempts := MAX_ATTEMPTS if Features.terrain_v2_enabled else 1
	for attempt in range(max_attempts):
		var attempt_seed := seed if attempt == 0 else hash([seed, attempt])
		data = _generate_once(profile, attempt_seed)
		data.attempts_used = attempt + 1
		if not Features.terrain_v2_enabled:
			return data
		data.validation_failure = MapValidator.validate(data, profile)
		if data.validation_failure == "":
			return data
	push_warning("TerrainGenerator: validation exhausted after %d attempts (seed %d): %s"
			% [data.attempts_used, seed, data.validation_failure])
	return data

static func _generate_once(profile: TerrainProfile, seed: int) -> MapData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var data := MapData.new()
	data.width  = rng.randi_range(profile.map_width_min,  profile.map_width_max)
	data.height = rng.randi_range(profile.map_height_min, profile.map_height_max)
	data.cells.resize(data.width * data.height)
	data.cells.fill(null)

	_pass_a_base_and_noise(data, profile, rng)
	_pass_a_spawn_platform(data)
	_pass_b_features(data, profile, rng)
	if Features.terrain_v2_enabled:
		SeamPass.apply(data)
	_pass_d_hp(data, rng)
	_pass_d_variants(data, rng)

	return data

# ── Stage A — base fill + noise surface (all columns) ────────────────────────

static func _pass_a_base_and_noise(data: MapData, profile: TerrainProfile,
		rng: RandomNumberGenerator) -> void:
	var base_row := data.height - Const.BASE_FILL_ROWS

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = rng.randi()
	noise.frequency = Const.NOISE_FREQUENCY
	var amp := profile.noise_max_amplitude

	for col in range(data.width):
		var offset   := int(noise.get_noise_1d(float(col)) * amp)
		var surf_row := clampi(base_row - offset, 0, data.height - 1)
		for row in range(surf_row, data.height):
			data.place_solid(col, row, 3, 0, false, ["FLAMMABLE"],
					MapData.GenOrigin.NOISE_FILL)

static func _pass_a_spawn_platform(data: MapData) -> void:
	# Spawn platform is always the leftmost column band, indestructible, clear above.
	var prow := data.height - Const.BASE_FILL_ROWS
	for col in range(Const.SPAWN_PLATFORM_COL,
			Const.SPAWN_PLATFORM_COL + Const.SPAWN_PLATFORM_WIDTH):
		if col >= data.width:
			break
		for row in range(prow, data.height):
			data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE,
					false, [], MapData.GenOrigin.SPAWN_PLATFORM)
		for row in range(maxi(prow - 6, 0), prow):
			data.set_cell(col, row, null)

# ── Stage B — skeletal features via placers ───────────────────────────────────

static func _pass_b_features(data: MapData, profile: TerrainProfile,
		rng: RandomNumberGenerator) -> void:
	var counts : Dictionary = {}
	var slots := [
		[profile.left_slot,   MapData.GenOrigin.SLOT_LEFT,   int(0.25 * data.width)],
		[profile.center_slot, MapData.GenOrigin.SLOT_CENTER, int(0.50 * data.width)],
		[profile.right_slot,  MapData.GenOrigin.SLOT_RIGHT,  int(0.75 * data.width)],
	]
	for entry in slots:
		_run_placer(data, entry[0], entry[2], entry[1], rng, counts)
	for bg_def in profile.background:
		_run_placer(data, bg_def, -1, MapData.GenOrigin.BACKGROUND, rng, counts)

static func _run_placer(data: MapData, def: FeatureDefinition, slot_col: int,
		origin: int, rng: RandomNumberGenerator, counts: Dictionary) -> void:
	if def == null:
		return
	var placer_script = PLACERS.get(def.type)
	if placer_script == null:
		push_warning("TerrainGenerator: no placer for FeatureType %d" % def.type)
		return
	var type_name : String = FeatureDefinition.FeatureType.keys()[def.type].to_lower()
	counts[type_name] = counts.get(type_name, 0) + 1
	var instance_id := "%s_%d" % [type_name, counts[type_name]]
	var inst : FeatureInstance = placer_script.new().place(
			data, slot_col, def, rng, instance_id, origin)
	if inst != null:
		data.features.append(inst)

# ── Stage D — HP sprinkle + visual variants ───────────────────────────────────

static func _pass_d_hp(data: MapData, rng: RandomNumberGenerator) -> void:
	var hp_rng := RandomNumberGenerator.new()
	hp_rng.seed = rng.randi()
	for i in range(data.cells.size()):
		var cell = data.cells[i]
		if cell == null:
			continue
		# Only ambient terrain gets the reinforced sprinkle — feature tiles keep the
		# durability their placer assigned (v0.2 rule: stage D never mutates features).
		var origin : int = cell.get("gen_origin", MapData.GenOrigin.NOISE_FILL)
		if origin != MapData.GenOrigin.NOISE_FILL and origin != MapData.GenOrigin.SEAM:
			continue
		if (cell["flags"] as int) & Tile.FLAG_INDESTRUCTIBLE:
			continue
		if hp_rng.randf() < Const.REINFORCED_TILE_CHANCE:
			cell["hp"]     = 6
			cell["max_hp"] = 6
			cell["status_tags"] = ["CONDUCTIVE"]

static func _pass_d_variants(data: MapData, rng: RandomNumberGenerator) -> void:
	var var_rng := RandomNumberGenerator.new()
	var_rng.seed = rng.randi()
	for i in range(data.cells.size()):
		if data.cells[i] != null:
			data.cells[i]["variant"] = var_rng.randi_range(0, 3)
