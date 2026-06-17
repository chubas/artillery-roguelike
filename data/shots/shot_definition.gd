# Data definition of a shot type (M2 spec §2.3). All tunables live in .tres files.
class_name ShotDefinition
extends Resource

@export var id : String = ""
@export var display_name : String = "Shell"
## Short flavor/mechanic phrase shown in the unit inspector panel (M5 polish).
@export var description : String = ""

## Physics
@export var base_speed : float = 600.0     # px/s at full charge
@export var gravity_scale : float = 1.0    # multiplier on global GRAVITY

## Payload
@export var aoe_pattern : AoEPattern = null
## Baseline magnitude before zone multipliers (M7). DORMANT since M10 — the fire path now
## derives strength from the firing unit's attack value (see strength_mult below). Kept so
## existing .tres load cleanly and for any non-unit callers.
@export var strength : int = 3
## Per-shot relative multiplier on the firing unit's attack (M10). Final salvo strength =
## unit.attack * strength_mult * unit.power + attack_modifier (clamped ≥ 0). 1.0 = the shot
## deals the unit's flat attack; >1 = a heavier shell, <1 = a lighter one.
@export var strength_mult : float = 1.0

## Action economy
@export var action_cost : int = 0          # 0 = free basic shot
@export var uses_per_stage : int = -1      # -1 = unlimited

## Trajectory type — governs physics behaviour (post-M2 variants)
enum TrajectoryType { ARC, FLAT, MORTAR, BYPASS, BOUNCING, BURROWING }
@export var trajectory : TrajectoryType = TrajectoryType.ARC

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

## True when this shot launches more than one projectile body (cluster or spiral).
func is_salvo() -> bool:
	return projectile_count > 1 or spiral_arms > 0
