# Mine (M6): 1 HP — any hit is instant death. Detonates either by being hit by a
# projectile's AoE (take_damage drains its 1 HP) or by a player unit stepping within
# trigger_radius (CombatManager._check_mine_triggers calls take_damage(hp) directly).
# Both paths funnel through the same _die() override, which only signals the
# detonation — CombatManager (not Mine) actually runs the explosion via AoEResolver,
# keeping cross-system effects routed through EventBus per the project's house rule.
class_name Mine
extends Deployable

@export var trigger_radius : int = 3
@export var explosion_pattern : AoEPattern
## Fixed blast magnitude (M7 zone model) — mines aren't fired by a unit, so they
## carry their own strength directly rather than going through Unit.power.
@export var strength : int = 4
## Terrain-only blast magnitude (M16) — separate from unit-damage strength.
@export var dig : int = 4
## null → use explosion_pattern footprint for dig offsets.
@export var dig_pattern : AoEPattern = null

func _init() -> void:
	max_hp = 1
	hp = 1
	color = Color(0.85, 0.2, 0.2)
	display_name = "Mine"

func _die() -> void:
	EventBus.mine_detonated.emit(self)
	EventBus.deployable_died.emit(self)
