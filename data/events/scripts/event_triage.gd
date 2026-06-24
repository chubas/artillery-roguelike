# Field Triage event: heal one critical unit fully (even from dead) OR restore 2 HP to everyone.
class_name EventTriage
extends EventDef

func choices(rs: RunState) -> Array[Dictionary]:
	var target := _pick_heal_target(rs)
	var label_a : String
	if target == null:
		label_a = "No unit needs healing"
	else:
		label_a = "Restore %s to full HP" % target.display_name
	return [
		{ "label": label_a, "available": target != null },
		{ "label": "Restore 2 HP to all units", "available": true },
	]

func resolve(choice_index: int, rs: RunState) -> void:
	if choice_index == 0:
		var target := _pick_heal_target(rs)
		if target == null:
			return
		target.current_hp = target.max_hp
		target.is_disabled = false
	else:
		for i in range(rs.squad.size()):
			var u : RunUnitState = rs.squad[i]
			u.current_hp = mini(u.current_hp + 2, u.max_hp)

# Prefers a dead unit; falls back to the unit with the most missing HP.
func _pick_heal_target(rs: RunState) -> RunUnitState:
	var dead_pick  : RunUnitState = null
	var hurt_pick  : RunUnitState = null
	var most_missing : int = 0
	for i in range(rs.squad.size()):
		var u : RunUnitState = rs.squad[i]
		if u.is_disabled:
			if dead_pick == null:
				dead_pick = u
		else:
			var missing := u.max_hp - u.current_hp
			if missing > most_missing:
				most_missing = missing
				hurt_pick = u
	return dead_pick if dead_pick != null else hurt_pick
