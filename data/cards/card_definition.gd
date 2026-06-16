# Data definition of a card (M5). Mirrors ShotDefinition's shape: tunables live in
# .tres files, behaviour is read by CombatManager at play time.
class_name CardDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Card"

enum TargetType { ALLY, ENEMY }
enum EffectType { SHIELD_BUFF, DIRECT_DAMAGE }

@export var target_type : TargetType = TargetType.ALLY
@export var effect_type : EffectType = EffectType.SHIELD_BUFF
@export var magnitude : int = 0           # shield points granted, or damage dealt
@export var action_cost : int = 1

@export var color : Color = Color(0.6, 0.6, 0.9)   # HUD chip tint

# POST-M5: an ARMOR_BUFF EffectType slots in here once Armor exists.
