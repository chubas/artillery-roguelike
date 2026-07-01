# Owns collectible Ore drops for one combat (M42): spawning from broken MINERAL veins, settling them
# onto the surface with per-column merging, collection by a stepping player unit, and snapshot/restore
# for move-undo. Ore nodes are parented under `_layer` (drawn above units/deployables).
#
# Flow: TerrainManager._destroy_tile emits EventBus.mineral_destroyed → spawn_at() (unsettled). The
# blast's collapse finishes and emits EventBus.aoe_resolved → settle_all() drops + merges Ore onto
# the freshly settled surface. Collection happens in CombatManager.try_move via try_collect().
class_name OreSystem
extends RefCounted

const ORE_CURRENCY := 2   # currency granted per source mineral voxel

var _terrain : TerrainManager
var _layer   : Node2D
var _ores    : Array = []   # Array[Ore]

func setup(terrain: TerrainManager, layer: Node2D, connect_signals: bool = true) -> void:
	_terrain = terrain
	_layer = layer
	if connect_signals:
		EventBus.mineral_destroyed.connect(_on_mineral_destroyed)
		EventBus.aoe_resolved.connect(_on_aoe_resolved)

func _on_mineral_destroyed(col: int, row: int) -> void:
	if not Features.minerals_enabled:
		return
	spawn_at(col, row)

func _on_aoe_resolved(_center: Vector2i, _radius: int, _affected: Array) -> void:
	settle_all()

## Create a fresh 1-value Ore at a voxel (unsettled — settle_all() moves it to the surface).
func spawn_at(col: int, row: int) -> Ore:
	var ore := Ore.new().setup(Vector2i(col, row), 1)
	_ores.append(ore)
	if _layer != null:
		_layer.add_child(ore)
	return ore

## Apply gravity to every Ore: each falls straight down one voxel at a time until it rests on a
## blocking terrain tile (or the map floor). An Ore that lands on the voxel occupied by another Ore
## MERGES into it (values sum) instead of stacking. Buried Ore with terrain below stays put — it
## never rises. Idempotent; run after each blast's collapse (EventBus.aoe_resolved).
func settle_all() -> void:
	if _terrain == null:
		return
	var changed := true
	while changed:
		changed = false
		var removed : Array = []
		for ore in _ores:
			if removed.has(ore):
				continue
			var below := Vector2i(ore.vox_position.x, ore.vox_position.y + 1)
			if below.y >= _terrain.map_height:
				continue   # resting on the map floor
			var t := _terrain.get_tile(below.x, below.y)
			if t != null and not t.has_flag(Tile.FLAG_PASSABLE):
				continue   # resting on solid terrain
			var other := _ore_at(below, ore, removed)
			if other != null:
				other.value += ore.value
				other.set_vox_position(other.vox_position)   # refresh label
				removed.append(ore)
				changed = true
			else:
				ore.set_vox_position(below)
				changed = true
		for ore in removed:
			_ores.erase(ore)
			ore.queue_free()

## The Ore occupying `vox` (excluding `skip` and any pending-removal), or null.
func _ore_at(vox: Vector2i, skip: Ore, removed: Array) -> Ore:
	for ore in _ores:
		if ore == skip or removed.has(ore):
			continue
		if ore.vox_position == vox:
			return ore
	return null

## A living player unit collects an Ore that is within its footprint OR sitting in the voxel row
## directly below its base (so drops that fell into a 1-voxel pit at the unit's feet are reachable).
func _unit_can_reach(unit: Unit, ore_vox: Vector2i) -> bool:
	var vp := unit.vox_position
	var w : int = unit.definition.width_voxels
	var h : int = unit.definition.height_voxels
	# Same column span; rows from the top of the footprint down to one voxel below the base.
	return ore_vox.x >= vp.x and ore_vox.x < vp.x + w \
		and ore_vox.y >= vp.y and ore_vox.y <= vp.y + h

## If a living player unit can reach an Ore, collect it: grant currency, remove the Ore.
func try_collect(unit: Unit) -> void:
	if not Features.minerals_enabled or unit == null or not unit.is_player or unit.hp <= 0:
		return
	var collected : Array = []
	for ore in _ores:
		if _unit_can_reach(unit, ore.vox_position):
			collected.append(ore)
	for ore in collected:
		if Run.active != null:
			Run.active.add_currency(ore.value * ORE_CURRENCY)
		EventBus.ore_collected.emit(ore.value)
		_ores.erase(ore)
		ore.queue_free()

# --- Undo snapshot/restore (M42) ----------------------------------------------

## Capture the current Ore set as plain data for a move checkpoint.
func snapshot() -> Array:
	var snap : Array = []
	for ore in _ores:
		snap.append({ "vox": ore.vox_position, "value": ore.value })
	return snap

## Rebuild the Ore set from a snapshot (undo): clears live Ore, re-creates from data.
func restore(snap: Array) -> void:
	for ore in _ores:
		ore.queue_free()
	_ores.clear()
	for d in snap:
		var ore := Ore.new().setup(d["vox"], d["value"])
		_ores.append(ore)
		if _layer != null:
			_layer.add_child(ore)

func ore_count() -> int:
	return _ores.size()
