# Data definition of a keyword (M41): a named, reusable mechanic that can appear on a unit, shot,
# or card, and can transfer between them (e.g. the Boosted card grants the Boosted keyword to a
# unit). Immutable data; the live "does this entity have keyword X right now?" question is answered
# by KeywordRegistry collectors, not stored on the entity.
#
# Shield and armor are deliberately NOT keywords (for now). Keyword ids are shared with any backing
# system by convention — e.g. the `boosted` keyword shares its id with the `boosted` StatusEffectDef,
# so a unit carrying that status surfaces the keyword automatically.
class_name KeywordDef
extends Resource

@export var id : String = ""
@export var display_name : String = ""
@export var description_template : String = ""
@export var color : Color = Color(0.8, 0.85, 1.0)

func resolve_description() -> String:
	return description_template
