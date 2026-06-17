# Artillery Space — global constants and coordinate helpers.
# Access as Const.VOXEL_SIZE, Const.world_to_voxel(...), etc. No autoload needed.
class_name Const

# --- Grid (terrain spec §3.1) -------------------------------------------------
const VOXEL_SIZE : int = 16     # px per voxel — single source of truth (DECIDED)
const MAP_WIDTH  : int = 120    # voxels
const MAP_HEIGHT : int = 100    # voxels
const CHUNK_SIZE : int = 16     # voxels per chunk side

static func chunks_wide() -> int:
	return int(ceil(float(MAP_WIDTH) / CHUNK_SIZE))

static func chunks_tall() -> int:
	return int(ceil(float(MAP_HEIGHT) / CHUNK_SIZE))

# --- Generation (terrain spec §6.2) ------------------------------------------
const BASE_FILL_ROWS        : int   = 60
const SURFACE_VARIATION     : int   = 8
const NOISE_SEED            : int   = 12345
const NOISE_FREQUENCY       : float = 0.03
const CAVE_COUNT            : int   = 3
const CAVE_WIDTH_MIN        : int   = 8
const CAVE_WIDTH_MAX        : int   = 16
const CAVE_HEIGHT_MIN       : int   = 5
const CAVE_HEIGHT_MAX       : int   = 10
const SPAWN_PLATFORM_COL    : int   = 10
const SPAWN_PLATFORM_WIDTH  : int   = 8
const REINFORCED_TILE_CHANCE: float = 0.10

# --- Destruction / AoE (terrain spec §8, reconciled in plan §1.1) ------------
const AOE_RADIUS  : int = 2
# 4 (not the spec's 3): with 75%/50% falloff this one-shots the dist-1 ring too,
# leaving a visible plus-shaped crater per blast; dist-2 cracks to 1 HP.
const BASE_DAMAGE : int = 4

# --- Projectile physics (terrain spec §9.6) ----------------------------------
const GRAVITY                : float = 980.0
const BASE_PROJECTILE_SPEED  : float = 600.0   # reference/default speed
const CORNER_THRESHOLD       : float = 0.15

# --- Gunbound-style firing input (user decision 2026-06-12) -------------------
const ANGLE_MIN_DEG  : float = 0.0     # 0 = horizontal right
const ANGLE_MAX_DEG  : float = 180.0   # 180 = horizontal left (90 = straight up)
const ANGLE_RATE_DEG : float = 45.0    # degrees/second while ↑/↓ held
const MIN_PROJECTILE_SPEED : float = 250.0
const MAX_PROJECTILE_SPEED : float = 950.0   # reference only; full charge = shot.base_speed
const CHARGE_TIME : float = 1.4        # seconds from min to max power
# Player full-charge launch speed = shot.base_speed × this (user request, M3): the M2
# values fell short and craters under-covered. Enemies (IK) are unaffected.
const PLAYER_POWER_MULT : float = 2.5

# --- M2 combat (M2 spec §4, §7) -----------------------------------------------
# M4: budget raised 5 → 10 so elemental modifiers (fire = 2 AP, electric = 3 AP) cost
# meaningfully against moves/shots without starving a turn. See milestone-4-plan.md §7.
const MAX_ACTIONS : int = 10           # shared action bar per player turn
const ENEMY_FIRE_DELAY : float = 0.8   # seconds between enemy shots
# Settle beat at the END of a shot's resolution routine (after AoE/FX, before the next unit
# is focused or the next enemy fires). Lets consequences read; future resolve actions
# (death animations, terrain collapse) slot in ahead of it. See ProjectileManager._on_impact.
const SHOT_RESOLVE_DELAY : float = 0.45
# Angles in this project are positive-up (0 = right, 90 = straight up).
# The spec's -45°/-60° (Godot y-down convention) map to +45/+60 here.
const ENEMY_LAUNCH_ANGLE_DEG : float = 45.0
const ENEMY_ALT_ANGLE_DEG    : float = 60.0
const ENEMY_ERROR_PCT : float = 0.05   # ±5% launch speed variance
const ENEMY_SPEED_MIN : float = 100.0  # IK result clamp
const ENEMY_SPEED_MAX : float = 2500.0 # cross-map shots need ~2000 px/s

# --- Wind (M8) ----------------------------------------------------------------
const MAX_WIND_FORCE        : float = 300.0  # px/s² horizontal acceleration at 100% wind (~30% of gravity)
const WIND_SPREAD_THRESHOLD : float = 0.2    # abs(wind_strength) must exceed this to drive fire spread

# --- Coordinate conversion (terrain spec §3.2) -------------------------------
static func world_to_voxel(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / VOXEL_SIZE), int(world_pos.y / VOXEL_SIZE))

static func voxel_to_world(vox: Vector2i) -> Vector2:
	return Vector2(vox.x * VOXEL_SIZE, vox.y * VOXEL_SIZE)

static func voxel_center_world(vox: Vector2i) -> Vector2:
	return Vector2((vox.x + 0.5) * VOXEL_SIZE, (vox.y + 0.5) * VOXEL_SIZE)

static func world_pixel_size() -> Vector2:
	return Vector2(MAP_WIDTH * VOXEL_SIZE, MAP_HEIGHT * VOXEL_SIZE)
