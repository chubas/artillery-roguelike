class_name ArtifactDef
extends Resource

@export var artifact_name : String = ""
@export var description   : String = ""

## Faction tag (M18): neutral artifacts are cross-faction; tagged ones bias reward pools later.
@export var faction : String = Faction.NEUTRAL

func on_combat_start(ctx: ArtifactContext) -> void: pass
func on_round_start(ctx: ArtifactContext) -> void: pass
func on_player_turn_end(ctx: ArtifactContext) -> void: pass
func on_unit_died(ctx: ArtifactContext, victim: Unit) -> void: pass
func on_unit_killed(ctx: ArtifactContext, victim: Unit, killer: Unit) -> void: pass

func modify_card_cost(ctx: ArtifactContext, card: CardDefinition, base_cost: int) -> int:
	return base_cost

func modify_projectile_strength(ctx: ArtifactContext, strength: int, flight_time: float) -> int:
	return strength

func bonus_actions_on_round_start(ctx: ArtifactContext) -> int:
	return 0

func reset_per_combat() -> void: pass
