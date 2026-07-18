# Win condition for a stage (run-state spec §9). Data evaluated each turn by ObjectiveEvaluator,
# rather than a hardcoded defeat-all check. Types are added incrementally — M13 ships DEFEAT_ALL
# (the existing behavior) and SURVIVE_N (the cheapest second type); REACH_ZONE / HOLD_ZONE later.
class_name ObjectiveDescriptor
extends Resource

enum Type { DEFEAT_ALL, SURVIVE_N, DEFEAT_BOSS }

@export var type : Type = Type.DEFEAT_ALL
@export var survive_rounds : int = 0   # SURVIVE_N: win once round_index reaches this
# DEFEAT_BOSS (M47): win once no living enemy carries the "BOSS" tag — unlike DEFEAT_ALL this
# ignores minions/waves, so killing the boss clears the stage even with adds still alive.
