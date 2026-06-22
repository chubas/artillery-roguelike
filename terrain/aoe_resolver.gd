# Stateless AoE resolver (M2 §6.3, extended for elements in M3 §3.4): applies an
# AoEPattern to terrain and units, with per-group element effects (affinity damage,
# unit statuses, tile statuses).
#
# M16: unit damage and terrain dig are separate channels — same salvo, optional
# separate dig_pattern, flat dig_strength (no zone tiers). Terrain is never damaged
# from the unit-damage loop; bypass shots pass dig_strength=0.
#
# Spec deviation (from milestone-2-plan.md): the literal per-voxel loop damages a unit
# once per covered voxel, which one-shots any multi-voxel unit near the center. Instead a
# unit takes damage ONCE per blast, from the DOMINANT group covering it (highest base
# damage = innermost ring). That group's element drives affinity and the applied status.
#
# Feature gating (M3 §2.2): when Features.elements_enabled is false, all groups resolve as
# physical (no affinity, no status) — proving the flag contract.
class_name AoEResolver

static func resolve(terrain: TerrainManager, units: Array, origin: Vector2i,
		pattern: AoEPattern, strength: int, is_enemy: bool, deployables: Array = [],
		dig_strength: int = 0, dig_pattern: AoEPattern = null,
		element_override: ElementDef = null) -> Array:
	var aoe_map := pattern.to_map() if pattern != null else {}
	var affected : Array = []
	var unit_hit : Dictionary = {}         # Unit -> { "dmg": int, "element": ElementDef }
	var deployable_hit : Dictionary = {}   # Deployable -> dmg (M6: no element/affinity — inert)
	var max_dist := 0
	for offset in aoe_map:
		var target : Vector2i = origin + offset
		var group : AoEGroup = aoe_map[offset]
		var element : ElementDef = \
				(element_override if element_override != null else group.element) \
				if Features.elements_enabled else null
		var zone_dmg := _zone_damage(strength, group.multiplier)
		max_dist = maxi(max_dist, absi(offset.x) + absi(offset.y))
		affected.append(target)
		# Tile status from the element (e.g. fire → Burning) on surviving tiles.
		if element and element.tile_status and Features.tile_statuses_enabled:
			TileStatusSystem.apply(terrain, target, element.tile_status)
		# Record dominant group per damageable unit (highest zone damage wins).
		for unit in units:
			if not _should_damage(unit, is_enemy):
				continue
			if not _voxel_in_bbox(target, unit):
				continue
			var prev = unit_hit.get(unit, null)
			if prev == null or zone_dmg > prev["dmg"]:
				unit_hit[unit] = { "dmg": zone_dmg, "element": element }
		# Same dominant-hit rule for deployables (mines, shield generators), flat damage.
		for d in deployables:
			if d.hp <= 0 or not d.contains_voxel(target):
				continue
			var prev_dmg = deployable_hit.get(d, null)
			if prev_dmg == null or zone_dmg > prev_dmg:
				deployable_hit[d] = zone_dmg
	# Terrain dig pass (M16): flat strength across dig footprint, independent of unit zones.
	if dig_strength > 0 and pattern != null:
		var flat_dig := maxi(1, dig_strength)
		var dig_map := _dig_offset_map(pattern, dig_pattern)
		for offset in dig_map:
			var target : Vector2i = origin + offset
			terrain.damage_tile(target.x, target.y, flat_dig)
			max_dist = maxi(max_dist, absi(offset.x) + absi(offset.y))
			if not affected.has(target):
				affected.append(target)
	# Apply the dominant hit to each unit: affinity damage + status.
	for unit in unit_hit:
		var element : ElementDef = unit_hit[unit]["element"]
		var final_dmg := _calc_damage(unit, unit_hit[unit]["dmg"], element)
		unit.take_damage(final_dmg, element)
		EventBus.unit_hit_taken.emit(unit, final_dmg,
				element.id if element else "physical", null)
		if element and element.unit_status and Features.unit_statuses_enabled:
			UnitStatusSystem.apply(unit, element.unit_status, 1)
	for d in deployable_hit:
		d.take_damage(deployable_hit[d])
	# Collapse once, after the whole blast (terrain + unit damage applied).
	terrain.resolve_collapses(units, deployables)
	terrain.aoe_resolved.emit(origin, max_dist, affected)
	EventBus.aoe_resolved.emit(origin, max_dist, affected)
	return affected

# --- Shared helpers (also used by TileStatusSystem ticks) -------------------------

## Friendly fire off (M2): a shot damages only the opposing side's living units.
static func _should_damage(unit: Unit, is_enemy: bool) -> bool:
	if unit.hp <= 0:
		return false
	if is_enemy:
		return unit.is_player     # enemy shot hits players
	return not unit.is_player     # player shot hits enemies

static func _voxel_in_bbox(vox: Vector2i, unit: Unit) -> bool:
	return unit.contains_voxel(vox)

## Offset set for the dig pass: explicit dig_pattern, else the unit-damage footprint.
static func _dig_offset_map(pattern: AoEPattern, dig_pattern: AoEPattern) -> Dictionary:
	var src := dig_pattern if dig_pattern != null else pattern
	return src.to_map() if src != null else {}

## Source strength * zone multiplier (M7), minimum 1 — pattern shape stays untouched
## by magnitude; magnitude comes entirely from the caller's `strength` value.
static func _zone_damage(strength: int, multiplier: float) -> int:
	return maxi(1, int(round(strength * multiplier)))

## Final damage after element affinity (M3 §3.4). Tag rules stack; a unit-specific
## affinity-table entry OVERRIDES tag rules entirely. Minimum 1 damage on any hit.
static func _calc_damage(unit: Unit, base_dmg: int, element: ElementDef) -> int:
	if element == null:
		return base_dmg
	var mult := 1.0
	var tags : Array = unit.definition.tags
	if element.strong_vs_tag != "" and element.strong_vs_tag in tags:
		mult *= 1.5
	if element.weak_vs_tag != "" and element.weak_vs_tag in tags:
		mult *= 0.5
	if element.vs_shielded_mult > 0.0 and "SHIELDED" in tags:
		mult *= element.vs_shielded_mult
	# Unit-specific affinity override takes precedence over tag rules.
	if unit.definition.element_affinities.has(element.id):
		mult = float(unit.definition.element_affinities[element.id])
	return maxi(1, int(base_dmg * mult))
