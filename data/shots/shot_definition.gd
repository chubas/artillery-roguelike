# Data definition of a shot type (M2 spec §2.3). All tunables live in .tres files.
class_name ShotDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Shell"

## Physics
@export var base_speed : float = 600.0     # px/s at full charge
@export var gravity_scale : float = 1.0    # multiplier on global GRAVITY

## Payload
@export var aoe_pattern : AoEPattern = null

## Action economy
@export var action_cost : int = 0          # 0 = free basic shot
@export var uses_per_stage : int = -1      # -1 = unlimited

## Trajectory type — governs physics behaviour (post-M2 variants)
enum TrajectoryType { ARC, FLAT, MORTAR, BYPASS, BOUNCING, BURROWING }
@export var trajectory : TrajectoryType = TrajectoryType.ARC

# Element lives per-group on the AoEPattern (M3 §3.2), not here — a shot can mix
# elements across rings. POST-M3: flags (PIERCING, SEEKING, etc.)
