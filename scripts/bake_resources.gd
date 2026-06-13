# Authoring aid (M2 spec §2.2): bakes the .tres data files from generator helpers.
# Run:  godot --headless -s scripts/bake_resources.gd
# The runtime always uses the baked .tres files, never this script.
extends SceneTree

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/shots/aoe")
	DirAccess.make_dir_recursive_absolute("res://data/units")

	# Standard shell AoE: diamond R=2, damage 3/2/1 per ring (spec §2.2).
	var diamond := AoEPattern.make_diamond(2, 3, 1.0)
	_save(diamond, "res://data/shots/aoe/diamond_r2.tres")

	var shell := ShotDefinition.new()
	shell.id = "basic_shell"
	shell.display_name = "Shell"
	shell.base_speed = 600.0
	shell.gravity_scale = 1.0
	shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2.tres")
	shell.action_cost = 0
	shell.uses_per_stage = -1
	shell.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(shell, "res://data/shots/basic_shell.tres")
	var shell_ref : ShotDefinition = load("res://data/shots/basic_shell.tres")

	var heavy := UnitDefinition.new()
	heavy.id = "player_heavy"
	heavy.display_name = "Unit1"
	heavy.width_voxels = 2
	heavy.height_voxels = 3
	heavy.max_hp = 9
	heavy.move_range = 2
	heavy.climb_max = 1
	heavy.default_shot = shell_ref
	heavy.color = Color(0.25, 0.45, 0.9)
	_save(heavy, "res://data/units/player_heavy.tres")

	var light := UnitDefinition.new()
	light.id = "player_light"
	light.display_name = "Unit2"
	light.width_voxels = 1
	light.height_voxels = 3
	light.max_hp = 4
	light.move_range = 4
	light.climb_max = 1
	light.default_shot = shell_ref
	light.color = Color(0.35, 0.75, 0.95)
	_save(light, "res://data/units/player_light.tres")

	var enemy := UnitDefinition.new()
	enemy.id = "enemy_static"
	enemy.display_name = "Enemy"
	enemy.width_voxels = 2
	enemy.height_voxels = 3
	enemy.max_hp = 6
	enemy.move_range = 0   # enemies don't move in M2
	enemy.climb_max = 1
	enemy.default_shot = shell_ref
	enemy.color = Color(0.85, 0.3, 0.25)
	_save(enemy, "res://data/units/enemy_static.tres")

	print("[bake] all resources written")
	quit()

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[bake] FAILED to save %s (err %d)" % [path, err])
	else:
		print("[bake] saved ", path)
