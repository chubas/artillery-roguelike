# Tile status orchestration (M3 spec §5.3). Static. Ticks once per round at round start,
# before the player turn (resolution order §6). Reuses AoEResolver's damage/affinity
# helpers so a burning tile and a fire shell deal damage identically.
class_name TileStatusSystem

## Apply `def` to the tile at `pos`. Refreshes duration if already present. Blocked by a
## tile carrying the def's removed_by_tag (e.g. burning cannot land on LIQUID).
static func apply(terrain: TerrainManager, pos: Vector2i, def: TileStatusDef) -> void:
	if not Features.tile_statuses_enabled or def == null:
		return
	var tile := terrain.get_tile(pos.x, pos.y)
	if tile == null:
		return
	if def.removed_by_tag != "" and tile.has_flag_tag(def.removed_by_tag):
		return
	if tile.tile_statuses.has(def.id):
		tile.tile_statuses[def.id].turns_left = def.duration
		return
	tile.tile_statuses[def.id] = TileStatusInstance.new(def)
	terrain.mark_tile_dirty(pos.x, pos.y)
	EventBus.tile_status_applied.emit(pos.x, pos.y, def.id)

## Tick every tile status on the map once. Called at round start.
static func tick_all(terrain: TerrainManager, units: Array) -> void:
	if not Features.tile_statuses_enabled:
		return
	# Snapshot first: spreads applied during the tick must NOT be processed this round.
	var active : Array = []
	for col in range(terrain.map_width):
		for row in range(terrain.map_height):
			var tile := terrain.get_tile(col, row)
			if tile != null and not tile.tile_statuses.is_empty():
				active.append([Vector2i(col, row), tile])
	for entry in active:
		_tick_tile(terrain, units, entry[0], entry[1])

static func _tick_tile(terrain: TerrainManager, units: Array,
		pos: Vector2i, tile: Tile) -> void:
	var to_remove : Array[String] = []
	for id in tile.tile_statuses:
		var inst : TileStatusInstance = tile.tile_statuses[id]
		var def : TileStatusDef = inst.definition
		# a. Damage units whose bounding box touches this tile (any side — fire burns all).
		#    Tick damage is physical (see TileStatusDef note); the status is applied directly.
		for unit in units:
			if unit.hp <= 0:
				continue
			if AoEResolver._voxel_in_bbox(pos, unit):
				unit.take_damage(def.tick_damage)
				if def.applied_status:
					UnitStatusSystem.apply(unit, def.applied_status, 1)
		# b. Spread to exposed FLAMMABLE neighbours.
		if def.spreads_to_tag != "":
			_spread(terrain, pos, def)
		# c. Electric chain (instant, not spread).
		if "CHAIN" in def.tags:
			_chain_electric(terrain, units, pos, def)
		EventBus.tile_status_ticked.emit(pos.x, pos.y, id)
		# d. Decrement; queue expired.
		if inst.tick():
			to_remove.append(id)
	for id in to_remove:
		tile.tile_statuses.erase(id)
		terrain.mark_tile_dirty(pos.x, pos.y)
		EventBus.tile_status_removed.emit(pos.x, pos.y, id)

static func _spread(terrain: TerrainManager, pos: Vector2i, def: TileStatusDef) -> void:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var npos : Vector2i = pos + offset
		var ntile := terrain.get_tile(npos.x, npos.y)
		if ntile == null:
			continue
		# Decision (M3 plan): fire only spreads to EXPOSED tiles (bordering VOID), so it
		# creeps along the surface instead of tunnelling through buried rock.
		if ntile.has_flag_tag(def.spreads_to_tag) and _is_exposed(terrain, npos):
			apply(terrain, npos, def)

static func _is_exposed(terrain: TerrainManager, pos: Vector2i) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if terrain.get_tile(pos.x + offset.x, pos.y + offset.y) == null:
			return true
	return false

static func _chain_electric(terrain: TerrainManager, units: Array,
		origin: Vector2i, def: TileStatusDef) -> void:
	# Instantly chain through all CONDUCTIVE tiles connected to origin, damaging any unit
	# whose bbox touches a conductive tile in the network.
	var visited : Array[Vector2i] = [origin]
	var queue : Array[Vector2i] = [origin]
	while not queue.is_empty():
		var current : Vector2i = queue.pop_front()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var npos : Vector2i = current + offset
			if npos in visited:
				continue
			var ntile := terrain.get_tile(npos.x, npos.y)
			if ntile == null or not ntile.has_flag_tag("CONDUCTIVE"):
				continue
			visited.append(npos)
			queue.append(npos)
			for unit in units:
				if unit.hp > 0 and AoEResolver._voxel_in_bbox(npos, unit):
					unit.take_damage(def.tick_damage)
