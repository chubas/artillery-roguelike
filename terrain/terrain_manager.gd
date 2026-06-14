# Owns all tile data and is the only writer of _grid (terrain spec §5, §6, §7, §12).
class_name TerrainManager
extends Node

# --- Signals (terrain spec §12.4) --------------------------------------------
signal tile_damaged(col: int, row: int, dmg: int, remaining_hp: int)
signal tile_destroyed(col: int, row: int, tile_type: int)
signal tile_changed(col: int, row: int)
signal aoe_resolved(center: Vector2i, radius: int, affected: Array)

# --- Storage (terrain spec §5.1) ---------------------------------------------
var _grid : Array = []   # size MAP_WIDTH*MAP_HEIGHT; null = VOID

# Collapse batching (plan §1.3): destroyed tiles queue their column; the queue is
# flushed once per AoE resolution (or deferred for stray single hits) so tiles
# don't fall mid-iteration into cells the AoE loop hasn't visited yet.
var _pending_collapse_cols : Dictionary = {}
var _collapse_flush_queued : bool = false

func _ready() -> void:
	_grid.resize(Const.MAP_WIDTH * Const.MAP_HEIGHT)
	_grid.fill(null)
	generate()

func _idx(col: int, row: int) -> int:
	return row * Const.MAP_WIDTH + col

func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < Const.MAP_WIDTH and row >= 0 and row < Const.MAP_HEIGHT

# --- Access (terrain spec §12.1) ---------------------------------------------
func get_tile(col: int, row: int) -> Tile:
	if not _in_bounds(col, row):
		return null
	return _grid[_idx(col, row)]

func is_solid(col: int, row: int) -> bool:
	var t := get_tile(col, row)
	return t != null and t.type == Tile.TileType.SOLID

func is_blocked(col: int, row: int) -> bool:
	# Blocked = exists and not passable. In M1 any tile blocks (no flags set).
	var t := get_tile(col, row)
	return t != null and not t.has_flag(Tile.FLAG_PASSABLE)

func get_surface_row(col: int) -> int:
	for row in range(Const.MAP_HEIGHT):
		if is_solid(col, row):
			return row
	return -1

# --- Mutation (terrain spec §12.2, §7) ---------------------------------------
func set_tile(col: int, row: int, tile: Tile) -> void:
	if not _in_bounds(col, row):
		return
	_grid[_idx(col, row)] = tile
	tile_changed.emit(col, row)

func clear_tile(col: int, row: int) -> void:
	# Immediate VOID, no collapse; used by generation.
	if not _in_bounds(col, row):
		return
	_grid[_idx(col, row)] = null
	tile_changed.emit(col, row)

# Repaint request for tile overlays (status tint changes). Reuses the local render
# signal — TerrainRenderer already routes tile_changed to the owning chunk (M3 plan).
func mark_tile_dirty(col: int, row: int) -> void:
	if _in_bounds(col, row):
		tile_changed.emit(col, row)

func damage_tile(col: int, row: int, dmg: int) -> void:
	var tile := get_tile(col, row)
	if tile == null:
		return
	if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE):
		return
	var prev_state := tile.damage_state()
	tile.hp = maxi(tile.hp - dmg, 0)
	if tile.damage_state() != prev_state:
		tile_changed.emit(col, row)
	tile_damaged.emit(col, row, dmg, tile.hp)
	EventBus.tile_damaged.emit(col, row, dmg, tile.hp)
	if tile.hp <= 0:
		_destroy_tile(col, row, tile)

func _destroy_tile(col: int, row: int, tile: Tile) -> void:
	# M1: destruction always leaves VOID (RUBBLE is post-M1).
	_grid[_idx(col, row)] = null
	tile_destroyed.emit(col, row, tile.type)
	EventBus.tile_destroyed.emit(col, row, tile.type)
	tile_changed.emit(col, row)
	_pending_collapse_cols[col] = true
	if not _collapse_flush_queued:
		_collapse_flush_queued = true
		flush_collapses.call_deferred()

# --- Collapse: column fall (terrain spec §7.3, batched per plan §1.3) ---------
func flush_collapses() -> void:
	_collapse_flush_queued = false
	var cols := _pending_collapse_cols.keys()
	_pending_collapse_cols.clear()
	for col in cols:
		_collapse_column(col)

func _collapse_column(col: int) -> void:
	# Bottom-up walk: every fallen tile settles before the tiles above it are checked.
	for row in range(Const.MAP_HEIGHT - 2, -1, -1):
		var tile := get_tile(col, row)
		if tile == null:
			continue
		# Spawn platform tiles are anchored (prototype convenience, spec §6.1 pass 4).
		if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE):
			continue
		# Fixed terrain (the current default): non-collapsible tiles never fall.
		if not tile.collapsible:
			continue
		if get_tile(col, row + 1) == null:
			_fall_tile(col, row)

func _fall_tile(col: int, from_row: int) -> void:
	var to_row := from_row + 1
	while to_row < Const.MAP_HEIGHT - 1 and get_tile(col, to_row + 1) == null:
		to_row += 1
	var tile = _grid[_idx(col, from_row)]
	_grid[_idx(col, from_row)] = null
	_grid[_idx(col, to_row)] = tile
	tile_changed.emit(col, from_row)
	tile_changed.emit(col, to_row)

# --- Query (terrain spec §12.3) ----------------------------------------------
func get_tiles_in_diamond(cx: int, cy: int, radius: int) -> Array:
	var out : Array = []
	for col in range(cx - radius, cx + radius + 1):
		for row in range(cy - radius, cy + radius + 1):
			if abs(col - cx) + abs(row - cy) <= radius:
				out.append(Vector2i(col, row))
	return out

func has_los(from: Vector2i, to: Vector2i) -> bool:
	return LoS.has_los(self, from, to)

# --- Generation: six passes, fixed seeds, reproducible (terrain spec §6.1) ----
func generate() -> void:
	var base_row := Const.MAP_HEIGHT - Const.BASE_FILL_ROWS

	# Pass 1 — base fill.
	for col in range(Const.MAP_WIDTH):
		for row in range(base_row, Const.MAP_HEIGHT):
			_grid[_idx(col, row)] = Tile.new().setup(Tile.TileType.SOLID, 3, 0)

	# Pass 2 — surface noise. Positive noise raises the surface (lower row index).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = Const.NOISE_SEED
	noise.frequency = Const.NOISE_FREQUENCY
	for col in range(Const.MAP_WIDTH):
		var offset := int(noise.get_noise_1d(float(col)) * Const.SURFACE_VARIATION)
		var surface : int = clampi(base_row - offset, 0, Const.MAP_HEIGHT - 1)
		for row in range(surface, base_row):
			_grid[_idx(col, row)] = Tile.new().setup(Tile.TileType.SOLID, 3, 0)
		for row in range(base_row, surface):
			_grid[_idx(col, row)] = null

	# Pass 3 — cave carving: ellipse subtraction in the underground mass.
	var cave_rng := RandomNumberGenerator.new()
	cave_rng.seed = Const.NOISE_SEED + 1
	for _i in range(Const.CAVE_COUNT):
		var ccol := cave_rng.randi_range(15, Const.MAP_WIDTH - 16)
		var min_row := get_surface_row(ccol) + 10
		var crow := cave_rng.randi_range(min_row, Const.MAP_HEIGHT - 11)
		var rw := cave_rng.randi_range(Const.CAVE_WIDTH_MIN, Const.CAVE_WIDTH_MAX)
		var rh := cave_rng.randi_range(Const.CAVE_HEIGHT_MIN, Const.CAVE_HEIGHT_MAX)
		for col in range(ccol - rw, ccol + rw + 1):
			for row in range(crow - rh, crow + rh + 1):
				if not _in_bounds(col, row):
					continue
				var dx := float(col - ccol) / rw
				var dy := float(row - crow) / rh
				if dx * dx + dy * dy <= 1.0:
					_grid[_idx(col, row)] = null

	# Pass 4 — spawn platform: flat, indestructible, with standing room above.
	var prow := get_surface_row(Const.SPAWN_PLATFORM_COL)
	for col in range(Const.SPAWN_PLATFORM_COL,
			Const.SPAWN_PLATFORM_COL + Const.SPAWN_PLATFORM_WIDTH):
		var t := Tile.new().setup(Tile.TileType.SOLID, 3, 0)
		t.flags = Tile.FLAG_INDESTRUCTIBLE
		t.status_tags = []   # indestructible platform does not burn (M3 §5.4)
		_grid[_idx(col, prow)] = t
		for row in range(maxi(prow - 6, 0), prow):
			_grid[_idx(col, row)] = null

	# Pass 5 — HP assignment: 10% reinforced (HP 6), separately seeded.
	var hp_rng := RandomNumberGenerator.new()
	hp_rng.seed = Const.NOISE_SEED + 99
	for row in range(Const.MAP_HEIGHT):
		for col in range(Const.MAP_WIDTH):
			var t := get_tile(col, row)
			if t == null or t.has_flag(Tile.FLAG_INDESTRUCTIBLE):
				continue
			if hp_rng.randf() < Const.REINFORCED_TILE_CHANCE:
				t.hp = 6
				t.max_hp = 6
				# Reinforced = metal/ore: conducts electricity, does not burn (M3 decision).
				t.status_tags = ["CONDUCTIVE"]

	# Pass 6 — visual variants, cosmetic only.
	var var_rng := RandomNumberGenerator.new()
	var_rng.seed = Const.NOISE_SEED + 7
	for row in range(Const.MAP_HEIGHT):
		for col in range(Const.MAP_WIDTH):
			var t := get_tile(col, row)
			if t != null:
				t.variant = var_rng.randi_range(0, 3)

# Reproducibility stats (plan §3, P2 acceptance): identical across runs at a fixed seed.
func debug_stats() -> String:
	var solid := 0
	for cell in _grid:
		if cell != null:
			solid += 1
	var checksum := 0
	for col in range(Const.MAP_WIDTH):
		checksum = (checksum * 31 + get_surface_row(col) + 1) % 1000000007
	return "solid=%d surface_checksum=%d" % [solid, checksum]
