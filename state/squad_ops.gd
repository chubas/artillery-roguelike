# Map-screen squad actions (M27): repair disabled units and retire any unit for Shards.
# Static utility — smoke-testable without a scene tree.
class_name SquadOps

const REPAIR_COST := 5
const RETIRE_REFUND := 2

static func used_capacity(rs: RunState) -> int:
	var total := 0
	for u in rs.squad:
		var def := load(u.definition_id) as UnitDefinition
		if def != null:
			total += def.capacity_cost
	return total

static func can_repair(rs: RunState, unit: RunUnitState) -> bool:
	return unit.is_disabled and rs.resources.get("shards", 0) >= REPAIR_COST

static func can_retire(_unit: RunUnitState) -> bool:
	return true

static func repair_unit(rs: RunState, index: int) -> bool:
	if index < 0 or index >= rs.squad.size():
		return false
	var unit : RunUnitState = rs.squad[index]
	if not can_repair(rs, unit):
		return false
	rs.resources["shards"] = rs.resources.get("shards", 0) - REPAIR_COST
	unit.is_disabled = false
	unit.current_hp = unit.max_hp
	return true

static func retire_unit(rs: RunState, index: int) -> bool:
	if index < 0 or index >= rs.squad.size():
		return false
	rs.squad.remove_at(index)
	rs.resources["shards"] = rs.resources.get("shards", 0) + RETIRE_REFUND
	return true
