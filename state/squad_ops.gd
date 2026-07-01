# Map-screen squad actions (M27): repair disabled units and retire any unit for Shards.
# Static utility — smoke-testable without a scene tree.
class_name SquadOps

const REPAIR_COST    := 5
const RETIRE_REFUND  := 2
const FUSION_REFUND  : int = 5   # M36: set to 0 to test no-reward fuse

static func used_capacity(rs: RunState) -> int:
	var total := 0
	for u in rs.squad:
		var def := load(u.definition_id) as UnitDefinition
		if def != null:
			total += def.capacity_cost
	return total

static func can_repair(rs: RunState, unit: RunUnitState) -> bool:
	return unit.is_disabled and rs.can_afford(REPAIR_COST)

static func can_retire(_unit: RunUnitState) -> bool:
	return true

static func repair_unit(rs: RunState, index: int) -> bool:
	if index < 0 or index >= rs.squad.size():
		return false
	var unit : RunUnitState = rs.squad[index]
	if not can_repair(rs, unit):
		return false
	rs.spend_currency(REPAIR_COST)
	unit.is_disabled = false
	unit.current_hp = unit.max_hp
	return true

static func retire_unit(rs: RunState, index: int) -> bool:
	if index < 0 or index >= rs.squad.size():
		return false
	rs.squad.remove_at(index)
	rs.add_currency(RETIRE_REFUND)
	return true

## M36: fuse source unit into target — transfers equipped_essences, removes source, grants FUSION_REFUND shards.
## Does NOT call retire_unit (which only gives 2◆ and has different semantics).
static func fuse_units(rs: RunState, source_idx: int, target_idx: int) -> bool:
	if source_idx == target_idx: return false
	if source_idx < 0 or source_idx >= rs.squad.size(): return false
	if target_idx < 0 or target_idx >= rs.squad.size(): return false
	var src : RunUnitState = rs.squad[source_idx]
	var tgt : RunUnitState = rs.squad[target_idx]
	tgt.equipped_essences.append_array(src.equipped_essences)
	rs.squad.remove_at(source_idx)
	rs.add_currency(FUSION_REFUND)
	return true
