class_name ArtifactContext
extends RefCounted

var terrain : TerrainManager
var units   : Array   # all active units (player + enemy)
var combat  : Node    # CombatManager — typed as Node to avoid circular reference
