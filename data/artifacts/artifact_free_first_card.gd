class_name ArtifactFreeFirstCard
extends ArtifactDef

var _state : Dictionary = { "triggered": false }

func modify_card_cost(ctx: ArtifactContext, card: CardDefinition, base_cost: int) -> int:
	if _state["triggered"]:
		return base_cost
	_state["triggered"] = true
	return 0

func reset_per_combat() -> void:
	_state["triggered"] = false
