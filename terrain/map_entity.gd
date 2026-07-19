# A named entity imported from an LDtk Entity layer. The importer preserves identity, placement,
# source layer, and arbitrary custom fields; gameplay systems decide what each entity means.
#
# Combat resolves entities that name a baked unit (id == entity name, lower-cased) into enemy
# units at their coordinate; entities that don't resolve to a unit are left untouched for other
# systems to consume.
class_name MapEntity
extends Resource

@export var name         : String = ""
@export var iid          : String = ""
@export var source_layer : String = ""
@export var coordinates  : Vector2i = Vector2i.ZERO
@export var props        : Dictionary = {}
