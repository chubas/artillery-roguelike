# The RunState <-> combat translation layer (run-state spec §4). A static utility (same shape as
# AoEResolver / ArtifactSystem) so CombatManager never touches RunState and combat_scene stays thin.
#
#   read  (combat entry): build_squad() turns each non-disabled RunUnitState into a combat Unit.
#   write (combat exit):  write_back() copies each player unit's hp/kills/disabled to its RunUnitState.
#
# Units are built but NOT added to the tree here — CombatManager owns placement and signal wiring.
# The run_state back-reference on each Unit is what makes both directions line up.
class_name CombatBridge

static func build_squad(rs: RunState) -> Array:
	var squad : Array = []
	for rus in rs.squad:
		if rus.is_disabled:
			continue   # disabled units don't deploy (spec §8)
		var u := Unit.new()
		u.definition = load(rus.definition_id)
		u.run_state = rus            # set before add_child so Unit._ready() reads current_hp/kills
		u.is_player = true
		u.display_name = rus.display_name
		u.aim_angle_deg = 45.0       # face the enemy side; CombatManager places it
		squad.append(u)
	return squad

static func write_back(_rs: RunState, player_units: Array) -> void:
	# Each Unit carries its run_state back-reference, so the RunState is updated through those;
	# `_rs` is kept in the signature as the explicit run being written (and for future fields).
	for u in player_units:
		if u.run_state == null:
			continue
		u.run_state.current_hp = u.hp
		u.run_state.kills = u.kills
		if u.hp <= 0:
			u.run_state.is_disabled = true
