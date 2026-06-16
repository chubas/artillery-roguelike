# Authoring aid (M2 §2.2, extended M3): bakes every .tres data file from generators.
# Run:  godot --headless --import   (once, to register class_names)
# then: godot --headless -s scripts/bake_resources.gd
# The runtime always uses the baked .tres files, never this script.
#
# Reference graph is a clean DAG: fire → {burn, burning}; burning → burn; burn → ∅.
# (See TileStatusDef note: we store applied_status, not a back-reference to the element,
#  precisely to avoid a load-breaking fire ↔ burning cycle.) So a single pass suffices.
extends SceneTree

func _initialize() -> void:
	for d in ["res://data/elements", "res://data/statuses", "res://data/tile_statuses",
			"res://data/shots/aoe", "res://data/units", "res://data/cards"]:
		DirAccess.make_dir_recursive_absolute(d)

	# ── Unit statuses (leaf — no refs) ────────────────────────────────────────
	var burn := StatusEffectDef.new()
	burn.id = "burn"; burn.display_name = "Burn"
	burn.max_stacks = 3; burn.duration = 2; burn.tick_damage = 1; burn.ap_reduction = 0
	burn.tags = ["FIRE"]
	_save(burn, "res://data/statuses/burn.tres")

	var shock := StatusEffectDef.new()
	shock.id = "shock"; shock.display_name = "Shock"
	shock.max_stacks = 3; shock.duration = 1; shock.tick_damage = 0; shock.ap_reduction = 1
	shock.tags = ["ELECTRIC"]
	_save(shock, "res://data/statuses/shock.tres")

	# ── Tile statuses (→ unit status to apply) ────────────────────────────────
	var burning := TileStatusDef.new()
	burning.id = "burning"; burning.display_name = "Burning"
	burning.duration = 3; burning.tick_damage = 1
	burning.applied_status = load("res://data/statuses/burn.tres")
	burning.tags = ["SPREADABLE", "FIRE"]
	burning.spreads_to_tag = "FLAMMABLE"; burning.removed_by_tag = "LIQUID"
	_save(burning, "res://data/tile_statuses/burning.tres")

	var electrified := TileStatusDef.new()
	electrified.id = "electrified"; electrified.display_name = "Electrified"
	electrified.duration = 2; electrified.tick_damage = 1
	electrified.applied_status = load("res://data/statuses/shock.tres")
	electrified.tags = ["CHAIN", "ELECTRIC"]
	electrified.spreads_to_tag = ""; electrified.removed_by_tag = ""
	_save(electrified, "res://data/tile_statuses/electrified.tres")

	# ── Elements (→ unit status + tile status) ────────────────────────────────
	var fire := ElementDef.new()
	fire.id = "fire"; fire.display_name = "Fire"
	fire.unit_status = load("res://data/statuses/burn.tres")
	fire.tile_status = load("res://data/tile_statuses/burning.tres")
	fire.strong_vs_tag = "ORGANIC"; fire.vs_shielded_mult = 0.0
	_save(fire, "res://data/elements/fire.tres")

	var electric := ElementDef.new()
	electric.id = "electric"; electric.display_name = "Electric"
	electric.unit_status = load("res://data/statuses/shock.tres")
	electric.tile_status = load("res://data/tile_statuses/electrified.tres")
	electric.strong_vs_tag = "MECHANICAL"; electric.vs_shielded_mult = 2.0
	_save(electric, "res://data/elements/electric.tres")

	# ── AoE patterns (diamond R=2, 3/2/1 per ring) ────────────────────────────
	_save(AoEPattern.make_diamond(2, 3, 1.0), "res://data/shots/aoe/diamond_r2.tres")
	_save(_elemental_diamond(load("res://data/elements/fire.tres")),
			"res://data/shots/aoe/diamond_r2_fire.tres")
	_save(_elemental_diamond(load("res://data/elements/electric.tres")),
			"res://data/shots/aoe/diamond_r2_electric.tres")

	# ── M4 patterns ───────────────────────────────────────────────────────────
	# R=3 cluster pellet (one of five); R=4 bypass unit-hit blast (heavy, 10→2 per ring).
	var fire_el : ElementDef = load("res://data/elements/fire.tres")
	var elec_el : ElementDef = load("res://data/elements/electric.tres")
	for variant in [["", null], ["_fire", fire_el], ["_electric", elec_el]]:
		_save(_diamond_pattern(3, 3, 1.0, variant[1]),
				"res://data/shots/aoe/diamond_r3%s.tres" % variant[0])
		_save(_diamond_pattern(4, 10, 2.0, variant[1]),
				"res://data/shots/aoe/diamond_r4%s.tres" % variant[0])

	# ── Phase F: shots ────────────────────────────────────────────────────────
	var basic := ShotDefinition.new()
	basic.id = "basic_shell"; basic.display_name = "Basic"
	basic.base_speed = 600.0; basic.gravity_scale = 1.0; basic.action_cost = 0
	basic.aoe_pattern = load("res://data/shots/aoe/diamond_r2.tres")
	basic.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(basic, "res://data/shots/basic_shell.tres")

	var fire_shell := ShotDefinition.new()
	fire_shell.id = "fire_shell"; fire_shell.display_name = "Fire"
	fire_shell.base_speed = 580.0; fire_shell.gravity_scale = 1.0; fire_shell.action_cost = 1
	fire_shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2_fire.tres")
	fire_shell.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(fire_shell, "res://data/shots/fire_shell.tres")

	var electric_shell := ShotDefinition.new()
	electric_shell.id = "electric_shell"; electric_shell.display_name = "Electric"
	electric_shell.base_speed = 650.0; electric_shell.gravity_scale = 0.85
	electric_shell.action_cost = 1
	electric_shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2_electric.tres")
	electric_shell.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(electric_shell, "res://data/shots/electric_shell.tres")

	var basic_ref : ShotDefinition = load("res://data/shots/basic_shell.tres")
	var fire_ref : ShotDefinition = load("res://data/shots/fire_shell.tres")
	var elec_ref : ShotDefinition = load("res://data/shots/electric_shell.tres")
	var loadout : Array[ShotDefinition] = [basic_ref, fire_ref, elec_ref]

	# ── M4: four shot-type families. Each unit fires one family; within it the player can
	#    pick physical (0 AP), fire (+2 AP) or electric (+3 AP) — same behaviour, different
	#    element + cost. _make_family writes the trio and returns it as a loadout. ──────────
	var cluster_loadout := _make_family("cluster", "Cluster", 3)
	var bypass_loadout  := _make_family("bypass",  "Drill",   4)
	var pull_loadout    := _make_family("pull",    "Pull",    2)
	var spiral_loadout  := _make_family("spiral",  "Spiral",  2)

	# ── Phase G: units ────────────────────────────────────────────────────────
	var heavy := UnitDefinition.new()
	heavy.id = "player_heavy"; heavy.display_name = "Unit1"
	heavy.width_voxels = 2; heavy.height_voxels = 3; heavy.max_hp = 9
	heavy.move_range = 99; heavy.climb_max = 1
	heavy.default_shot = basic_ref; heavy.available_shots = loadout
	heavy.tags = []; heavy.element_affinities = {}
	heavy.color = Color(0.25, 0.45, 0.9)
	_save(heavy, "res://data/units/player_heavy.tres")

	var light := UnitDefinition.new()
	light.id = "player_light"; light.display_name = "Unit2"
	light.width_voxels = 1; light.height_voxels = 3; light.max_hp = 4
	light.move_range = 99; light.climb_max = 1
	light.default_shot = basic_ref; light.available_shots = loadout
	light.tags = []; light.element_affinities = {}
	light.color = Color(0.35, 0.75, 0.95)
	_save(light, "res://data/units/player_light.tres")

	var organic := UnitDefinition.new()
	organic.id = "enemy_organic"; organic.display_name = "Brute"
	organic.width_voxels = 2; organic.height_voxels = 3; organic.max_hp = 8
	organic.move_range = 0; organic.climb_max = 1
	organic.default_shot = basic_ref
	organic.tags = ["ORGANIC"]
	organic.element_affinities = { "fire": 1.5, "electric": 0.75 }
	organic.color = Color(0.55, 0.75, 0.3)
	_save(organic, "res://data/units/enemy_organic.tres")

	var mechanical := UnitDefinition.new()
	mechanical.id = "enemy_mechanical"; mechanical.display_name = "Drone"
	mechanical.width_voxels = 2; mechanical.height_voxels = 3; mechanical.max_hp = 6
	mechanical.move_range = 0; mechanical.climb_max = 1
	mechanical.default_shot = basic_ref
	mechanical.tags = ["MECHANICAL"]
	mechanical.element_affinities = { "fire": 0.75, "electric": 1.5 }
	mechanical.color = Color(0.7, 0.55, 0.85)
	_save(mechanical, "res://data/units/enemy_mechanical.tres")

	# ── M4 player squad: one unit per shot family ─────────────────────────────
	_save_player_unit("player_cluster", "Cluster", cluster_loadout,
			Color(0.85, 0.7, 0.2))      # goldenrod
	_save_player_unit("player_bypass", "Drill", bypass_loadout,
			Color(0.2, 0.7, 0.65))      # teal
	_save_player_unit("player_pull", "Magnet", pull_loadout,
			Color(0.9, 0.45, 0.4))      # coral
	_save_player_unit("player_spiral", "Spiral", spiral_loadout,
			Color(0.6, 0.4, 0.85))      # purple

	# ── M5: cards ─────────────────────────────────────────────────────────────
	var shield_card := CardDefinition.new()
	shield_card.id = "shield_buff"; shield_card.display_name = "Shield Up"
	shield_card.target_type = CardDefinition.TargetType.ALLY
	shield_card.effect_type = CardDefinition.EffectType.SHIELD_BUFF
	shield_card.magnitude = 4; shield_card.action_cost = 2
	shield_card.color = Color(0.35, 0.65, 0.95)
	_save(shield_card, "res://data/cards/shield_buff.tres")

	var strike_card := CardDefinition.new()
	strike_card.id = "direct_strike"; strike_card.display_name = "Direct Strike"
	strike_card.target_type = CardDefinition.TargetType.ENEMY
	strike_card.effect_type = CardDefinition.EffectType.DIRECT_DAMAGE
	strike_card.magnitude = 3; strike_card.action_cost = 3
	strike_card.color = Color(0.9, 0.3, 0.25)
	_save(strike_card, "res://data/cards/direct_strike.tres")

	print("[bake] all M5 resources written")
	quit()

# Build a diamond R=2 pattern with every group carrying `element`.
func _elemental_diamond(element: ElementDef) -> AoEPattern:
	return _diamond_pattern(2, 3, 1.0, element)

# Diamond pattern with an optional element on every ring (null = physical).
func _diamond_pattern(radius: int, base: int, falloff: float, element: ElementDef) -> AoEPattern:
	var p := AoEPattern.make_diamond(radius, base, falloff)
	if element != null:
		for g in p.groups:
			g.element = element
	return p

# Write a shot-type family (physical / fire / electric) and return it as a typed loadout.
# `type_id` selects both the M4 behaviour payload and which AoE pattern radius is used.
func _make_family(type_id: String, label: String, base_cost_unused: int) -> Array[ShotDefinition]:
	var trio : Array[ShotDefinition] = []
	for variant in [["", "", 0], ["fire", "_fire", 2], ["electric", "_electric", 3]]:
		var s := ShotDefinition.new()
		s.id = type_id + ("_" + variant[0] if variant[0] != "" else "_basic")
		s.display_name = label if variant[0] == "" else "%s %s" % [label, str(variant[0]).capitalize()]
		s.base_speed = 600.0
		s.gravity_scale = 1.0
		s.action_cost = variant[2]
		s.aoe_pattern = load("res://data/shots/aoe/%s%s.tres" %
				[_family_pattern(type_id), variant[1]])
		_apply_family_payload(s, type_id)
		var path := "res://data/shots/%s.tres" % s.id
		_save(s, path)
		trio.append(load(path))
	return trio

# Which AoE pattern base each family detonates with.
func _family_pattern(type_id: String) -> String:
	match type_id:
		"cluster": return "diamond_r3"   # each of 5 pellets
		"bypass":  return "diamond_r4"   # heavy unit-hit blast
		_:         return "diamond_r2"   # pull / spiral per-projectile

# Stamp the M4 behaviour fields onto a shot for its family.
func _apply_family_payload(s: ShotDefinition, type_id: String) -> void:
	match type_id:
		"cluster":
			s.projectile_count = 5
			s.spread_deg = 1.0
		"bypass":
			s.bypass_terrain = true
		"pull":
			s.pull_near_radius = 4
			s.pull_far_radius = 8
			s.pull_near_voxels = 2
			s.pull_far_voxels = 1
		"spiral":
			s.spiral_arms = 2
			s.spiral_amplitude = 24.0
			s.spiral_frequency = 2.0

func _save_player_unit(id: String, dname: String,
		loadout: Array[ShotDefinition], color: Color) -> void:
	var u := UnitDefinition.new()
	u.id = id
	u.display_name = dname
	u.width_voxels = 2
	u.height_voxels = 3
	u.max_hp = 6
	u.move_range = 99
	u.climb_max = 1
	u.default_shot = loadout[0]
	u.available_shots = loadout
	u.tags = []
	u.element_affinities = {}
	u.color = color
	_save(u, "res://data/units/%s.tres" % id)

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[bake] FAILED to save %s (err %d)" % [path, err])
	else:
		print("[bake] saved ", path)
