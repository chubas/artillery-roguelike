# Gravity-pull resolve action (M4): a post-impact step that drags nearby units toward the
# blast. Two concentric bands — units within `pull_near_radius` voxels are hauled
# `pull_near_voxels` steps, those out to `pull_far_radius` get `pull_far_voxels`. Every step
# obeys the SAME movement rules as walking (UnitMovement): a unit pinned against a 2-voxel
# wall doesn't budge, units can't be stacked into the same space, and each settles after.
#
# Units are pulled CLOSEST-FIRST so an inner unit lands before an outer one is dragged into
# the space it just vacated (or blocks it). Affects both sides — anything caught in the field.
class_name GravityPullResolver

static func resolve(terrain: TerrainManager, units: Array,
		impact_voxel: Vector2i, shot: ShotDefinition) -> void:
	var far := shot.pull_far_radius
	if far <= 0:
		return
	# Gather caught units with their distance to the impact (by unit centre).
	var caught : Array = []
	for u in units:
		if u.hp <= 0:
			continue
		var d := Vector2(u.center_voxel() - impact_voxel).length()
		if d <= float(far):
			caught.append({ "unit": u, "dist": d })
	caught.sort_custom(func(a, b): return a["dist"] < b["dist"])

	for entry in caught:
		var u : Unit = entry["unit"]
		var dist : float = entry["dist"]
		var steps := shot.pull_near_voxels if dist <= float(shot.pull_near_radius) \
				else shot.pull_far_voxels
		_pull_unit(terrain, units, u, impact_voxel, steps)

# Walk a unit up to `steps` voxels toward the impact column, one legal step at a time.
# Direction is fixed by the unit's INITIAL side of the impact — the pull is "by N voxels",
# so a unit may be dragged right up to (or just past) the blast, not stopped at alignment.
static func _pull_unit(terrain: TerrainManager, units: Array, unit: Unit,
		impact_voxel: Vector2i, steps: int) -> void:
	var dir := signi(impact_voxel.x - unit.center_voxel().x)
	if dir == 0:
		return   # already on the impact column → nothing horizontal to do
	for _i in range(steps):
		var dest := UnitMovement.resolve_move(unit, dir, terrain, units)
		if dest == UnitMovement.NO_MOVE:
			break   # blocked (wall, edge, or another unit) → stop here
		unit.set_vox_position(dest)
	# Drop into any crater the blast opened beneath the unit.
	var settled := UnitMovement.settle(unit, terrain)
	if settled != unit.vox_position:
		unit.set_vox_position(settled)
