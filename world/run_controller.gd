# Run-level scene-flow controller (M14, run-state spec §7) — the game's main scene. Persists for
# the whole run and swaps its single active child between the MapScreen and a freshly-instanced
# combat_scene. The run state lives in the Run autoload; this controller only reads it to decide
# flow and never touches combat internals. Re-instancing combat_scene per stage IS the per-stage
# reset (fresh Unit nodes — M12), so HP/kills/disabled carry only through RunState.
extends Node

const _COMBAT_SCENE := "res://world/combat_scene.tscn"

var _current : Node = null   # the active MapScreen or combat_scene instance

func _ready() -> void:
	# Smoke mode: skip the map and drop straight into combat, which runs the M4–M14 chain + quits.
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		_enter_combat(null)
		return
	if Run.active == null:
		Run.start_default_run()
	_show_map()

func _swap(node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = node
	add_child(node)

func _show_map() -> void:
	var map_screen := MapScreen.new()
	map_screen.stage_selected.connect(_enter_combat)
	map_screen.new_run_requested.connect(_restart_run)
	_swap(map_screen)
	map_screen.setup(Run.active.map)

# `node` null = smoke / standalone (combat_scene picks its own default stage_01).
func _enter_combat(node: MapNode) -> void:
	var cs : Node = (load(_COMBAT_SCENE) as PackedScene).instantiate()
	if node != null:
		cs.stage = node.stage()   # set before add_child so combat_scene._ready() reads it
	cs.combat_exited.connect(_on_combat_exited)
	_swap(cs)

func _on_combat_exited(outcome: String) -> void:
	# Write-back already happened in combat_scene; the controller advances the run.
	var map : MapState = Run.active.map
	var any_alive := Run.active.squad.any(func(u): return not u.is_disabled)
	if outcome == "cleared" and any_alive:
		map.mark_visited()
		if map.is_last():
			_show_map_end("RUN COMPLETE")
		else:
			map.advance()
			_show_map()
	else:
		_show_map_end("RUN OVER")   # objective failed, or the whole squad is disabled

func _show_map_end(text: String) -> void:
	var map_screen := MapScreen.new()
	map_screen.new_run_requested.connect(_restart_run)
	_swap(map_screen)
	map_screen.setup(Run.active.map)
	map_screen.show_end(text)

func _restart_run() -> void:
	Run.start_default_run()
	_show_map()
