# Unit status orchestration (M3 spec §4.3). Static — no instance state.
#
# Spec deviation (M3 plan): the spec's tick_all() calls CombatManager.action_bar.spend()
# directly. Our CombatManager uses an `actions_left: int`, not an action_bar object, and
# we keep the dependency one-directional (CombatManager → here). So tick_all() RETURNS the
# total AP reduction and the caller subtracts it from the shared pool.
class_name UnitStatusSystem

## Apply `stacks` of `def` to `unit`. Caps at max_stacks; refreshes duration (deliverable 9).
static func apply(unit: Unit, def: StatusEffectDef, stacks: int = 1) -> void:
	if not Features.unit_statuses_enabled:
		return
	if def == null:
		return
	if unit.active_statuses.has(def.id):
		unit.active_statuses[def.id].apply_stacks(stacks)
	else:
		unit.active_statuses[def.id] = StatusInstance.new(def, stacks)
	unit.queue_redraw()
	EventBus.status_applied.emit(unit, def.id, stacks)

## Tick all statuses on `unit` (called at the correct phase for this unit's side).
## Applies tick damage immediately; returns the total AP reduction for the shared pool.
static func tick_all(unit: Unit) -> int:
	if unit.hp <= 0:
		return 0
	var to_remove : Array[String] = []
	var total_ap_reduction := 0
	var total_tick_damage := 0
	# Damage statuses before healing (resolution order §6); M3 has no healing yet.
	for id in unit.active_statuses:
		var inst : StatusInstance = unit.active_statuses[id]
		var def : StatusEffectDef = inst.definition
		total_tick_damage += def.tick_damage * inst.stacks
		total_ap_reduction += def.ap_reduction * inst.stacks
		EventBus.status_ticked.emit(unit, id, inst.stacks)
		# Persistent effects (M10, e.g. Boosted) never expire by time — only their per-stack
		# damage/AP applies; non-persistent statuses count down and are removed at 0.
		if def.decays_per_turn and inst.tick():
			to_remove.append(id)
	if total_tick_damage > 0:
		unit.take_damage(total_tick_damage)
	for id in to_remove:
		unit.active_statuses.erase(id)
		EventBus.status_removed.emit(unit, id)
	unit.queue_redraw()
	return total_ap_reduction

## Remove all statuses listing `element_id` in their cleansed_by_element field.
static func cleanse_by_element(unit: Unit, element_id: String) -> void:
	var to_remove : Array[String] = []
	for id in unit.active_statuses:
		var def : StatusEffectDef = unit.active_statuses[id].definition
		if def.cleansed_by_element == element_id:
			to_remove.append(id)
	for id in to_remove:
		unit.active_statuses.erase(id)
		EventBus.status_removed.emit(unit, id)
	if not to_remove.is_empty():
		unit.queue_redraw()
