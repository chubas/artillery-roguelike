# Data definition of a card (M5). Mirrors ShotDefinition's shape: tunables live in
# .tres files, behaviour is read by CombatManager at play time.
class_name CardDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Card"

# TILE = pick a ground space (mine); NONE = instant, no target (applied on select). (M11)
enum TargetType { ALLY, ENEMY, TILE, NONE }
enum EffectType { SHIELD_BUFF, DIRECT_DAMAGE, ADD_BOOSTED, DEPLOY_MINE, HALVE_WIND }

@export var target_type : TargetType = TargetType.ALLY
@export var effect_type : EffectType = EffectType.SHIELD_BUFF
@export var magnitude : int = 0           # shield points, damage dealt, or Boosted stacks granted
@export var action_cost : int = 1

@export var color : Color = Color(0.6, 0.6, 0.9)   # HUD chip tint

# POST-M5: an ARMOR_BUFF EffectType slots in here once Armor exists.
