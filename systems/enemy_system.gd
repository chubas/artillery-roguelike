# Enemy firing logic (M2 spec §7): nearest-target selection + parabola IK.
#
# Spec deviation (documented in milestone-2-plan.md §4.5 area): the spec's §7.3 formula
# `v² = g·dx² / (2·cos²θ·(dx·tanθ − dy))` mixes a y-up textbook derivation with Godot's
# y-down dy, which makes the denominator negative for every reachable target. Here the
# convention is explicit: angle is positive-up, dy_up is positive when the target is
# ABOVE the barrel, and dx is always positive (direction handled separately).
class_name EnemySystem

static func solve_launch_speed(dx: float, dy_up: float, angle_up_rad: float,
		g: float) -> float:
	var cos_a := cos(angle_up_rad)
	var tan_a := tan(angle_up_rad)
	var denom := 2.0 * cos_a * cos_a * (dx * tan_a - dy_up)
	if absf(denom) < 0.001:
		return -1.0   # no solution at this angle
	var v_sq := (g * dx * dx) / denom
	if v_sq <= 0.0:
		return -1.0   # target not reachable on this parabola branch
	return sqrt(v_sq)

static func nearest_living_player(enemy: Unit, players: Array) -> Unit:
	var nearest : Unit = null
	var min_dist := INF
	for unit in players:
		if unit.hp <= 0:
			continue
		var dist := Vector2(unit.vox_position - enemy.vox_position).length()
		if dist < min_dist:
			min_dist = dist
			nearest = unit
	return nearest

# Computes the IK firing solution for enemy → target.
# Returns {} if no solution at either angle.
static func firing_solution(enemy: Unit, target: Unit) -> Dictionary:
	var barrel := enemy.barrel_origin_world()
	var tgt := target.center_world()
	var dx := absf(tgt.x - barrel.x)
	var dy_up := barrel.y - tgt.y   # positive = target above barrel
	var side := -1.0 if tgt.x < barrel.x else 1.0
	var g := Const.GRAVITY * enemy.definition.default_shot.gravity_scale
	for angle_deg in [Const.ENEMY_LAUNCH_ANGLE_DEG, Const.ENEMY_ALT_ANGLE_DEG]:
		var a := deg_to_rad(angle_deg)
		var speed := solve_launch_speed(dx, dy_up, a, g)
		if speed > 0.0:
			return {
				"speed": speed,
				"direction": Vector2(cos(a) * side, -sin(a)),
				"angle_deg": angle_deg,
			}
	return {}

# Fires one enemy at the nearest player. Returns true if a shot was fired.
static func fire_enemy(enemy: Unit, players: Array, projectiles: ProjectileManager,
		with_error: bool = true) -> bool:
	var target := nearest_living_player(enemy, players)
	if target == null:
		return false
	var sol := firing_solution(enemy, target)
	if sol.is_empty():
		push_warning("Enemy %s: no firing solution" % enemy.display_name)
		return false
	var speed : float = sol["speed"]
	if with_error:
		speed *= 1.0 + randf_range(-Const.ENEMY_ERROR_PCT, Const.ENEMY_ERROR_PCT)
	speed = clampf(speed, Const.ENEMY_SPEED_MIN, Const.ENEMY_SPEED_MAX)
	projectiles.fire(enemy.barrel_origin_world(), sol["direction"], speed,
			enemy.definition.default_shot, true, enemy)
	return true
