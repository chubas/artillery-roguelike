# Deterministic enemy targeting (M45). Replaces accuracy RNG with a telegraphed pipeline:
# at round start each enemy locks a target + a committed firing solution, both shown on hover
# during the player turn, then executes that exact solution on its turn.
#
# TWO INDEPENDENT LAYERS THAT COMPOSE (never collapse them):
#   1. reachable set — who the enemy CAN hit: straight-line LOS from the enemy to each living
#      player; a shot with bypass_terrain ignores cover (all living players reachable).
#   2. targeting rule — who the enemy WANTS to hit among the reachable set.
# SPECIFIC (Taunt/forced) is a command: it ignores the reachable filter and even a dead target's
# corpse (fire-time handling lives in CombatManager).
class_name EnemyTargeting

## Living players the enemy can hit. bypass_terrain shots see through cover.
static func reachable_players(enemy: Unit, players: Array, terrain: TerrainManager) -> Array:
	var out : Array = []
	var shot := enemy.definition.default_shot
	var bypass : bool = shot != null and shot.bypass_terrain
	var from := enemy.center_voxel()
	for p in players:
		if p.hp <= 0:
			continue
		if bypass or terrain == null or LoS.has_los(terrain, from, p.center_voxel()):
			out.append(p)
	return out

## Apply the enemy's rule to a candidate set → the chosen Unit (or null). Deterministic tie-break
## is the set's own order (players array order = lowest index wins).
static func pick_target(enemy: Unit, reachable: Array, players: Array) -> Unit:
	if enemy.targeting_rule == UnitDefinition.TargetingRule.SPECIFIC:
		# A command ignores reachability — target the forced unit regardless of cover.
		return enemy.forced_target
	if reachable.is_empty():
		return null
	match enemy.targeting_rule:
		UnitDefinition.TargetingRule.NEAREST:
			return _by_distance(enemy, reachable, true)
		UnitDefinition.TargetingRule.FARTHEST:
			return _by_distance(enemy, reachable, false)
		UnitDefinition.TargetingRule.WEAKEST:
			return _by_metric(reachable, func(u): return -u.hp)          # lowest current HP
		UnitDefinition.TargetingRule.STRONGEST:
			return _by_metric(reachable, func(u): return u.definition.max_hp)  # highest max HP
		UnitDefinition.TargetingRule.FIXED_LANE:
			# Most aligned with the enemy's column: smallest |Δx|, ignoring distance/HP.
			return _by_metric(reachable, func(u): return -absi(u.center_voxel().x - enemy.center_voxel().x))
		_:
			return _by_distance(enemy, reachable, true)

static func _by_distance(enemy: Unit, cands: Array, nearest: bool) -> Unit:
	var best : Unit = null
	var best_d := INF if nearest else -1.0
	for u in cands:
		var d := Vector2(u.vox_position - enemy.vox_position).length()
		if (nearest and d < best_d) or (not nearest and d > best_d):
			best_d = d
			best = u
	return best

## Highest-scoring candidate (first wins ties → preserves set order).
static func _by_metric(cands: Array, score: Callable) -> Unit:
	var best : Unit = null
	var best_s := -INF
	for u in cands:
		var s : float = float(score.call(u))
		if s > best_s:
			best_s = s
			best = u
	return best

## Telegraph pass: pick each living enemy's target + committed firing solution.
## reset_rules = true (round start) restores each enemy's definition rule, clearing any prior
## one-round override (Taunt). reset_rules = false (mid-round re-run after Taunt) preserves the
## current runtime rule so the override survives within the round it was applied.
static func assign_all(enemies: Array, players: Array, terrain: TerrainManager,
		wind_force_x: float, reset_rules: bool = true) -> void:
	for e in enemies:
		if e.hp <= 0:
			continue
		# M47: no-op attackers (bosses without a shot yet) get no telegraph — they never fire.
		if e.definition.attack_behavior == UnitDefinition.AttackBehavior.NONE:
			e.intended_target = null
			e.intended_solution = {}
			continue
		if reset_rules:
			e.targeting_rule = e.definition.targeting_rule
			e.forced_target = null
		_assign_one(e, players, terrain, wind_force_x)

static func _assign_one(enemy: Unit, players: Array, terrain: TerrainManager,
		wind_force_x: float) -> void:
	var reachable := reachable_players(enemy, players, terrain)
	enemy.intended_target = pick_target(enemy, reachable, players)
	if enemy.intended_target != null and is_instance_valid(enemy.intended_target):
		enemy.intended_solution = EnemySystem.firing_solution(
				enemy, enemy.intended_target, wind_force_x)
	else:
		enemy.intended_solution = {}

## A player unit died: rule-based enemies aiming at it recompute a fresh target; SPECIFIC enemies
## keep the dead target (they will fire at its corpse). Keeps the telegraph live during the turn.
static func reassign_for_dead(enemies: Array, dead: Unit, players: Array,
		terrain: TerrainManager, wind_force_x: float) -> void:
	for e in enemies:
		if e.hp <= 0 or e.intended_target != dead:
			continue
		if e.targeting_rule == UnitDefinition.TargetingRule.SPECIFIC:
			continue   # committed to the specific unit — fire at the corpse
		_assign_one(e, players, terrain, wind_force_x)
