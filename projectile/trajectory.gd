# Shared ballistic math: the live projectile and the charge preview both use these,
# so the preview arc is exactly what the shot will do (general spec §4.2 preview-on).
class_name Trajectory

# Half-voxel DDA sample along a movement segment (terrain spec §9.2).
static func check_segment(terrain: TerrainManager, from: Vector2, to: Vector2) -> Dictionary:
	var step_count := int(from.distance_to(to) / (Const.VOXEL_SIZE * 0.5)) + 1
	for i in range(1, step_count + 1):
		var t := float(i) / step_count
		var pt := from.lerp(to, t)
		var vox := Const.world_to_voxel(pt)
		if terrain.is_blocked(vox.x, vox.y):
			return {
				"collided": true,
				"impact_voxel": vox,   # face contact: hit voxel IS the AoE center (§9.3)
				"contact_point": pt,
			}
	return { "collided": false, "impact_voxel": Vector2i.ZERO, "contact_point": Vector2.ZERO }

# Full-arc simulation at the physics timestep. Mirrors Projectile._physics_process
# exactly (velocity integrated before position, same collision stepping).
# Returns { hit: bool, impact_voxel: Vector2i, points: PackedVector2Array }.
# ignore_terrain (M4 bypass preview): never stops on terrain — the ghost flies through to the
# map edge, mirroring a drill shot. The footprint is then placed by the caller (e.g. at a unit).
static func simulate_arc(terrain: TerrainManager, origin: Vector2, direction: Vector2,
		speed: float, gravity_scale: float = 1.0, max_time: float = 8.0,
		ignore_terrain: bool = false, wind_force_x: float = 0.0) -> Dictionary:
	var dt := 1.0 / 60.0
	var pos := origin
	var vel := direction.normalized() * speed
	var points := PackedVector2Array([pos])
	var w := Const.world_pixel_size()
	var t := 0.0
	while t < max_time:
		vel.y += Const.GRAVITY * gravity_scale * dt
		vel.x += wind_force_x * dt
		var next := pos + vel * dt
		if not ignore_terrain:
			var hit := check_segment(terrain, pos, next)
			if hit["collided"]:
				points.append(hit["contact_point"])
				return { "hit": true, "impact_voxel": hit["impact_voxel"], "points": points }
		pos = next
		points.append(pos)
		if pos.x < 0 or pos.x > w.x or pos.y > w.y:
			break
		t += dt
	return { "hit": false, "impact_voxel": Vector2i.ZERO, "points": points }
