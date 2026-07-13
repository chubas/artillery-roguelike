# Pure unit-movement geometry (M2 spec §5.2, extracted in M4). Stateless: every rule
# about where a unit can step — flat walk, 1-voxel climb, fall into pits, unit collision —
# lives here so both player input (CombatManager.try_move) and effects that shove units
# around (GravityPullResolver) resolve movement IDENTICALLY. No action-economy here; callers
# own the action pool and move_range checks.
class_name UnitMovement

const NO_MOVE := Vector2i(-9999, -9999)

# M38: free climb voxels (1 AP) per weight class.
static func free_climb_for_weight(weight: int) -> int:
	if weight <= 0: return 99
	if weight == 1: return 2   # light: 1–2 voxels free, 3rd costs extra AP
	if weight >= 3: return 0   # heavy: no climbing
	return 1                   # medium default

# M38: max climb voxels (2 AP) per weight class.
static func max_climb_for_weight(weight: int) -> int:
	if weight <= 0: return 99
	if weight == 1: return 3   # light: up to 3 voxels with 2 AP
	if weight >= 3: return 0   # heavy: no climbing
	return 2                   # medium: up to 2 voxels with 2 AP

# One horizontal step in `direction` (±1) with climb/fall + unit-collision rules.
# Returns the resulting top-left voxel, or NO_MOVE if the step is illegal.
static func resolve_move(unit: Unit, direction: int,
		terrain: TerrainManager, units: Array) -> Vector2i:
	var w := unit.definition.width_voxels
	var h := unit.definition.height_voxels
	var new_x := unit.vox_position.x + direction
	if new_x < 0 or new_x + w > terrain.map_width:
		return NO_MOVE
	var foot := unit.vox_position.y + h - 1
	# Flat / fall candidate.
	if bbox_terrain_clear(terrain, Vector2i(new_x, foot - h + 1), w, h):
		var f := foot
		while f < terrain.map_height - 1 and not grounded(terrain, new_x, f, w):
			f += 1
		return Vector2i(new_x, f - h + 1)
	# Climb candidates: try ascending 1..max_climb voxels, lowest accessible wins.
	var max_climb := max_climb_for_weight(unit.definition.weight)
	for k in range(1, max_climb + 1):
		var climb_top_left := Vector2i(new_x, foot - h - k + 1)
		if climb_top_left.y < 0:
			break
		if bbox_terrain_clear(terrain, climb_top_left, w, h) \
				and grounded(terrain, new_x, foot - k, w):
			return climb_top_left
	return NO_MOVE

# Vertical-only fall: where the unit lands if terrain under it gives way. Returns the
# settled top-left (may equal the current position).
static func settle(unit: Unit, terrain: TerrainManager) -> Vector2i:
	return settle_at(unit.vox_position, unit.definition.width_voxels,
			unit.definition.height_voxels, terrain)

# Position-only core of settle(), extracted (M6) so non-Unit entities (Deployable)
# can fall using the same rules without needing a UnitDefinition.
static func settle_at(pos: Vector2i, w: int, h: int, terrain: TerrainManager) -> Vector2i:
	var foot := pos.y + h - 1
	while foot < terrain.map_height - 1 and not grounded(terrain, pos.x, foot, w):
		foot += 1
	return Vector2i(pos.x, foot - h + 1)

# --- Shared predicates ------------------------------------------------------------
static func bbox_terrain_clear(terrain: TerrainManager, top_left: Vector2i,
		w: int, h: int) -> bool:
	for col in range(top_left.x, top_left.x + w):
		for row in range(top_left.y, top_left.y + h):
			if terrain.is_blocked(col, row):
				return false
	return true

static func grounded(terrain: TerrainManager, x: int, foot: int, w: int) -> bool:
	if foot >= terrain.map_height - 1:
		return true   # map bottom counts as support
	for col in range(x, x + w):
		if terrain.is_solid(col, foot + 1):
			return true
	return false

static func overlaps_any_unit(units: Array, top_left: Vector2i,
		def: UnitDefinition, exclude: Unit) -> bool:
	var rect := Rect2i(top_left, Vector2i(def.width_voxels, def.height_voxels))
	for u in units:
		if u == exclude or u.hp <= 0:   # dead wrecks don't block
			continue
		var other := Rect2i(u.vox_position,
			Vector2i(u.definition.width_voxels, u.definition.height_voxels))
		if rect.intersects(other):
			return true
	return false

