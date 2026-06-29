# Context object built at fire time and passed through to DamageResolver (M39).
# Carries shot-specific state so conditional_bonus entries on ShotDefinition can
# be evaluated without threading extra parameters through the call chain.
class_name ShotContext
extends RefCounted

var launch_angle  : float = 0.0    # degrees at firing time (positive-up convention)
var flight_time   : float = 0.0    # seconds in flight (filled at impact)
var distance      : float = 0.0    # voxels from barrel to impact (filled at impact)
var launch_round  : int = 0        # which round the shot was fired
var firing_unit   : Unit = null
var target_pos    : Vector2i = Vector2i.ZERO
var is_first_shot : bool = false   # first shot this unit has fired this combat
