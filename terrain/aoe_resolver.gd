# Stateless AoE resolver (M2 spec §6.3): applies an AoEPattern to terrain and units.
#
# Spec deviation (documented in milestone-2-plan.md): the spec's literal loop damages a
# unit once per covered voxel, which stacks to a near-guaranteed one-shot for any
# multi-voxel unit near the center. Instead a unit takes damage ONCE per blast, using
# the highest group damage among its covered voxels.
class_name AoEResolver

static func resolve(terrain: TerrainManager, units: Array, origin: Vector2i,
		pattern: AoEPattern, is_enemy: bool) -> Array:
	var aoe_map := pattern.to_map()
	var affected : Array = []
	var unit_damage : Dictionary = {}   # Unit -> max group damage
	var max_dist := 0
	for offset in aoe_map:
		var target : Vector2i = origin + offset
		var group : AoEGroup = aoe_map[offset]
		max_dist = maxi(max_dist, abs(offset.x) + abs(offset.y))
		terrain.damage_tile(target.x, target.y, group.damage)
		affected.append(target)
		for unit in units:
			if unit.hp <= 0:
				continue
			# Friendly fire off in M2 (spec §6.3 note).
			if is_enemy and not unit.is_player:
				continue
			if not is_enemy and unit.is_player:
				continue
			if unit.contains_voxel(target):
				unit_damage[unit] = maxi(unit_damage.get(unit, 0), group.damage)
	for unit in unit_damage:
		unit.take_damage(unit_damage[unit])
	# Collapse once, after the whole blast (terrain + unit damage applied).
	terrain.flush_collapses()
	terrain.aoe_resolved.emit(origin, max_dist, affected)
	return affected
