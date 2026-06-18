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
			"res://data/shots/aoe", "res://data/units", "res://data/cards",
			"res://data/artifacts/resources", "res://data/stages"]:
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

	# M10: Boosted — a persistent buff whose stacks are spent by moving (not by time).
	var boosted := StatusEffectDef.new()
	boosted.id = "boosted"; boosted.display_name = "Boosted"
	boosted.max_stacks = 9; boosted.duration = -1; boosted.tick_damage = 0; boosted.ap_reduction = 0
	boosted.is_buff = true; boosted.decays_per_turn = false; boosted.consumed_by_move = true
	_save(boosted, "res://data/statuses/boosted.tres")

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

	# ── AoE patterns (M7: shape only — core/edge zones, magnitude comes from
	#    ShotDefinition.strength * Unit.power, set below) ─────────────────────
	_save(AoEPattern.make_diamond(1, 2), "res://data/shots/aoe/diamond_r2.tres")
	_save(_elemental_diamond(load("res://data/elements/fire.tres")),
			"res://data/shots/aoe/diamond_r2_fire.tres")
	_save(_elemental_diamond(load("res://data/elements/electric.tres")),
			"res://data/shots/aoe/diamond_r2_electric.tres")

	# ── M4 patterns ───────────────────────────────────────────────────────────
	# r3: cluster pellet (one of five); r4: bypass unit-hit blast (heavier strength below).
	var fire_el : ElementDef = load("res://data/elements/fire.tres")
	var elec_el : ElementDef = load("res://data/elements/electric.tres")
	for variant in [["", null], ["_fire", fire_el], ["_electric", elec_el]]:
		_save(_diamond_pattern(1, 3, variant[1]),
				"res://data/shots/aoe/diamond_r3%s.tres" % variant[0])
		_save(_diamond_pattern(2, 4, variant[1]),
				"res://data/shots/aoe/diamond_r4%s.tres" % variant[0])

	# ── Phase F: shots ────────────────────────────────────────────────────────
	var basic := ShotDefinition.new()
	basic.id = "basic_shell"; basic.display_name = "Basic"
	basic.description = "A plain explosive shell. Free to fire, no element."
	basic.base_speed = 600.0; basic.gravity_scale = 1.0; basic.action_cost = 0
	basic.aoe_pattern = load("res://data/shots/aoe/diamond_r2.tres")
	basic.trajectory = ShotDefinition.TrajectoryType.ARC
	basic.strength = 3
	_save(basic, "res://data/shots/basic_shell.tres")

	var fire_shell := ShotDefinition.new()
	fire_shell.id = "fire_shell"; fire_shell.display_name = "Fire"
	fire_shell.description = "Burns on impact; strong vs organic, ignites flammable terrain."
	fire_shell.base_speed = 580.0; fire_shell.gravity_scale = 1.0; fire_shell.action_cost = 1
	fire_shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2_fire.tres")
	fire_shell.trajectory = ShotDefinition.TrajectoryType.ARC
	fire_shell.strength = 3
	_save(fire_shell, "res://data/shots/fire_shell.tres")

	var electric_shell := ShotDefinition.new()
	electric_shell.id = "electric_shell"; electric_shell.display_name = "Electric"
	electric_shell.description = "Shocks on impact; strong vs mechanical, chains through conductive terrain."
	electric_shell.base_speed = 650.0; electric_shell.gravity_scale = 0.85
	electric_shell.action_cost = 1
	electric_shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2_electric.tres")
	electric_shell.trajectory = ShotDefinition.TrajectoryType.ARC
	electric_shell.strength = 3
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
	organic.attack = 3
	organic.move_range = 0; organic.climb_max = 1
	organic.default_shot = basic_ref
	organic.tags = ["ORGANIC"]
	organic.element_affinities = { "fire": 1.5, "electric": 0.75 }
	organic.color = Color(0.55, 0.75, 0.3)
	_save(organic, "res://data/units/enemy_organic.tres")

	var mechanical := UnitDefinition.new()
	mechanical.id = "enemy_mechanical"; mechanical.display_name = "Drone"
	mechanical.width_voxels = 2; mechanical.height_voxels = 3; mechanical.max_hp = 6
	mechanical.attack = 3
	mechanical.move_range = 0; mechanical.climb_max = 1
	mechanical.default_shot = basic_ref
	mechanical.tags = ["MECHANICAL"]
	mechanical.element_affinities = { "fire": 0.75, "electric": 1.5 }
	mechanical.color = Color(0.7, 0.55, 0.85)
	_save(mechanical, "res://data/units/enemy_mechanical.tres")

	# ── M4 player squad: one unit per shot family ─────────────────────────────
	# M10: attack value is the source of projectile strength (× shot.strength_mult × power).
	# Values mirror the old per-shot strengths so balance is unchanged: drill is the heavy hitter.
	_save_player_unit("player_cluster", "Cluster", cluster_loadout,
			Color(0.85, 0.7, 0.2), 3)       # goldenrod
	_save_player_unit("player_bypass", "Drill", bypass_loadout,
			Color(0.2, 0.7, 0.65), 10)      # teal — heavy unit-hit blast
	_save_player_unit("player_pull", "Magnet", pull_loadout,
			Color(0.9, 0.45, 0.4), 3)       # coral
	_save_player_unit("player_spiral", "Spiral", spiral_loadout,
			Color(0.6, 0.4, 0.85), 3)       # purple

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

	# ── M11: deck cards ───────────────────────────────────────────────────────
	var boosted_card := CardDefinition.new()
	boosted_card.id = "boosted_card"; boosted_card.display_name = "Overdrive"
	boosted_card.target_type = CardDefinition.TargetType.ALLY
	boosted_card.effect_type = CardDefinition.EffectType.ADD_BOOSTED
	boosted_card.magnitude = 2; boosted_card.action_cost = 2
	boosted_card.color = Color(0.3, 0.8, 0.4)
	_save(boosted_card, "res://data/cards/boosted_card.tres")

	var mine_card := CardDefinition.new()
	mine_card.id = "mine_card"; mine_card.display_name = "Drop Mine"
	mine_card.target_type = CardDefinition.TargetType.TILE
	mine_card.effect_type = CardDefinition.EffectType.DEPLOY_MINE
	mine_card.magnitude = 0; mine_card.action_cost = 2
	mine_card.color = Color(0.9, 0.55, 0.2)
	_save(mine_card, "res://data/cards/mine_card.tres")

	var wind_card := CardDefinition.new()
	wind_card.id = "halve_wind"; wind_card.display_name = "Calm Winds"
	wind_card.target_type = CardDefinition.TargetType.NONE
	wind_card.effect_type = CardDefinition.EffectType.HALVE_WIND
	wind_card.magnitude = 0; wind_card.action_cost = 1
	wind_card.color = Color(0.4, 0.8, 0.95)
	_save(wind_card, "res://data/cards/halve_wind.tres")

	# ── M6: deployables ────────────────────────────────────────────────────────
	_save(AoEPattern.make_diamond(1, 2), "res://data/shots/aoe/diamond_mine.tres")

	# ── M9: artifacts ────────────────────────────────────────────────────────────
	_bake_artifact(ArtifactSquadRegen.new(), "Squad Regen",
			"At the start of each round, all player units heal 1 HP.",
			"res://data/artifacts/resources/squad_regen.tres")
	_bake_artifact(ArtifactLifesteal.new(), "Lifesteal",
			"Units heal half of missing HP when killing an enemy.",
			"res://data/artifacts/resources/lifesteal.tres")
	_bake_artifact(ArtifactEnemyDebuff.new(), "Enemy Debuff",
			"At the end of the player turn, all enemies lose 3 attack (stacks).",
			"res://data/artifacts/resources/enemy_debuff.tres")
	_bake_artifact(ArtifactFreeFirstCard.new(), "Free First Card",
			"The first card played each combat costs 0 actions.",
			"res://data/artifacts/resources/free_first_card.tres")
	_bake_artifact(ArtifactIdleActions.new(), "Idle Actions",
			"At round start, gain +1 action for each ally that did not move last round.",
			"res://data/artifacts/resources/idle_actions.tres")
	_bake_artifact(ArtifactDeathExplosion.new(), "Death Explosion",
			"The first enemy to die each combat explodes in a diamond doing 5 damage.",
			"res://data/artifacts/resources/death_explosion.tres")
	_bake_artifact(ArtifactLongFlight.new(), "Long Flight",
			"Projectiles airborne for more than 10 seconds deal 20% more damage.",
			"res://data/artifacts/resources/long_flight.tres")

	# ── M10: artifacts ─────────────────────────────────────────────────────────
	_bake_artifact(ArtifactStartBoosted.new(), "Battle Drills",
			"At the start of the stage, give your units Boosted (3).",
			"res://data/artifacts/resources/start_boosted.tres")

	# ── M13: stage descriptors ─────────────────────────────────────────────────
	var W := Const.MAP_WIDTH
	# stage_01 reproduces the historical hardcoded stage exactly (defeat-all).
	var s1_obj := ObjectiveDescriptor.new()
	s1_obj.type = ObjectiveDescriptor.Type.DEFEAT_ALL
	var s1 := StageDescriptor.new()
	s1.id = "stage_01"
	s1.terrain_seed = Const.NOISE_SEED
	s1.initial_enemies = [
		{ "unit": "res://data/units/enemy_organic.tres",    "name": "EnemyA", "col": W - 20 },
		{ "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyB", "col": W - 14 },
	]
	s1.reinforcements = [
		{ "round": 2, "unit": "res://data/units/enemy_organic.tres",    "name": "EnemyC", "col": W - 26 },
		{ "round": 5, "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyD", "col": W - 6 },
	]
	s1.deployables = [
		{ "type": "mine", "col": 40 },
		{ "type": "mine", "col": 60 },
		{ "type": "shield_generator", "col": 95 },
	]
	s1.wind_enabled = true; s1.wind_start_round = 3; s1.wind_ramp_per_round = 0.05; s1.wind_max_strength = 1.0
	s1.objective = s1_obj
	s1.threat_tags = ["fire", "electric"]
	_save(s1, "res://data/stages/stage_01.tres")

	# stage_02: a survive-N stage on different terrain — exercises the new objective path.
	var s2_obj := ObjectiveDescriptor.new()
	s2_obj.type = ObjectiveDescriptor.Type.SURVIVE_N
	s2_obj.survive_rounds = 4
	var s2 := StageDescriptor.new()
	s2.id = "stage_02"
	s2.terrain_seed = 777
	s2.initial_enemies = [
		{ "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyA", "col": W - 18 },
	]
	s2.reinforcements = [
		{ "round": 2, "unit": "res://data/units/enemy_organic.tres",    "name": "EnemyB", "col": W - 30 },
		{ "round": 3, "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyC", "col": W - 8 },
	]
	s2.deployables = [ { "type": "mine", "col": 50 } ]
	s2.wind_enabled = true; s2.wind_start_round = 2; s2.wind_ramp_per_round = 0.08; s2.wind_max_strength = 1.0
	s2.objective = s2_obj
	s2.threat_tags = ["electric", "survive"]
	_save(s2, "res://data/stages/stage_02.tres")

	print("[bake] all M13 resources written")
	quit()

# Build a core1/edge2 diamond pattern with every group carrying `element`.
func _elemental_diamond(element: ElementDef) -> AoEPattern:
	return _diamond_pattern(1, 2, element)

# Diamond pattern with an optional element on every ring (null = physical).
func _diamond_pattern(core_radius: int, edge_radius: int, element: ElementDef) -> AoEPattern:
	var p := AoEPattern.make_diamond(core_radius, edge_radius)
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
		s.description = _family_description(type_id, variant[0])
		s.base_speed = 600.0
		s.gravity_scale = 1.0
		s.action_cost = variant[2]
		s.aoe_pattern = load("res://data/shots/aoe/%s%s.tres" %
				[_family_pattern(type_id), variant[1]])
		s.strength = _family_strength(type_id)
		_apply_family_payload(s, type_id)
		var path := "res://data/shots/%s.tres" % s.id
		_save(s, path)
		trio.append(load(path))
	return trio

# Short flavor phrase per family + element variant, shown in the unit inspector (M5 polish).
func _family_description(type_id: String, element: String) -> String:
	var base := ""
	match type_id:
		"cluster": base = "Five shells fan out and detonate together."
		"bypass":  base = "Drills straight through terrain, exploding on the first enemy hit."
		"pull":    base = "Explodes normally, then drags nearby units toward the impact."
		"spiral":  base = "Main shell plus two arms that weave around its flight path."
	match element:
		"fire": return base + " Burns on impact; strong vs organic."
		"electric": return base + " Shocks on impact; strong vs mechanical."
		_: return base

# Which AoE pattern base each family detonates with.
func _family_pattern(type_id: String) -> String:
	match type_id:
		"cluster": return "diamond_r3"   # each of 5 pellets
		"bypass":  return "diamond_r4"   # heavy unit-hit blast
		_:         return "diamond_r2"   # pull / spiral per-projectile

# Baseline strength (M7) per family — independent of pattern shape.
func _family_strength(type_id: String) -> int:
	match type_id:
		"bypass": return 10   # heavy unit-hit blast
		_:        return 3    # cluster / pull / spiral

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
		loadout: Array[ShotDefinition], color: Color, attack: int = 3) -> void:
	var u := UnitDefinition.new()
	u.id = id
	u.display_name = dname
	u.width_voxels = 2
	u.height_voxels = 3
	u.max_hp = 6
	u.attack = attack
	u.move_range = 99
	u.climb_max = 1
	u.default_shot = loadout[0]
	u.available_shots = loadout
	u.tags = []
	u.element_affinities = {}
	u.color = color
	_save(u, "res://data/units/%s.tres" % id)

func _bake_artifact(a: ArtifactDef, name: String, desc: String, path: String) -> void:
	a.artifact_name = name
	a.description = desc
	_save(a, path)

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[bake] FAILED to save %s (err %d)" % [path, err])
	else:
		print("[bake] saved ", path)
