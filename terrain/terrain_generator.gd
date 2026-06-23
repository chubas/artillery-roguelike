class_name TerrainGenerator

# ── Public API ────────────────────────────────────────────────────────────────

static func generate(profile: TerrainProfile, seed: int) -> MapData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var data := MapData.new()
	data.width  = rng.randi_range(profile.map_width_min,  profile.map_width_max)
	data.height = rng.randi_range(profile.map_height_min, profile.map_height_max)
	data.cells.resize(data.width * data.height)
	data.cells.fill(null)

	_pass1_features(data, profile, rng)
	_pass1_spawn_platform(data)
	_pass2_base_and_noise(data, profile, rng)
	_pass3_hp(data, rng)
	_pass4_variants(data, rng)

	return data

# ── Pass 1 — skeletal features ────────────────────────────────────────────────

static func _pass1_features(data: MapData, profile: TerrainProfile,
		rng: RandomNumberGenerator) -> void:
	var slots := [
		[profile.left_slot,   MapData.GenOrigin.SLOT_LEFT,   int(0.25 * data.width)],
		[profile.center_slot, MapData.GenOrigin.SLOT_CENTER, int(0.50 * data.width)],
		[profile.right_slot,  MapData.GenOrigin.SLOT_RIGHT,  int(0.75 * data.width)],
	]
	for entry in slots:
		var def : FeatureDefinition = entry[0]
		var origin : int            = entry[1]
		var slot_col : int          = entry[2]
		if def == null:
			continue
		match def.type:
			FeatureDefinition.FeatureType.RIDGE:
				_place_ridge(data, slot_col, def, origin, rng)
			FeatureDefinition.FeatureType.BUNKER:
				_place_bunker(data, slot_col, def, origin, rng)
			FeatureDefinition.FeatureType.PIT:
				_place_pit(data, slot_col, def, origin, rng)
			FeatureDefinition.FeatureType.PILLAR:
				_place_pillar(data, slot_col, def, origin, rng)

	for bg_def in profile.background:
		if bg_def == null:
			continue
		if bg_def.type == FeatureDefinition.FeatureType.CRYSTAL_DEPOSIT:
			_place_crystal_deposit(data, bg_def, rng)

static func _pass1_spawn_platform(data: MapData) -> void:
	# Mirror of TerrainManager.generate() pass 4. Spawn platform is always at the
	# leftmost column band, indestructible, with clear space above.
	var base_row  := data.height - Const.BASE_FILL_ROWS
	# Approximate surface row at spawn col: use base_row as the reference.
	var prow := base_row
	for col in range(Const.SPAWN_PLATFORM_COL,
			Const.SPAWN_PLATFORM_COL + Const.SPAWN_PLATFORM_WIDTH):
		if col >= data.width:
			break
		for row in range(prow, data.height):
			data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE,
					false, [], MapData.GenOrigin.SPAWN_PLATFORM)
		for row in range(maxi(prow - 6, 0), prow):
			data.set_cell(col, row, null)

# ── Feature placers ────────────────────────────────────────────────────────────

static func _surface_row(data: MapData, col: int) -> int:
	for row in range(data.height):
		if data.get_cell(col, row) != null:
			return row
	return data.height - 1

static func _place_ridge(data: MapData, slot_col: int, def: FeatureDefinition,
		origin: int, rng: RandomNumberGenerator) -> void:
	var w := rng.randi_range(def.width_min, def.width_max)
	var h := rng.randi_range(def.height_min, def.height_max)
	var base_col := slot_col - w / 2
	var surf     := _surface_row(data, slot_col)
	var top_row  := maxi(surf - h, 0)
	var base_row := top_row + int(h * 0.70)   # bottom 30% = indestructible base
	var slope    : bool = def.special_params.get("slope_edges", false)

	for col in range(base_col, base_col + w):
		if col < 0 or col >= data.width:
			continue
		var col_top := top_row
		if slope:
			var dist_from_edge := mini(col - base_col, (base_col + w - 1) - col)
			col_top += maxi(0, 2 - dist_from_edge)

		for row in range(col_top, surf + 1):
			if row < 0 or row >= data.height:
				continue
			if row >= base_row:
				# Indestructible base
				data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE,
						false, [], origin)
			else:
				# Carveable fill
				data.place_solid(col, row, 3, 0, true, ["FLAMMABLE"], origin)

static func _place_pit(data: MapData, slot_col: int, def: FeatureDefinition,
		origin: int, rng: RandomNumberGenerator) -> void:
	var w     := rng.randi_range(def.width_min, def.width_max)
	var depth := rng.randi_range(def.height_min, def.height_max)
	var base_col := slot_col - w / 2
	var surf  := _surface_row(data, slot_col)

	for col in range(base_col, base_col + w):
		if col < 0 or col >= data.width:
			continue
		for row in range(surf, mini(surf + depth, data.height)):
			data.set_cell(col, row, null)
		# Mark the walls at the pit edge with origin so visualizer shows the slot
		if col == base_col or col == base_col + w - 1:
			for row in range(maxi(surf - 2, 0), surf):
				var cell = data.get_cell(col, row)
				if cell != null:
					cell["gen_origin"] = origin

static func _place_pillar(data: MapData, slot_col: int, def: FeatureDefinition,
		origin: int, rng: RandomNumberGenerator) -> void:
	var pw   := rng.randi_range(def.width_min,  def.width_max)
	var ph   := rng.randi_range(def.height_min, def.height_max)
	var gap  : int = def.special_params.get("gap_from_terrain", 8)
	var surf := _surface_row(data, slot_col)
	var top_row  := maxi(surf - ph, 0)
	var base_row := top_row + int(ph * 0.40)
	var base_col := slot_col - pw / 2

	# Carve gap on both sides
	for col in range(base_col - gap, base_col):
		if col < 0 or col >= data.width:
			continue
		for row in range(maxi(surf - ph - 2, 0), surf + 1):
			if row >= 0 and row < data.height:
				data.set_cell(col, row, null)
	for col in range(base_col + pw, base_col + pw + gap):
		if col < 0 or col >= data.width:
			continue
		for row in range(maxi(surf - ph - 2, 0), surf + 1):
			if row >= 0 and row < data.height:
				data.set_cell(col, row, null)

	# Place pillar block
	for col in range(base_col, base_col + pw):
		if col < 0 or col >= data.width:
			continue
		for row in range(top_row, surf + 1):
			if row < 0 or row >= data.height:
				continue
			if row >= base_row:
				data.place_solid(col, row, 3, Tile.FLAG_INDESTRUCTIBLE,
						false, [], origin)
			else:
				data.place_solid(col, row, 3, 0, true, ["FLAMMABLE"], origin)

static func _place_bunker(data: MapData, slot_col: int, def: FeatureDefinition,
		origin: int, rng: RandomNumberGenerator) -> void:
	var bw        := rng.randi_range(def.width_min, def.width_max)
	var bh        := rng.randi_range(def.height_min, def.height_max)
	var apertures : int = def.special_params.get("aperture_count", 1)
	var surf      := _surface_row(data, slot_col)
	var top_row   := maxi(surf - bh, 0)
	var base_col  := slot_col - bw / 2

	# Place shell first (entire block)
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

	# Hollow out interior (3-voxel inset)
	for col in range(base_col + 3, base_col + bw - 3):
		if col < 0 or col >= data.width:
			continue
		for row in range(top_row + 3, surf - 1):
			if row >= 0 and row < data.height:
				data.set_cell(col, row, null)

	# Apertures in the facing (left) wall
	var ap_spacing := bh / (apertures + 1)
	for a in range(apertures):
		var ap_row := top_row + ap_spacing * (a + 1)
		if ap_row >= 0 and ap_row < data.height:
			for c2 in range(base_col, base_col + 3):
				if c2 >= 0 and c2 < data.width:
					data.set_cell(c2, ap_row, null)

static func _place_crystal_deposit(data: MapData, def: FeatureDefinition,
		rng: RandomNumberGenerator) -> void:
	var depth_min := def.height_min
	var depth_max := def.height_max
	var tile_count := rng.randi_range(3, 8)

	# Place in left-center zone to be reachable from spawn side
	var vein_col := rng.randi_range(int(data.width * 0.10), int(data.width * 0.40))
	var vein_row := rng.randi_range(depth_min, mini(depth_max, data.height - 2))

	for _i in range(tile_count):
		var col := vein_col + rng.randi_range(-2, 2)
		var row := vein_row + rng.randi_range(-1, 1)
		if col < 0 or col >= data.width or row < 0 or row >= data.height:
			continue
		data.set_cell(col, row, {
			"type": 0,
			"hp": 5, "max_hp": 5, "flags": 0,
			"collapsible": true, "status_tags": ["CRYSTAL"],
			"variant": 0, "gen_origin": MapData.GenOrigin.CRYSTAL
		})

# ── Pass 2 — base fill + noise ────────────────────────────────────────────────

static func _pass2_base_and_noise(data: MapData, profile: TerrainProfile,
		rng: RandomNumberGenerator) -> void:
	var base_row := data.height - Const.BASE_FILL_ROWS

	# Identify columns claimed by pass 1
	var claimed : Array = []
	claimed.resize(data.width)
	claimed.fill(false)
	for col in range(data.width):
		for row in range(data.height):
			if data.get_cell(col, row) != null:
				claimed[col] = true
				break

	# Base fill for unclaimed columns
	for col in range(data.width):
		if claimed[col]:
			continue
		for row in range(base_row, data.height):
			data.place_solid(col, row, 3, 0, false, ["FLAMMABLE"],
					MapData.GenOrigin.NOISE_FILL)

	# Noise surface pass for unclaimed columns
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = rng.randi()
	noise.frequency = Const.NOISE_FREQUENCY
	var amp := profile.noise_max_amplitude

	for col in range(data.width):
		if claimed[col]:
			continue
		var offset   := int(noise.get_noise_1d(float(col)) * amp)
		var surf_row := clampi(base_row - offset, 0, data.height - 1)
		for row in range(surf_row, base_row):
			data.place_solid(col, row, 3, 0, false, ["FLAMMABLE"],
					MapData.GenOrigin.NOISE_FILL)
		for row in range(base_row, surf_row):
			data.set_cell(col, row, null)

# ── Pass 3 — HP assignment ────────────────────────────────────────────────────

static func _pass3_hp(data: MapData, rng: RandomNumberGenerator) -> void:
	var hp_rng := RandomNumberGenerator.new()
	hp_rng.seed = rng.randi()
	for i in range(data.cells.size()):
		var cell = data.cells[i]
		if cell == null:
			continue
		if (cell["flags"] as int) & Tile.FLAG_INDESTRUCTIBLE:
			continue
		if hp_rng.randf() < Const.REINFORCED_TILE_CHANCE:
			cell["hp"]     = 6
			cell["max_hp"] = 6
			cell["status_tags"] = ["CONDUCTIVE"]

# ── Pass 4 — visual variants ──────────────────────────────────────────────────

static func _pass4_variants(data: MapData, rng: RandomNumberGenerator) -> void:
	var var_rng := RandomNumberGenerator.new()
	var_rng.seed = rng.randi()
	for i in range(data.cells.size()):
		if data.cells[i] != null:
			data.cells[i]["variant"] = var_rng.randi_range(0, 3)
