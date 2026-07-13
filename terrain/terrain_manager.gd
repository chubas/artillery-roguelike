# Owns all tile data and is the only writer of _grid (terrain spec §5, §6, §7, §12).
class_name TerrainManager
extends Node

# --- Signals (terrain spec §12.4) --------------------------------------------
signal tile_damaged(col: int, row: int, dmg: int, remaining_hp: int)
signal tile_destroyed(col: int, row: int, tile_type: int)
signal tile_changed(col: int, row: int)
signal aoe_resolved(center: Vector2i, radius: int, affected: Array)

# --- Dimensions (M32: variable per loaded MapData; default = Const values) ----
var map_width  : int = Const.MAP_WIDTH
var map_height : int = Const.MAP_HEIGHT

func chunks_wide() -> int:
	return int(ceil(float(map_width)  / Const.CHUNK_SIZE))

func chunks_tall() -> int:
	return int(ceil(float(map_height) / Const.CHUNK_SIZE))

# --- Storage (terrain spec §5.1) ---------------------------------------------
var _grid : Array = []   # size map_width*map_height; null = VOID

# Columns that need a collapse pass after tile destruction (batched per blast).
var _pending_collapse_cols : Dictionary = {}

func _ready() -> void:
	_grid.resize(map_width * map_height)
	_grid.fill(null)
	# Generation is driven by the scene (combat_scene) with the active stage's terrain_seed (M13),
	# so the grid is only allocated here — not filled with a fixed-seed map.

func _idx(col: int, row: int) -> int:
	return row * map_width + col

func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < map_width and row >= 0 and row < map_height

# --- Access (terrain spec §12.1) ---------------------------------------------
func get_tile(col: int, row: int) -> Tile:
	if not _in_bounds(col, row):
		return null
	return _grid[_idx(col, row)]

func is_solid(col: int, row: int) -> bool:
	var t := get_tile(col, row)
	# M42: MINERAL veins are standable/support ground like SOLID (they just drop Ore when broken).
	return t != null and (t.type == Tile.TileType.SOLID or t.type == Tile.TileType.MINERAL)

func is_blocked(col: int, row: int) -> bool:
	# Blocked = exists and not passable. In M1 any tile blocks (no flags set).
	var t := get_tile(col, row)
	return t != null and not t.has_flag(Tile.FLAG_PASSABLE)

func get_surface_row(col: int) -> int:
	for row in range(map_height):
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

## M42: convert small clustered blobs of destructible SOLID tiles into MINERAL veins (durability 2),
## deterministic from `seed`. Prefers near-surface placement and guarantees a fraction are exposed on
## the surface. Called once after terrain build in combat_scene._setup_terrain (both gen paths).
func scatter_minerals(seed: int, patch_count: int = 10) -> void:
	if not Features.minerals_enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x0DE501   # distinct stream from terrain gen
	for i in range(patch_count):
		var col := rng.randi_range(2, map_width - 3)
		var surf := get_surface_row(col)
		if surf < 0:
			continue
		# Anchor: ~40% exposed at the surface, the rest buried 1–5 voxels down.
		var anchor_row : int = surf if rng.randf() < 0.4 else clampi(surf + rng.randi_range(1, 5), 0, map_height - 1)
		var blob := rng.randi_range(2, 4)
		for _b in range(blob):
			var c := col + rng.randi_range(-1, 1)
			var r := anchor_row + rng.randi_range(-1, 1)
			var t := get_tile(c, r)
			# Only convert plain destructible SOLID ground — never platform/reinforced/void.
			if t == null or t.type != Tile.TileType.SOLID or t.has_flag(Tile.FLAG_INDESTRUCTIBLE):
				continue
			_grid[_idx(c, r)] = Tile.new().setup(Tile.TileType.MINERAL, 2, 0)
			tile_changed.emit(c, r)

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
	# M42: a broken MINERAL vein drops a collectible Ore at this voxel (OreSystem listens).
	if tile.type == Tile.TileType.MINERAL:
		EventBus.mineral_destroyed.emit(col, row)
	tile_changed.emit(col, row)
	queue_collapse(col)

# --- Collapse (M17): column fall + crush ---------------------------------------

## Mark a column for the next `resolve_collapses()` call (e.g. after manual tile removal).
func queue_collapse(col: int) -> void:
	if col >= 0 and col < map_width:
		_pending_collapse_cols[col] = true

## Process columns queued by recent destroys until stable. Pass living units/deployables so
## falling tiles can crush occupants (damage = tile max_hp). Callable from any hook after
## attacks, actions, or scripted terrain changes — queue columns first if needed.
func resolve_collapses(units: Array = [], deployables: Array = []) -> void:
	if not Features.collapse_enabled:
		_pending_collapse_cols.clear()
		return
	var cols : Array = _pending_collapse_cols.keys()
	_pending_collapse_cols.clear()
	if cols.is_empty():
		return
	_run_collapse_until_stable(cols, units, deployables)

## Scan every column for unsupported collapsible tiles (end-of-turn, transmutation, etc.).
func resolve_all_collapses(units: Array = [], deployables: Array = []) -> void:
	if not Features.collapse_enabled:
		return
	var cols : Array = []
	for c in range(map_width):
		cols.append(c)
	_run_collapse_until_stable(cols, units, deployables)

## Back-compat alias — no occupants, so crush damage is skipped. Prefer resolve_collapses().
func flush_collapses() -> void:
	resolve_collapses([], [])

func _run_collapse_until_stable(cols: Array, units: Array, deployables: Array) -> void:
	while true:
		var any := false
		for col in cols:
			if _collapse_column(col, units, deployables):
				any = true
		if not any:
			break

func _collapse_column(col: int, units: Array, deployables: Array) -> bool:
	# Bottom-up: lower rows (higher index) settle before tiles above them are checked.
	var changed := false
	for row in range(map_height - 2, -1, -1):
		var tile := get_tile(col, row)
		if tile == null:
			continue
		if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE):
			continue
		if not tile.collapsible:
			continue
		if not _is_unsupported(col, row):
			continue
		if _fall_tile(col, row, units, deployables):
			changed = true
	return changed

func _is_unsupported(col: int, row: int) -> bool:
	# Cannot fall past the bottom row.
	if row >= map_height - 1:
		return false
	var below := get_tile(col, row + 1)
	if below != null and _blocks_collapse(below):
		return false
	return true

func _blocks_collapse(tile: Tile) -> bool:
	return not tile.has_flag(Tile.FLAG_PASSABLE)

func _fall_tile(col: int, from_row: int, units: Array, deployables: Array) -> bool:
	var tile := get_tile(col, from_row)
	if tile == null:
		return false
	var crush_dmg := tile.max_hp
	for r in range(from_row + 1, map_height):
		var victims := _occupants_at(col, r, units, deployables)
		if not victims.is_empty():
			_crush(col, from_row, r, crush_dmg, tile, victims)
			return true
		if r < map_height - 1:
			var below := get_tile(col, r + 1)
			if below != null and _blocks_collapse(below):
				if r == from_row:
					return false
				_move_tile(col, from_row, r)
				return true
		else:
			# Bottom row of the map — rest here if empty.
			if r == from_row:
				return false
			_move_tile(col, from_row, r)
			return true
	return false

func _move_tile(col: int, from_row: int, to_row: int) -> void:
	var tile = _grid[_idx(col, from_row)]
	_grid[_idx(col, from_row)] = null
	_grid[_idx(col, to_row)] = tile
	tile_changed.emit(col, from_row)
	tile_changed.emit(col, to_row)

func _crush(col: int, from_row: int, impact_row: int, damage: int,
		tile: Tile, victims: Array) -> void:
	_grid[_idx(col, from_row)] = null
	tile_changed.emit(col, from_row)
	tile_destroyed.emit(col, from_row, tile.type)
	EventBus.tile_destroyed.emit(col, from_row, tile.type)
	for v in victims:
		if v is Unit:
			v.take_damage(damage)
			EventBus.unit_hit_taken.emit(v, damage, "physical", null)
		elif v is Deployable:
			v.take_damage(damage)
	EventBus.terrain_crushed.emit(col, impact_row, damage, victims)

func _occupants_at(col: int, row: int, units: Array, deployables: Array) -> Array:
	var vox := Vector2i(col, row)
	var out : Array = []
	for u in units:
		if u is Unit and u.hp > 0 and u.contains_voxel(vox):
			out.append(u)
	for d in deployables:
		if d is Deployable and d.hp > 0 and d.contains_voxel(vox):
			out.append(d)
	return out

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

# --- M32: Load from MapData ──────────────────────────────────────────────────

func load_map(data: MapData) -> void:
	map_width  = data.width
	map_height = data.height
	_grid.resize(map_width * map_height)
	_grid.fill(null)
	for row in range(map_height):
		for col in range(map_width):
			var cell = data.get_cell(col, row)
			if cell == null:
				continue
			var t := Tile.new()
			t.type        = cell["type"]  as Tile.TileType
			t.hp          = cell["hp"]
			t.max_hp      = cell["max_hp"]
			t.flags       = cell["flags"]
			t.collapsible = cell["collapsible"]
			t.status_tags.assign(cell["status_tags"] as Array)
			t.variant     = cell["variant"]
			_grid[_idx(col, row)] = t

# --- Generation: six passes, seeded, reproducible (terrain spec §6.1) ---------
# `seed` drives the surface noise + the derived cave/HP/variant RNGs, so each stage descriptor
# (M13) gets its own reproducible terrain. Defaults to Const.NOISE_SEED (the historical map).
func generate(seed: int = Const.NOISE_SEED) -> void:
	# Reset to the fixed legacy dimensions and reallocate — this instance may have previously
	# loaded a differently-sized MapData (custom map / profile) via load_map(), and every pass
	# below indexes _grid assuming the classic 120x100 layout.
	map_width  = Const.MAP_WIDTH
	map_height = Const.MAP_HEIGHT
	_grid.resize(map_width * map_height)
	_grid.fill(null)

	var base_row := map_height - Const.BASE_FILL_ROWS

	# Pass 1 — base fill.
	for col in range(map_width):
		for row in range(base_row, map_height):
			_grid[_idx(col, row)] = Tile.new().setup(Tile.TileType.SOLID, 3, 0)

	# Pass 2 — surface noise. Positive noise raises the surface (lower row index).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed
	noise.frequency = Const.NOISE_FREQUENCY
	for col in range(map_width):
		var offset := int(noise.get_noise_1d(float(col)) * Const.SURFACE_VARIATION)
		var surface : int = clampi(base_row - offset, 0, map_height - 1)
		for row in range(surface, base_row):
			_grid[_idx(col, row)] = Tile.new().setup(Tile.TileType.SOLID, 3, 0)
		for row in range(base_row, surface):
			_grid[_idx(col, row)] = null

	# Pass 3 — cave carving: ellipse subtraction in the underground mass.
	var cave_rng := RandomNumberGenerator.new()
	cave_rng.seed = seed + 1
	for _i in range(Const.CAVE_COUNT):
		var ccol := cave_rng.randi_range(15, map_width - 16)
		var min_row := get_surface_row(ccol) + 10
		var crow := cave_rng.randi_range(min_row, map_height - 11)
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
		t.collapsible = false
		t.status_tags = []   # indestructible platform does not burn (M3 §5.4)
		_grid[_idx(col, prow)] = t
		for row in range(maxi(prow - 6, 0), prow):
			_grid[_idx(col, row)] = null

	# Pass 5 — HP assignment: 10% reinforced (HP 6), separately seeded.
	var hp_rng := RandomNumberGenerator.new()
	hp_rng.seed = seed + 99
	for row in range(map_height):
		for col in range(map_width):
			var t := get_tile(col, row)
			if t == null or t.has_flag(Tile.FLAG_INDESTRUCTIBLE):
				continue
			if hp_rng.randf() < Const.REINFORCED_TILE_CHANCE:
				t.hp = 6
				t.max_hp = 6
				# Reinforced = metal/ore: conducts electricity, does not burn (M3 decision).
				t.status_tags = ["CONDUCTIVE"]

	# Pass 6 — visual variants, cosmetic only. collapsible stays false (M17 default);
	# specific tiles opt in via content/transmutation later.
	var var_rng := RandomNumberGenerator.new()
	var_rng.seed = seed + 7
	for row in range(map_height):
		for col in range(map_width):
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
	for col in range(map_width):
		checksum = (checksum * 31 + get_surface_row(col) + 1) % 1000000007
	return "solid=%d surface_checksum=%d" % [solid, checksum]
