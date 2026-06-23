# Builds one Chunk child per CHUNK_SIZE region and routes tile_changed → dirty chunk (plan §2).
class_name TerrainRenderer
extends Node2D

var _terrain : TerrainManager
var _chunks : Array = []   # Array[Chunk], indexed chunks_wide*cy + cx

func setup(terrain: TerrainManager) -> void:
	_terrain = terrain
	_build_chunks()
	_terrain.tile_changed.connect(_on_tile_changed)

func _build_chunks() -> void:
	for cy in range(_terrain.chunks_tall()):
		for cx in range(_terrain.chunks_wide()):
			var c := Chunk.new().setup(cx, cy, _terrain)
			add_child(c)
			_chunks.append(c)

func mark_all_dirty() -> void:
	for c in _chunks:
		c.mark_dirty()

func _on_tile_changed(col: int, row: int) -> void:
	var cx := int(floor(float(col) / Const.CHUNK_SIZE))
	var cy := int(floor(float(row) / Const.CHUNK_SIZE))
	var i := cy * _terrain.chunks_wide() + cx
	if i >= 0 and i < _chunks.size() and _chunks[i] != null:
		_chunks[i].mark_dirty()
