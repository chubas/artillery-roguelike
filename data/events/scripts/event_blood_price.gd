# Blood Price event: take 10 free shards OR sacrifice 3 HP from the highest-HP unit for 20 shards.
class_name EventBloodPrice
extends EventDef

func choices(rs: RunState) -> Array[Dictionary]:
	var target := _pick_sacrifice_target(rs)
	var label_b : String
	var avail_b : bool
	if target == null:
		label_b = "Sacrifice 3 HP for 20 ◆  (no eligible unit)"
		avail_b = false
	else:
		label_b = "Sacrifice 3 HP from %s (%d HP) for 20 ◆" % [target.display_name, target.current_hp]
		avail_b = target.current_hp > 3
	return [
		{ "label": "Take 10 ◆ for free", "available": true },
		{ "label": label_b, "available": avail_b },
	]

func resolve(choice_index: int, rs: RunState) -> void:
	if choice_index == 0:
		rs.resources["shards"] = rs.resources.get("shards", 0) + 10
	else:
		var target := _pick_sacrifice_target(rs)
		if target == null or target.current_hp <= 3:
			return
		target.current_hp -= 3
		rs.resources["shards"] = rs.resources.get("shards", 0) + 20

# Returns the alive unit with the highest current HP (not disabled).
func _pick_sacrifice_target(rs: RunState) -> RunUnitState:
	var best    : RunUnitState = null
	var best_hp : int = 0
	for i in range(rs.squad.size()):
		var u : RunUnitState = rs.squad[i]
		if not u.is_disabled and u.current_hp > best_hp:
			best_hp = u.current_hp
			best = u
	return best
