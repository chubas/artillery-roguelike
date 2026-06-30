class_name ArtifactDef
extends Resource

@export var artifact_name        : String = ""
@export var description_template : String = ""

## Keyword ids this artifact references / grants (M41). e.g. Battle Drills lists ["boosted"], so its
## hover tooltip explains Boosted. Surfaced via KeywordRegistry.
@export var keywords : Array[String] = []

func resolve_description() -> String:
	return description_template

## Faction tag (M18): neutral artifacts are cross-faction; tagged ones bias reward pools later.
@export var faction : String = Faction.NEUTRAL
@export var rarity  : String = Rarity.COMMON

func on_combat_start(ctx: ArtifactContext) -> void: pass
func on_round_start(ctx: ArtifactContext) -> void: pass
func on_player_turn_end(ctx: ArtifactContext) -> void: pass
func on_unit_died(ctx: ArtifactContext, victim: Unit) -> void: pass
func on_unit_killed(ctx: ArtifactContext, victim: Unit, killer: Unit) -> void: pass

func modify_card_cost(ctx: ArtifactContext, card: CardDefinition, base_cost: int) -> int:
	return base_cost

func modify_projectile_strength(ctx: ArtifactContext, strength: float, flight_time: float) -> float:
	return strength

func bonus_actions_on_round_start(ctx: ArtifactContext) -> int:
	return 0

func reset_per_combat() -> void: pass
