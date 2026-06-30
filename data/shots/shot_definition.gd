# Data definition of a shot type (M2 spec §2.3). All tunables live in .tres files.
class_name ShotDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Shell"
## Flavor/mechanic phrase shown in the unit inspector. Use {damage}, {dig}, {count}, {cost},
## {uses} tokens; AoE shape is not tokened — use [[shape]] as a visual placeholder.
@export var description_template : String = ""

## Keyword ids this shot carries (M41). Surfaced in tooltips via KeywordRegistry.
@export var keywords : Array[String] = []

## Physics
@export var base_speed : float = 600.0     # px/s at full charge
@export var gravity_scale : float = 1.0    # multiplier on global GRAVITY

## Payload
@export var aoe_pattern : AoEPattern = null
## Per-shot relative multiplier on the firing unit's dig (M16). Final dig strength =
## unit.dig * dig_mult + dig_modifier (clamped ≥ 0). Ignored when bypass_terrain.
@export var dig_mult : float = 1.0
## Terrain-only blast footprint. null → every offset in aoe_pattern (flat dig strength).
## Ignored when bypass_terrain (drill uses centre-voxel trail, not dig AoE).
@export var dig_pattern : AoEPattern = null
## Per-shot conditional flat damage bonuses (M39). Key = condition id (String),
## value = flat damage added when the condition is met (evaluated against ShotContext).
## Example: { "angle_above_70": 2 }. Empty = no conditions (all current shots).
@export var conditional_bonus : Dictionary = {}

## Action economy
@export var action_cost : int = 0          # 0 = free basic shot
@export var uses_per_stage : int = -1      # -1 = unlimited

## Trajectory type — governs physics behaviour (post-M2 variants)
enum TrajectoryType { ARC, FLAT, MORTAR, BYPASS, BOUNCING, BURROWING }
@export var trajectory : TrajectoryType = TrajectoryType.ARC

## Primary behaviour hook — ProjectileManager branches on this for spawn/resolve.
enum ShotBehavior { STANDARD, SPLIT, WALKER, BARRIER, TELEPORT, BIG_BALL }
@export var behavior : ShotBehavior = ShotBehavior.STANDARD

# ── M5 shot behaviours ────────────────────────────────────────────────────────
## Split: after `split_delay_sec`, fan `split_count` pellets ±`split_spread_deg`.
@export var split_delay_sec : float = 0.0
@export var split_count : int = 5
@export var split_spread_deg : float = 10.0   # half-angle of the fan cone

## Walker: on terrain impact, crawl along the surface up to `walker_max_steps` voxels.
@export var walker_max_steps : int = 10
## Continuous crawl speed in px/s between voxel waypoints. 0 = default (~one voxel / 0.12s).
@export var walker_crawl_speed : float = 0.0

## Barrier: after `barrier_delay_sec`, leave `barrier_tile_hp` tiles in void voxels passed.
@export var barrier_delay_sec : float = 0.0
@export var barrier_tile_hp : int = 1

## Big ball: visual-only scale multiplier on the projectile body (default 4 px radius).
@export var projectile_draw_radius : float = 4.0

# ── M4 shot-variety payloads ──────────────────────────────────────────────────
# A single ShotDefinition can describe a multi-projectile salvo, a terrain-bypassing
# drill, a gravity-pull blast, or a spiral. ProjectileManager.fire() reads these to
# decide what to spawn; AoEResolver / GravityPullResolver read them at impact.

## Cluster: spawn N projectiles fanned out by `spread_deg` between adjacent shots.
## 1 = a normal single projectile (default).
@export var projectile_count : int = 1
@export var spread_deg : float = 0.0       # degrees between adjacent sub-projectiles

## Bypass / drill: ignore terrain collision; the centre-voxel trail takes 1 dmg per
## unique tile passed. On overlapping an opposing unit it stops and applies `aoe_pattern`.
@export var bypass_terrain : bool = false

## Gravity pull: after the AoE resolves, drag nearby units toward the impact voxel.
## near (≤ near_radius) → near_voxels steps; far (≤ far_radius) → far_voxels steps.
## All 0 = no pull (default). near_radius < far_radius.
@export var pull_near_radius : int = 0
@export var pull_far_radius  : int = 0
@export var pull_near_voxels : int = 0
@export var pull_far_voxels  : int = 0

## Spiral: spawn `spiral_arms` satellite projectiles that oscillate perpendicular to
## the main trajectory (sinusoid of `spiral_amplitude` px at `spiral_frequency` Hz).
## 0 = no arms (default). The main projectile is always present alongside the arms.
@export var spiral_arms      : int   = 0
@export var spiral_amplitude : float = 0.0   # perpendicular offset amplitude (world px)
@export var spiral_frequency : float = 1.0   # oscillations per second

# Element lives per-group on the AoEPattern (M3 §3.2), not here — a shot can mix
# elements across rings. POST-M3: flags (PIERCING, SEEKING, etc.)

## True when this shot launches more than one projectile body (cluster, spiral, or split).
func is_salvo() -> bool:
	return projectile_count > 1 or spiral_arms > 0 or behavior == ShotBehavior.SPLIT

## Returns the substitution dict for description_template given a live unit (may be null).
## Uses the same formula as DamageResolver so tooltip and gameplay always agree.
func resolve_params(unit: Unit = null) -> Dictionary:
	var dmg   := PowerCalculator.effective_attack(unit) if unit != null else 3
	var dg    := unit.dig if unit != null else 1
	return {
		"damage": maxi(0, dmg),
		"dig":    maxi(0, roundi(dg * dig_mult)),
		"count":  projectile_count,
		"cost":   action_cost,
		"uses":   (str(uses_per_stage) if uses_per_stage >= 0 else "∞"),
	}

func resolve_description(unit: Unit = null) -> String:
	if description_template.is_empty(): return ""
	return description_template.format(resolve_params(unit))
