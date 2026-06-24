# Base class for out-of-combat event nodes. Subclasses implement choices() and resolve().
# Baked as .tres resources and referenced by MapNode.event_path.
class_name EventDef
extends Resource

@export var event_id    : String = ""
@export var title       : String = ""
@export var description : String = ""
@export var act_tags    : Array[String] = ["act_1"]

## Returns choice descriptors for the event screen.
## Each dict: { label: String, available: bool }
## Called at display time so dynamic content (unit names, HP) is current.
func choices(_rs: RunState) -> Array[Dictionary]:
	return []

## Apply the chosen option to the run state. choice_index matches choices() order.
func resolve(_choice_index: int, _rs: RunState) -> void:
	pass
