# Map validation (M43, terrain-generation v0.2 §7): checks a finished MapData against the
# mechanical preconditions of its profile's terrain story. Returns "" on pass, else a short
# failure reason. TerrainGenerator rerolls with a derived seed on failure (bounded attempts).
# Generation is not provably correct — it is CHECKED: cheap whole-map checks here, plus each
# placer's own validate() for feature-specific function.
class_name MapValidator

## Total dig hits allowed on the cheapest route before "reachable" fails (tune in sandbox).
const DIG_BUDGET := 40
## Max free vertical rise between adjacent columns without digging (medium climb).
const CLIMB := 2
## Unit clearance for zone anchors (largest unit convention: 2 wide x 3 tall).
const UNIT_W := 2
const UNIT_H := 3

static func validate(data: MapData, profile: TerrainProfile) -> String:
	var reason := _check_reachability(data, profile)
	if reason != "":
		return reason
	reason = _check_zone_clearance(data)
	if reason != "":
		return reason
	for inst in data.features:
		var placer_script = TerrainGenerator.PLACERS.get(inst.type)
		if placer_script == null:
			continue
		reason = placer_script.new().validate(data, inst)
		if reason != "":
			return reason
	return ""

# ── Reachability: spawn platform -> enemy zone, dig-cost weighted ─────────────
# Dijkstra over columns standing on the surface. Moving to an adjacent column is free when
# the rise is within CLIMB (drops are always free); a taller rise costs the HP of the tiles
# that must be dug off the target column to bring it within climb range. Indestructible
# rises above CLIMB block the route.

static func _check_reachability(data: MapData, profile: TerrainProfile) -> String:
	var surf : Array = []
	surf.resize(data.width)
	for col in range(data.width):
		surf[col] = FeaturePlacer.surface_row(data, col)

	var start := clampi(Const.SPAWN_PLATFORM_COL + Const.SPAWN_PLATFORM_WIDTH / 2,
			0, data.width - 1)
	var enemy_start := int(profile.enemy_zone_start * data.width)
	var enemy_end   := mini(int(profile.enemy_zone_end * data.width), data.width - 1)

	var cost : Array = []
	cost.resize(data.width)
	cost.fill(-1)
	cost[start] = 0
	var frontier : Array = [start]
	while not frontier.is_empty():
		# Cheapest-first (widths <= 240; a linear scan is fine)
		var best_i := 0
		for i in range(1, frontier.size()):
			if cost[frontier[i]] < cost[frontier[best_i]]:
				best_i = i
		var col : int = frontier.pop_at(best_i)
		if col >= enemy_start and col <= enemy_end:
			return ""
		for dir in [-1, 1]:
			var next : int = col + dir
			if next < 0 or next >= data.width:
				continue
			var step := _step_cost(data, surf, col, next)
			if step < 0:
				continue   # blocked (indestructible rise)
			var total : int = cost[col] + step
			if total > DIG_BUDGET:
				continue
			if cost[next] == -1 or total < cost[next]:
				cost[next] = total
				if not frontier.has(next):
					frontier.append(next)
	return "enemy zone unreachable within dig budget %d" % DIG_BUDGET

static func _step_cost(data: MapData, surf: Array, from: int, to: int) -> int:
	var rise : int = surf[from] - surf[to]   # positive = target column is higher
	if rise <= CLIMB:
		return 0
	# Dig the target column's top tiles down until the rise is within climb range.
	var dig := 0
	for row in range(surf[to], surf[to] + rise - CLIMB):
		var cell = data.get_cell(to, row)
		if cell == null:
			continue
		if (cell.get("flags", 0) as int) & Tile.FLAG_INDESTRUCTIBLE:
			return -1
		dig += cell.get("hp", 0) as int
	return dig

# ── Zone-anchor clearance: every Rect2i anchor fits a UNIT_W x UNIT_H open block ──

static func _check_zone_clearance(data: MapData) -> String:
	for inst in data.features:
		for name in inst.anchors:
			var value = inst.anchors[name]
			if not value is Rect2i:
				continue
			if not _zone_fits_unit(data, value):
				return "%s.%s: zone has no %dx%d clearance" % [inst.id, name, UNIT_W, UNIT_H]
	return ""

static func _zone_fits_unit(data: MapData, zone: Rect2i) -> bool:
	for col in range(zone.position.x, zone.end.x - UNIT_W + 1):
		for row in range(zone.position.y, zone.end.y - UNIT_H + 1):
			var clear := true
			for dc in range(UNIT_W):
				for dr in range(UNIT_H):
					if not FeaturePlacer.is_open(data, col + dc, row + dr):
						clear = false
						break
				if not clear:
					break
			if clear:
				return true
	return false
