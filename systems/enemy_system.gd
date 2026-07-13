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

# Computes the deterministic IK firing solution for enemy → a world point, accounting for the
# forecast wind (M45). The projectile integrates constant accel (ax, g): ax = wind_force_x
# (px/s², projectile.gd), g = GRAVITY * gravity_scale. At a fixed launch angle `a` with
# side = sign(dx), cx = cos(a)*side, sy = -sin(a), X = dx, Yd = dy (screen y-down):
#   t² = 2·(Yd − (sy/cx)·X) / (g − (sy/cx)·ax);  v = (X − 0.5·ax·t²) / (cx·t)
# accepted when t² > 0 and v > 0. Reduces to the no-wind ballistic solve when ax = 0.
# Returns {} if no solution at either angle.
static func firing_solution(enemy: Unit, target: Unit, wind_force_x: float = 0.0) -> Dictionary:
	return solution_to_point(enemy, target.center_world(), wind_force_x)

static func solution_to_point(enemy: Unit, tgt: Vector2, wind_force_x: float = 0.0) -> Dictionary:
	var barrel := enemy.barrel_origin_world()
	var x_signed := tgt.x - barrel.x
	var yd := tgt.y - barrel.y            # screen y-down: positive = target below barrel
	var side := -1.0 if x_signed < 0.0 else 1.0
	var g := Const.GRAVITY * enemy.definition.default_shot.gravity_scale
	for angle_deg in [Const.ENEMY_LAUNCH_ANGLE_DEG, Const.ENEMY_ALT_ANGLE_DEG]:
		var a := deg_to_rad(angle_deg)
		var cx := cos(a) * side
		var sy := -sin(a)
		if absf(cx) < 0.0001:
			continue
		var ratio := sy / cx
		var denom := g - ratio * wind_force_x
		if absf(denom) < 0.0001:
			continue
		var t_sq := 2.0 * (yd - ratio * x_signed) / denom
		if t_sq <= 0.0:
			continue
		var t := sqrt(t_sq)
		var v := (x_signed - 0.5 * wind_force_x * t_sq) / (cx * t)
		if v <= 0.0:
			continue
		v = clampf(v, Const.ENEMY_SPEED_MIN, Const.ENEMY_SPEED_MAX)
		return {
			"speed": v,
			"direction": Vector2(cx, sy),
			"angle_deg": angle_deg,
		}
	return {}

# Legacy flag-off path (Features.enemy_targeting_enabled = false): fire deterministically at the
# nearest player, no accuracy RNG. The telegraphed pipeline in EnemyTargeting supersedes this.
static func fire_enemy(enemy: Unit, players: Array, projectiles: ProjectileManager,
		wind_force_x: float = 0.0) -> bool:
	var target := nearest_living_player(enemy, players)
	if target == null:
		return false
	var sol := firing_solution(enemy, target, wind_force_x)
	if sol.is_empty():
		push_warning("Enemy %s: no firing solution" % enemy.display_name)
		return false
	projectiles.fire(enemy.barrel_origin_world(), sol["direction"], sol["speed"],
			enemy.definition.default_shot, true, enemy)
	return true
