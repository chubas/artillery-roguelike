# A named entity placed on a hand-authored map (M47). Parsed from an `Entity_<name>: ...` line in
# a map file. For now an entity only carries a map coordinate, but `props` is an open key/value bag
# so richer entity definitions (unit id, patrol path, trigger data, ...) can be layered on later
# without changing the parser's shape — see CustomMap._parse_entity.
#
# Combat resolves entities that name a baked unit (id == entity name, lower-cased) into enemy
# units at their coordinate; entities that don't resolve to a unit are left untouched for other
# systems to consume.
class_name MapEntity
extends RefCounted

var name        : String = ""
var coordinates : Vector2i = Vector2i.ZERO
var props       : Dictionary = {}   # arbitrary key/value; "coordinates" mirrored here too
