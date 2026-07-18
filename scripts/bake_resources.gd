# Authoring aid (M2 §2.2, extended M3): bakes every .tres data file from generators.
# Run:  godot --headless --import   (once, to register class_names)
# then: godot --headless --path . res://scripts/bake_runner.tscn
# Do NOT use `-s scripts/bake_resources.gd` — that entry skips autoload registration at
# parse time and fails to compile scripts that reference EventBus / Features / Run.
# The runtime always uses the baked .tres files, never this script.
#
# Reference graph is a clean DAG: fire → {burn, burning}; burning → burn; burn → ∅.
# (See TileStatusDef note: we store applied_status, not a back-reference to the element,
#  precisely to avoid a load-breaking fire ↔ burning cycle.) So a single pass suffices.
extends Node

func _ready() -> void:
	for d in ["res://data/elements", "res://data/statuses", "res://data/tile_statuses",
			"res://data/shots/aoe", "res://data/units", "res://data/cards", "res://data/keywords",
			"res://data/artifacts/resources", "res://data/stages",
			"res://data/essences/resources",
			"res://data/terrain/profiles", "res://data/terrain/features"]:
		DirAccess.make_dir_recursive_absolute(d)

	# ── Keywords (M41): named mechanics surfaced in hover tooltips ─────────────
	# `boosted` shares its id with the Boosted status so applying it surfaces the keyword.
	# `unit` / `shot` are throwaway test keywords proving unit/shot → tooltip mapping.
	_bake_keyword("boosted", "Boosted",
			"The unit's next moves spend a Boosted stack instead of an action point.",
			Color(0.3, 0.8, 0.4))
	_bake_keyword("unit", "Unit",
			"Test keyword attached to every unit (M41 mapping check).",
			Color(0.6, 0.9, 1.0))
	_bake_keyword("shot", "Shot",
			"Test keyword attached to every shot (M41 mapping check).",
			Color(0.95, 0.8, 0.4))

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
	fire.strong_vs_tag = "ORGANIC"
	fire.vs_shield_mult = 0.5
	fire.vs_hp_mult = 1.5
	_save(fire, "res://data/elements/fire.tres")

	var electric := ElementDef.new()
	electric.id = "electric"; electric.display_name = "Electric"
	electric.unit_status = load("res://data/statuses/shock.tres")
	electric.tile_status = load("res://data/tile_statuses/electrified.tres")
	electric.strong_vs_tag = "MECHANICAL"
	electric.vs_shielded_mult = 2.0
	electric.vs_armor_mult = 0.5
	electric.vs_shield_mult = 2.0
	electric.vs_hp_mult = 0.5
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

	# ── M5 AoE patterns (Strong/Weak/Terrain radii) ───────────────────────────
	_save(AoEPattern.make_diamond(2, 2), "res://data/shots/aoe/diamond_dig_r2.tres")
	_save(AoEPattern.make_diamond(2, 3), "res://data/shots/aoe/diamond_s2_w3.tres")
	_save(AoEPattern.make_diamond(1, 1), "res://data/shots/aoe/diamond_dig_r1.tres")

	# ── Phase F: shots ────────────────────────────────────────────────────────
	var basic := ShotDefinition.new()
	basic.id = "basic_shell"; basic.display_name = "Basic"
	basic.description_template = "Free to fire. Deals {damage} damage on impact."
	basic.base_speed = 600.0; basic.gravity_scale = 1.0; basic.action_cost = 0
	basic.aoe_pattern = load("res://data/shots/aoe/diamond_r2.tres")
	basic.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(basic, "res://data/shots/basic_shell.tres")

	var fire_shell := ShotDefinition.new()
	fire_shell.id = "fire_shell"; fire_shell.display_name = "Fire"
	fire_shell.description_template = "Burns on impact; strong vs organic, ignites flammable terrain."
	fire_shell.base_speed = 580.0; fire_shell.gravity_scale = 1.0; fire_shell.action_cost = 1
	fire_shell.aoe_pattern = load("res://data/shots/aoe/diamond_r2_fire.tres")
	fire_shell.trajectory = ShotDefinition.TrajectoryType.ARC
	_save(fire_shell, "res://data/shots/fire_shell.tres")

	var electric_shell := ShotDefinition.new()
	electric_shell.id = "electric_shell"; electric_shell.display_name = "Electric"
	electric_shell.description_template = "Shocks on impact; strong vs mechanical, chains through conductive terrain."
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
	heavy.move_range = 99; heavy.weight = 2  # candidate: weight=3 (heavy bruiser)
	heavy.base_power = 3.0
	heavy.default_shot = basic_ref; heavy.available_shots = [basic_ref]
	heavy.tags = []; heavy.element_affinities = {}
	heavy.faction = Faction.ARMY
	heavy.rarity = Rarity.COMMON
	heavy.color = Color(0.25, 0.45, 0.9)
	_save(heavy, "res://data/units/player_heavy.tres")

	var light := UnitDefinition.new()
	light.id = "player_light"; light.display_name = "Unit2"
	light.width_voxels = 1; light.height_voxels = 3; light.max_hp = 4
	light.move_range = 99; light.weight = 2  # candidate: weight=1 (light scout)
	light.base_power = 3.0
	light.default_shot = basic_ref; light.available_shots = [basic_ref]
	light.tags = []; light.element_affinities = {}
	light.faction = Faction.ARMY
	light.rarity = Rarity.COMMON
	light.color = Color(0.35, 0.75, 0.95)
	_save(light, "res://data/units/player_light.tres")

	var organic := UnitDefinition.new()
	organic.id = "enemy_organic"; organic.display_name = "Brute"
	organic.width_voxels = 2; organic.height_voxels = 3; organic.max_hp = 8
	organic.base_power = 3.0
	organic.dig = 1
	organic.move_range = 0; organic.weight = 2
	organic.default_shot = basic_ref
	organic.tags = ["ORGANIC"]
	organic.targeting_rule = UnitDefinition.TargetingRule.WEAKEST   # M45: finisher (tunable)
	organic.element_affinities = { "fire": 1.5, "electric": 0.75 }
	organic.faction = Faction.ARMY
	organic.rarity = Rarity.COMMON
	organic.color = Color(0.55, 0.75, 0.3)
	_save(organic, "res://data/units/enemy_organic.tres")

	var mechanical := UnitDefinition.new()
	mechanical.id = "enemy_mechanical"; mechanical.display_name = "Drone"
	mechanical.width_voxels = 2; mechanical.height_voxels = 3; mechanical.max_hp = 6
	mechanical.base_power = 3.0
	mechanical.dig = 1
	mechanical.move_range = 0; mechanical.weight = 2
	mechanical.default_shot = basic_ref
	mechanical.tags = ["MECHANICAL"]
	mechanical.targeting_rule = UnitDefinition.TargetingRule.STRONGEST   # M45: counters tanks (tunable)
	mechanical.element_affinities = { "fire": 0.75, "electric": 1.5 }
	mechanical.faction = Faction.ARMY
	mechanical.rarity = Rarity.COMMON
	mechanical.color = Color(0.7, 0.55, 0.85)
	_save(mechanical, "res://data/units/enemy_mechanical.tres")

	# ── M47: Act 1 boss (Boss1) ──────────────────────────────────────────────
	# 5×5 immobile fortress boss. No attack yet (attack_behavior = NONE = no-op turn); its special
	# rule is a future milestone. anchored = never falls when terrain beneath it is destroyed.
	# The "BOSS" tag is what the DEFEAT_BOSS objective watches. base_power is set > 0 only to pass
	# the bake guard (_validate_unit_definitions); it is never read because the boss never fires.
	var boss1 := UnitDefinition.new()
	boss1.id = "boss1"; boss1.display_name = "Boss"
	boss1.width_voxels = 5; boss1.height_voxels = 5; boss1.max_hp = 100
	boss1.base_power = 1.0            # unused — boss never fires (attack_behavior NONE)
	boss1.dig = 0
	boss1.move_range = 0; boss1.weight = 3
	boss1.anchored = true
	boss1.attack_behavior = UnitDefinition.AttackBehavior.NONE
	boss1.default_shot = null         # never fires
	boss1.tags = ["BOSS", "MECHANICAL"]
	boss1.faction = Faction.ARMY
	boss1.rarity = Rarity.BOSS
	boss1.color = Color(0.72, 0.22, 0.28)   # menacing crimson
	_save(boss1, "res://data/units/boss1.tres")

	# ── M4 player squad: one unit per shot family ─────────────────────────────
	# M10: attack value is the source of projectile strength (× shot.strength_mult × power).
	# Values mirror the old per-shot strengths so balance is unchanged: drill is the heavy hitter.
	# M38 weight: all at 2 (medium) — candidates noted per unit.
	_save_player_unit("player_cluster", "Cluster", cluster_loadout,
			Color(0.85, 0.7, 0.2), 1.0, 1, 4)  # multishot cluster — low per-hit power; armored; candidate weight=3
	_save_player_unit("player_bypass", "Drill", bypass_loadout,
			Color(0.2, 0.7, 0.65), 6.0)            # teal; heavy single-hit driller; candidate: weight=1 (light fast)
	_save_player_unit("player_pull", "Magnet", pull_loadout,
			Color(0.9, 0.45, 0.4), 3.0)            # coral
	_save_player_unit("player_spiral", "Spiral", spiral_loadout,
			Color(0.6, 0.4, 0.85), 3.0)            # purple

	# ── M5: five behaviour shots (basic only — no elemental loadout variants) ─
	var blast_242 : AoEPattern = load("res://data/shots/aoe/diamond_r4.tres")
	var dig_242 : AoEPattern = load("res://data/shots/aoe/diamond_dig_r2.tres")
	var blast_231 : AoEPattern = load("res://data/shots/aoe/diamond_s2_w3.tres")
	var dig_231 : AoEPattern = load("res://data/shots/aoe/diamond_dig_r1.tres")

	var split_shot := _make_behavior_shot("split_basic", "Split",
			"Splits after 2s into five shells (±10°). Each detonates [[shape]].",
			ShotDefinition.ShotBehavior.SPLIT, blast_242, dig_242)
	split_shot.split_delay_sec = 2.0
	split_shot.split_count = 5
	split_shot.split_spread_deg = 10.0
	_save(split_shot, "res://data/shots/split_basic.tres")

	var walker_shot := _make_behavior_shot("walker_basic", "Walker",
			"On landing, crawls along terrain away from you (up to 10 voxels), then explodes [[shape]].",
			ShotDefinition.ShotBehavior.WALKER, blast_242, dig_242)
	walker_shot.walker_max_steps = 10
	walker_shot.walker_crawl_speed = float(Const.VOXEL_SIZE) / 0.12
	_save(walker_shot, "res://data/shots/walker_basic.tres")

	var barrier_shot := _make_behavior_shot("barrier_basic", "Barrier",
			"After 2s, leaves 1-HP terrain in open air along its path. No blast on impact.",
			ShotDefinition.ShotBehavior.BARRIER, null, null)
	barrier_shot.barrier_delay_sec = 2.0
	barrier_shot.barrier_tile_hp = 1
	_save(barrier_shot, "res://data/shots/barrier_basic.tres")

	var teleport_shot := _make_behavior_shot("teleport_basic", "Teleporter",
			"On landing, moves you to the impact site if there is room. Otherwise nothing happens.",
			ShotDefinition.ShotBehavior.TELEPORT, null, null)
	_save(teleport_shot, "res://data/shots/teleport_basic.tres")

	var bigball_shot := _make_behavior_shot("bigball_basic", "Big Ball",
			"Oversized shell. Detonates [[shape]] on impact.",
			ShotDefinition.ShotBehavior.BIG_BALL, blast_231, dig_231)
	bigball_shot.projectile_draw_radius = 12.0
	_save(bigball_shot, "res://data/shots/bigball_basic.tres")

	var split_ref : ShotDefinition = load("res://data/shots/split_basic.tres")
	var walker_ref : ShotDefinition = load("res://data/shots/walker_basic.tres")
	var barrier_ref : ShotDefinition = load("res://data/shots/barrier_basic.tres")
	var teleport_ref : ShotDefinition = load("res://data/shots/teleport_basic.tres")
	var bigball_ref : ShotDefinition = load("res://data/shots/bigball_basic.tres")

	_save_player_unit("player_split", "Splitter", [split_ref],
			Color(0.95, 0.75, 0.25), 1.0)  # multishot — lower per-hit power; weight=1 (light aerial splitter)
	_save_player_unit("player_walker", "Crawler", [walker_ref],
			Color(0.55, 0.85, 0.35), 3.0)  # candidate: weight=3 (heavy ground crawler)
	_save_player_unit("player_barrier", "Builder", [barrier_ref],
			Color(0.45, 0.55, 0.95), 3.0)  # candidate: weight=3 (heavy defensive builder)
	_save_player_unit("player_teleport", "Blink", [teleport_ref],
			Color(0.85, 0.4, 0.95), 3.0)   # candidate: weight=0 (weightless teleporter)
	_save_player_unit("player_bigball", "Big Ball", [bigball_ref],
			Color(0.9, 0.55, 0.2), 3.0)

	# ── M5: cards ─────────────────────────────────────────────────────────────
	var shield_card := CardDefinition.new()
	shield_card.id = "shield_buff"; shield_card.display_name = "Shield Up"
	shield_card.target_type = CardDefinition.TargetType.ALLY
	shield_card.effect_type = CardDefinition.EffectType.SHIELD_BUFF
	shield_card.magnitude = 4; shield_card.action_cost = 1
	shield_card.faction = Faction.NEUTRAL; shield_card.rarity = Rarity.BASIC
	shield_card.color = Color(0.35, 0.65, 0.95)
	_save(shield_card, "res://data/cards/shield_buff.tres")

	var armor_card := CardDefinition.new()
	armor_card.id = "armor_buff"; armor_card.display_name = "Armor Up"
	armor_card.target_type = CardDefinition.TargetType.ALLY
	armor_card.effect_type = CardDefinition.EffectType.ARMOR_BUFF
	armor_card.magnitude = 5; armor_card.action_cost = 1
	armor_card.faction = Faction.NEUTRAL; armor_card.rarity = Rarity.COMMON
	armor_card.color = Color(0.95, 0.82, 0.25)
	_save(armor_card, "res://data/cards/armor_buff.tres")

	var strike_card := CardDefinition.new()
	strike_card.id = "direct_strike"; strike_card.display_name = "Direct Strike"
	strike_card.target_type = CardDefinition.TargetType.ENEMY
	strike_card.effect_type = CardDefinition.EffectType.DIRECT_DAMAGE
	strike_card.magnitude = 2; strike_card.action_cost = 1
	strike_card.faction = Faction.NEUTRAL; strike_card.rarity = Rarity.BASIC
	strike_card.color = Color(0.9, 0.3, 0.25)
	_save(strike_card, "res://data/cards/direct_strike.tres")

	# ── M11: deck cards ───────────────────────────────────────────────────────
	var boosted_card := CardDefinition.new()
	boosted_card.id = "boosted_card"; boosted_card.display_name = "Overdrive"
	boosted_card.target_type = CardDefinition.TargetType.ALLY
	boosted_card.effect_type = CardDefinition.EffectType.ADD_BOOSTED
	boosted_card.magnitude = 2; boosted_card.action_cost = 1
	boosted_card.faction = Faction.NEUTRAL; boosted_card.rarity = Rarity.COMMON
	boosted_card.color = Color(0.3, 0.8, 0.4)
	boosted_card.keywords = ["boosted"]   # M41: hover explains Boosted that this card grants
	_save(boosted_card, "res://data/cards/boosted_card.tres")

	var mine_card := CardDefinition.new()
	mine_card.id = "mine_card"; mine_card.display_name = "Drop Mine"
	mine_card.target_type = CardDefinition.TargetType.TILE
	mine_card.effect_type = CardDefinition.EffectType.DEPLOY_MINE
	mine_card.magnitude = 0; mine_card.action_cost = 1
	mine_card.faction = Faction.ARMY; mine_card.rarity = Rarity.COMMON
	mine_card.color = Color(0.9, 0.55, 0.2)
	_save(mine_card, "res://data/cards/mine_card.tres")

	var wind_card := CardDefinition.new()
	wind_card.id = "halve_wind"; wind_card.display_name = "Calm Winds"
	wind_card.target_type = CardDefinition.TargetType.NONE
	wind_card.effect_type = CardDefinition.EffectType.HALVE_WIND
	wind_card.magnitude = 0; wind_card.action_cost = 0
	wind_card.faction = Faction.ARMY; wind_card.rarity = Rarity.COMMON
	wind_card.color = Color(0.4, 0.8, 0.95)
	_save(wind_card, "res://data/cards/halve_wind.tres")

	# ── M30: elemental prime cards ────────────────────────────────────────────
	var fire_prime := CardDefinition.new()
	fire_prime.id = "fire_prime"; fire_prime.display_name = "Fire Prime"
	fire_prime.description_template = "Target ally's next shot burns on impact."
	fire_prime.target_type = CardDefinition.TargetType.ALLY
	fire_prime.effect_type = CardDefinition.EffectType.PRIME_FIRE
	fire_prime.action_cost = 1; fire_prime.faction = Faction.ARMY
	fire_prime.rarity = Rarity.COMMON
	fire_prime.color = Color(0.9, 0.35, 0.15)
	_save(fire_prime, "res://data/cards/fire_prime.tres")

	var elec_prime := CardDefinition.new()
	elec_prime.id = "electric_prime"; elec_prime.display_name = "Electric Prime"
	elec_prime.description_template = "Target ally's next shot shocks on impact."
	elec_prime.target_type = CardDefinition.TargetType.ALLY
	elec_prime.effect_type = CardDefinition.EffectType.PRIME_ELECTRIC
	elec_prime.action_cost = 1; elec_prime.faction = Faction.ARMY
	elec_prime.rarity = Rarity.COMMON
	elec_prime.color = Color(0.25, 0.65, 0.95)
	_save(elec_prime, "res://data/cards/electric_prime.tres")

	# ── M6: deployables ────────────────────────────────────────────────────────
	_save(AoEPattern.make_diamond(1, 2), "res://data/shots/aoe/diamond_mine.tres")

	# ── M9: artifacts ────────────────────────────────────────────────────────────
	_bake_artifact(ArtifactSquadRegen.new(), "Squad Regen",
			"At the start of each round, all player units heal 1 HP.",
			"res://data/artifacts/resources/squad_regen.tres", Faction.NEUTRAL)
	_bake_artifact(ArtifactLifesteal.new(), "Lifesteal",
			"Units heal half of missing HP when killing an enemy.",
			"res://data/artifacts/resources/lifesteal.tres", Faction.NEUTRAL)
	_bake_artifact(ArtifactEnemyDebuff.new(), "Enemy Debuff",
			"At the end of the player turn, all enemies lose 3 attack (stacks).",
			"res://data/artifacts/resources/enemy_debuff.tres", Faction.ARMY)
	_bake_artifact(ArtifactFreeFirstCard.new(), "Free First Card",
			"The first card played each combat costs 0 actions.",
			"res://data/artifacts/resources/free_first_card.tres", Faction.NEUTRAL)
	_bake_artifact(ArtifactIdleActions.new(), "Idle Actions",
			"At round start, gain +1 action for each ally that did not move last round.",
			"res://data/artifacts/resources/idle_actions.tres", Faction.ARMY)
	_bake_artifact(ArtifactDeathExplosion.new(), "Death Explosion",
			"The first enemy to die each combat explodes in a diamond doing 5 damage.",
			"res://data/artifacts/resources/death_explosion.tres", Faction.ARMY)
	_bake_artifact(ArtifactLongFlight.new(), "Long Flight",
			"Projectiles airborne for more than 10 seconds deal 20% more damage.",
			"res://data/artifacts/resources/long_flight.tres", Faction.ARMY)

	# ── M10: artifacts ─────────────────────────────────────────────────────────
	_bake_artifact(ArtifactStartBoosted.new(), "Battle Drills",
			"At the start of the stage, give your units Boosted (3).",
			"res://data/artifacts/resources/start_boosted.tres", Faction.ARMY,
			Rarity.COMMON, ["boosted"])

	# ── M40: artifacts ─────────────────────────────────────────────────────────
	_bake_artifact(ArtifactLastStand.new(), "Last Stand",
			"While a unit is your only survivor, its attack is multiplied by 1.5.",
			"res://data/artifacts/resources/last_stand.tres", Faction.NEUTRAL)

	# ── M22: essences ─────────────────────────────────────────────────────────
	var armor_primer := EssenceArmorPrimer.new()
	armor_primer.base_value = 10
	_bake_essence(armor_primer, "Armor Primer",
			"Enter each combat with {value} extra armor.",
			1, "res://data/essences/resources/armor_primer.tres")
	_bake_essence(EssenceDoubleShot.new(), "Double Shot",
			"After firing, automatically shoot again with the same angle and power after 2 seconds.",
			1, "res://data/essences/resources/double_shot.tres")

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
	s1.spawn_min_col = 0; s1.spawn_max_col = W / 2 - 1   # left half
	s1.objective = s1_obj
	s1.threat_tags = ["fire", "electric"]
	s1.act_tags = ["act_1"]
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
	s2.spawn_min_col = 0; s2.spawn_max_col = W / 2 - 1
	s2.objective = s2_obj
	s2.threat_tags = ["electric", "survive"]
	s2.act_tags = ["act_1"]
	_save(s2, "res://data/stages/stage_02.tres")

	# stage_03 (M14): the run's final node — a heavier defeat-all on its own terrain.
	var s3_obj := ObjectiveDescriptor.new()
	s3_obj.type = ObjectiveDescriptor.Type.DEFEAT_ALL
	var s3 := StageDescriptor.new()
	s3.id = "stage_03"
	s3.terrain_seed = 24680
	s3.initial_enemies = [
		{ "unit": "res://data/units/enemy_organic.tres",    "name": "EnemyA", "col": W - 22 },
		{ "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyB", "col": W - 16 },
		{ "unit": "res://data/units/enemy_organic.tres",    "name": "EnemyC", "col": W - 10 },
	]
	s3.reinforcements = [
		{ "round": 3, "unit": "res://data/units/enemy_mechanical.tres", "name": "EnemyD", "col": W - 28 },
	]
	s3.deployables = [ { "type": "mine", "col": 45 }, { "type": "shield_generator", "col": 70 } ]
	s3.wind_enabled = true; s3.wind_start_round = 2; s3.wind_ramp_per_round = 0.06; s3.wind_max_strength = 1.0
	s3.spawn_min_col = 0; s3.spawn_max_col = W / 2 - 1
	s3.objective = s3_obj
	s3.threat_tags = ["fire", "electric", "swarm"]
	s3.act_tags = ["act_1"]
	_save(s3, "res://data/stages/stage_03.tres")

	# ── M47: Act 1 boss stage ────────────────────────────────────────────────────
	# The boss itself is spawned from the map's Entity_Boss1 (data/maps/boss1.txt), not from
	# initial_enemies. Objective is DEFEAT_BOSS — clears the instant the boss dies. Wind off.
	var sb_obj := ObjectiveDescriptor.new()
	sb_obj.type = ObjectiveDescriptor.Type.DEFEAT_BOSS
	var sb := StageDescriptor.new()
	sb.id = "stage_boss1"
	sb.terrain_seed = 4771
	sb.initial_enemies = []           # boss comes from the map entity; waves/minions added later
	sb.reinforcements = []
	sb.deployables = []
	sb.wind_enabled = false
	sb.spawn_min_col = 0; sb.spawn_max_col = W / 2 - 1   # overridden by the custom map's zones
	sb.objective = sb_obj
	sb.threat_tags = ["boss"]
	sb.act_tags = ["act_1"]
	_save(sb, "res://data/stages/stage_boss1.tres")

	# ── M35: event resources ─────────────────────────────────────────────────────
	var ev_triage := EventTriage.new()
	ev_triage.event_id    = "field_triage"
	ev_triage.title       = "Field Triage"
	ev_triage.description = "Your medic scavenges supplies. Choose how to use them."
	ev_triage.act_tags    = ["act_1"]
	_save(ev_triage, "res://data/events/resources/event_triage.tres")

	var ev_blood := EventBloodPrice.new()
	ev_blood.event_id    = "blood_price"
	ev_blood.title       = "Blood Price"
	ev_blood.description = "A black market contact offers a deal. The price is steep."
	ev_blood.act_tags    = ["act_1"]
	_save(ev_blood, "res://data/events/resources/event_blood_price.tres")

	# ── M36: consumable card ──────────────────────────────────────────────────────
	var heal_vial := CardDefinition.new()
	heal_vial.id           = "heal_vial"
	heal_vial.display_name = "Heal Vial"
	heal_vial.faction      = Faction.NEUTRAL
	heal_vial.target_type  = CardDefinition.TargetType.ALLY
	heal_vial.effect_type  = CardDefinition.EffectType.HEAL
	heal_vial.magnitude    = 10
	heal_vial.is_consumable = true
	heal_vial.action_cost  = 1
	heal_vial.rarity       = Rarity.COMMON
	heal_vial.color        = Color(0.2, 0.8, 0.4, 1.0)
	_save(heal_vial, "res://data/cards/heal_vial.tres")

	# M45: Taunt — all enemies target the chosen ally this round.
	var taunt := CardDefinition.new()
	taunt.id           = "taunt"
	taunt.display_name = "Taunt"
	taunt.faction      = Faction.NEUTRAL
	taunt.target_type  = CardDefinition.TargetType.ALLY
	taunt.effect_type  = CardDefinition.EffectType.TAUNT
	taunt.description_template = "All enemies target this ally this round."
	taunt.action_cost  = 1
	taunt.rarity       = Rarity.COMMON
	taunt.color        = Color(0.9, 0.55, 0.15, 1.0)
	_save(taunt, "res://data/cards/taunt.tres")

	# ── M32: Terrain feature definitions ────────────────────────────────────────
	var fd_ridge := FeatureDefinition.new()
	fd_ridge.type = FeatureDefinition.FeatureType.RIDGE
	fd_ridge.width_min = 20; fd_ridge.width_max = 40
	fd_ridge.height_min = 8; fd_ridge.height_max = 18
	fd_ridge.special_params = {"slope_edges": true}
	_save(fd_ridge, "res://data/terrain/features/ridge_standard.tres")

	var fd_bunker := FeatureDefinition.new()
	fd_bunker.type = FeatureDefinition.FeatureType.BUNKER
	fd_bunker.width_min = 14; fd_bunker.width_max = 22
	fd_bunker.height_min = 8; fd_bunker.height_max = 12
	fd_bunker.special_params = {"aperture_count": 1}
	_save(fd_bunker, "res://data/terrain/features/bunker_standard.tres")

	var fd_pit := FeatureDefinition.new()
	fd_pit.type = FeatureDefinition.FeatureType.PIT
	fd_pit.width_min = 16; fd_pit.width_max = 28
	fd_pit.height_min = 30; fd_pit.height_max = 60
	_save(fd_pit, "res://data/terrain/features/pit_standard.tres")

	var fd_crystal := FeatureDefinition.new()
	fd_crystal.type = FeatureDefinition.FeatureType.CRYSTAL_DEPOSIT
	fd_crystal.width_min = 0; fd_crystal.width_max = 0   # unused for crystal
	fd_crystal.height_min = 30; fd_crystal.height_max = 65
	_save(fd_crystal, "res://data/terrain/features/crystal_vein.tres")

	# ── M32: Terrain profiles ────────────────────────────────────────────────
	var tp_open := TerrainProfile.new()
	tp_open.story = "No terrain problem — open field"
	tp_open.noise_max_amplitude = 8
	tp_open.background = [fd_crystal]
	_save(tp_open, "res://data/terrain/profiles/open_field.tres")

	var tp_ridge := TerrainProfile.new()
	tp_ridge.story = "Enemy holds the high ground"
	tp_ridge.center_slot = fd_ridge
	tp_ridge.noise_max_amplitude = 5
	_save(tp_ridge, "res://data/terrain/profiles/ridge_assault.tres")

	var tp_fortress := TerrainProfile.new()
	tp_fortress.story = "Enemy inside a protected structure"
	tp_fortress.right_slot = fd_bunker
	tp_fortress.noise_max_amplitude = 5
	tp_fortress.map_width_min = 110; tp_fortress.map_width_max = 140
	_save(tp_fortress, "res://data/terrain/profiles/fortress_siege.tres")

	var tp_pit := TerrainProfile.new()
	tp_pit.story = "A gap punishes ground movement"
	tp_pit.center_slot = fd_pit
	tp_pit.noise_max_amplitude = 4
	tp_pit.map_width_min = 120; tp_pit.map_width_max = 150
	_save(tp_pit, "res://data/terrain/profiles/pit_crossing.tres")

	print("[bake] all M14 resources written")
	_tag_test_keywords()
	_validate_unit_definitions()
	get_tree().quit()

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
		s.description_template = _family_description(type_id, variant[0])
		s.base_speed = 600.0
		s.gravity_scale = 1.0
		s.action_cost = variant[2]
		s.aoe_pattern = load("res://data/shots/aoe/%s%s.tres" %
				[_family_pattern(type_id), variant[1]])
		s.dig_mult = 1.0
		if type_id != "bypass":
			s.dig_pattern = s.aoe_pattern
		_apply_family_payload(s, type_id)
		var path := "res://data/shots/%s.tres" % s.id
		_save(s, path)
		trio.append(load(path))
	var basic_only : Array[ShotDefinition] = [trio[0]]
	return basic_only

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

func _make_behavior_shot(id: String, label: String, desc: String,
		behavior: ShotDefinition.ShotBehavior,
		aoe: AoEPattern, dig: AoEPattern) -> ShotDefinition:
	var s := ShotDefinition.new()
	s.id = id
	s.display_name = label
	s.description_template = desc
	s.behavior = behavior
	s.base_speed = 600.0
	s.gravity_scale = 1.0
	s.action_cost = 0
	s.dig_mult = 1.0
	s.aoe_pattern = aoe
	if dig != null:
		s.dig_pattern = dig
	elif aoe != null:
		s.dig_pattern = aoe
	return s

func _save_player_unit(id: String, dname: String,
		loadout: Array[ShotDefinition], color: Color, base_power: float = 3.0,
		dig: int = 1, base_armor: int = 0) -> void:
	var u := UnitDefinition.new()
	u.id = id
	u.display_name = dname
	u.width_voxels = 2
	u.height_voxels = 3
	u.max_hp = 6
	u.base_armor = base_armor
	u.base_power = base_power
	u.dig = dig
	u.move_range = 99
	u.weight = 2
	u.default_shot = loadout[0]
	u.available_shots = loadout
	u.tags = []
	u.element_affinities = {}
	u.faction = Faction.ARMY
	u.rarity = Rarity.COMMON
	u.color = color
	_save(u, "res://data/units/%s.tres" % id)

func _bake_artifact(a: ArtifactDef, name: String, desc: String, path: String,
		faction: String = Faction.NEUTRAL, rarity: String = Rarity.COMMON,
		keywords: Array = []) -> void:
	a.artifact_name = name
	a.description_template = desc
	a.faction = faction
	a.rarity = rarity
	a.keywords.assign(keywords)
	_save(a, path)

func _bake_essence(e: EssenceDef, name: String, desc: String, slot_cost: int,
		path: String, faction: String = Faction.NEUTRAL) -> void:
	e.essence_name = name
	e.description_template = desc
	e.slot_cost    = slot_cost
	e.faction      = faction
	_save(e, path)

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[bake] FAILED to save %s (err %d)" % [path, err])
	else:
		print("[bake] saved ", path)

func _bake_keyword(id: String, dname: String, desc: String, color: Color) -> void:
	var kw := KeywordDef.new()
	kw.id = id
	kw.display_name = dname
	kw.description_template = desc
	kw.color = color
	_save(kw, "res://data/keywords/%s.tres" % id)

# M41 TEST tagging: every unit gets the `unit` keyword and every shot gets the `shot` keyword, to
# verify keyword→tooltip mapping across all surfaces. Centralized post-pass so we don't touch every
# construction site; remove this when real keywords replace the test ones. Real keyword assignments
# (e.g. boosted_card → ["boosted"]) are set at their own construction sites and preserved here.
func _tag_test_keywords() -> void:
	for spec in [["res://data/units", "unit"], ["res://data/shots", "shot"]]:
		var dir_path : String = spec[0]
		var kw : String = spec[1]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var path := "%s/%s" % [dir_path, file]
			var res := load(path)
			if res == null or not (res is UnitDefinition or res is ShotDefinition):
				continue
			if not res.keywords.has(kw):
				var arr : Array[String] = []
				arr.assign(res.keywords)
				arr.append(kw)
				res.keywords = arr
				_save(res, path)

# Build-time guard: every UnitDefinition in res://data/units must carry a positive base_power.
# A unit left at the 0.0 sentinel (base_power never authored) fails the build loudly. This is the
# single enforcement point for "all units have a defined base power" — see UnitDefinition.base_power.
func _validate_unit_definitions() -> bool:
	var dir_path := "res://data/units"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[validate] cannot open %s" % dir_path)
		return false
	var failures : Array[String] = []
	var checked := 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var path := "%s/%s" % [dir_path, file]
		var def := load(path) as UnitDefinition
		if def == null:
			failures.append("%s: not a UnitDefinition" % file)
			continue
		checked += 1
		if def.base_power <= 0.0:
			failures.append("%s (id=%s): base_power=%.2f — must be > 0 (set it explicitly)"
					% [file, def.id, def.base_power])
	if failures.is_empty():
		print("[validate] OK — all %d unit definitions have base_power > 0" % checked)
		return true
	push_error("[validate] FAILED — %d/%d unit definitions missing a valid base_power:"
			% [failures.size(), checked])
	for f in failures:
		push_error("  - %s" % f)
		print("[validate]   ✗ %s" % f)
	return false
