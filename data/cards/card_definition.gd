# Data definition of a card (M5). Mirrors ShotDefinition's shape: tunables live in
# .tres files, behaviour is read by CombatManager at play time.
class_name CardDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Card"

## Faction tag (M18): neutral cards appear in any run; faction-tagged cards filter by run faction later.
@export var faction : String = Faction.NEUTRAL

# TILE = pick a ground space (mine); NONE = instant, no target (applied on select). (M11)
enum TargetType { ALLY, ENEMY, TILE, NONE }
enum EffectType { SHIELD_BUFF, ARMOR_BUFF, DIRECT_DAMAGE, ADD_BOOSTED, DEPLOY_MINE, HALVE_WIND,
                  PRIME_FIRE, PRIME_ELECTRIC }   # M30: elemental prime cards

@export var target_type : TargetType = TargetType.ALLY
@export var effect_type : EffectType = EffectType.SHIELD_BUFF
@export var description_template : String = ""
@export var magnitude       : int = 0   # shield/armor points, damage dealt, or Boosted stacks
@export var magnitude_per_level : int = 0   # seam for card-shop upgrades; 0 = no scaling yet
@export var action_cost : int = 1

@export var color : Color = Color(0.6, 0.6, 0.9)   # HUD chip tint

## Effective magnitude given the card's upgrade tier from Run.active.card_upgrades.
func effective_magnitude(level: int = 0) -> int:
	return magnitude + magnitude_per_level * level

func resolve_params(level: int = 0) -> Dictionary:
	return {"magnitude": effective_magnitude(level), "cost": action_cost}

func resolve_description(level: int = 0) -> String:
	if description_template.is_empty(): return ""
	return description_template.format(resolve_params(level))

