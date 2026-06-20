class_name EssenceContext
extends RefCounted

var unit      : Unit = null           # the unit that OWNS this essence
var terrain   : TerrainManager = null
var all_units : Array = []            # all combat units (player + enemy)
var combat    : Node = null           # CombatManager ref (Node to avoid circular dep)
# Populated by the combat manager before calling on_unit_fired hooks:
var last_shot  : ShotDefinition = null
var last_speed : float = 0.0
