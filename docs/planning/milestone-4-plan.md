# Milestone 4 — Shot Varieties & Unit Roster

## Overview

Four new shot behaviors replace the homogeneous basic/elemental shells.  
Each becomes a dedicated player unit, giving the squad mechanical identity.  
Layered on top: per-unit angle/power memory, a larger action budget (10 AP), and
rebalanced element costs (fire 2 AP, electric 3 AP).

---

## §1 Locked Decisions

| # | Decision |
|---|----------|
| 1 | Cluster: sub-projectiles fly simultaneously; impacts are **queued** by `(collision_frame, proj_index)`; after each resolution the queue re-checks whether remaining queued voxels are still solid before resolving. |
| 2 | Cluster: `shot_resolved` fires only when **all** sub-projectiles in the salvo have exited (resolved or despawned). |
| 3 | Bypass: trail damage = 1 dmg per unique voxel the projectile's centre passes through (no radius, just centre-voxel); tracked in a `Dictionary` per flight. The `aoe_pattern` on the shot definition is the **unit-hit explosion** (big). |
| 4 | Bypass: unit collision is checked in `ProjectileManager._process` against all units, using bounding-box overlap; the same friendly-fire rules as AoEResolver apply. |
| 5 | Gravity pull: movement is **horizontal only** (left/right toward impact X), uses the same terrain + unit collision rules as `CombatManager.try_move`. Units are processed **closest first**. |
| 6 | Gravity pull: a unit that is pulled but blocked on the first step simply doesn't move (not an error). |
| 7 | Spiral: **3 projectiles** total — main (index 0) + two satellite arms (index 1, index 2). Satellites derive their world position from the main Projectile's current position + a sinusoidal perpendicular offset; they carry their own collision detection. |
| 8 | Spiral: satellites are `SpiralSatellite extends Node2D`; they are not `Projectile` subclasses but plug into the same impact queue and salvo counter. |
| 9 | All sub-projectiles in cluster/spiral inherit the same `AoEPattern` as the parent shot. No per-arm element variation in M4. |
| 10 | `Const.MAX_ACTIONS = 10`. Fire shell `action_cost = 2`. Electric shell `action_cost = 3`. Basic shell unchanged at 0. |
| 11 | Four player units, one per shot type. Each unit's `available_shots` = `[basic, fire_variant, electric_variant]` of its specialty. Enemies unchanged. |
| 12 | Angle memory is free — `Unit.aim_angle_deg` already persists. Power memory: `Unit.last_power_frac` saved on each fire; HUD draws a small triangle marker at that position on the charge bar. |

---

## §2 Cluster Shot

**Behaviour:**  
Five projectiles launched simultaneously, angles spaced 1° apart centred on the aim direction (−2°, −1°, 0°, +1°, +2°). Each carries the same `AoEPattern` (diamond radius 3).

**`ShotDefinition` fields added:**
```
projectile_count : int   = 1      # 5 for cluster
spread_deg       : float = 0.0    # spacing between adjacent sub-projectiles (deg)
```

**`Projectile` changes:**  
Add `proj_index : int` field (set at launch). When a sub-projectile detects a collision it **pauses** (`_active = false`) and calls `ProjectileManager.queue_impact(self, pos, voxel)` instead of emitting `impact` directly. It does NOT free itself.

**`ProjectileManager` impact queue:**
```
_pending_impacts : Array  # { proj, world_pos, voxel, frame, proj_index }
_salvo_remaining : int    # decremented on each resolved/despawned sub-projectile
```

Each frame, if `_resolving == 0` and `_pending_impacts` is not empty:
1. Pop the item with lowest `(frame, proj_index)`.
2. Re-check `_terrain.is_blocked(voxel)` — if no longer solid, **resume** the projectile (`proj._active = true`); do not resolve.
3. If still solid, run the resolution routine (same async pipeline as today). On completion, free the projectile and decrement `_salvo_remaining`; if `_salvo_remaining == 0` emit `shot_resolved`.

Projectiles that leave the map bounds also decrement `_salvo_remaining`.

---

## §3 Bypass / Drill Shot

**Behaviour:**  
Ignores terrain collision. As it flies, each unique voxel its centre occupies takes 1 damage (tracked per flight). If its bounding area overlaps any enemy unit, it stops and applies the `aoe_pattern` (big explosion: diamond radius 4, ~12 damage). If it leaves the map, it simply despawns.

**`ShotDefinition` fields added:**
```
bypass_terrain : bool = false
```
`aoe_pattern` = the unit-hit explosion (diamond r4, high damage).  
No trail AoEPattern resource needed — trail damage = 1 per voxel is applied directly.

**`Projectile` changes:**
```
var bypass_mode   : bool       = false
var _bypass_hit   : Dictionary = {}      # Vector2i → true (damaged voxels)
```

Modified `_physics_process` when `bypass_mode`:
- Skip `Trajectory.check_segment` for terrain.
- Compute current voxel; if not in `_bypass_hit`: call `_terrain.damage_tile(vox.x, vox.y, 1)`; mark in `_bypass_hit`.
- Unit overlap check is **not** in `Projectile` — it's in `ProjectileManager._process` (access to unit list):  
  Each frame, iterate all bypass projectiles; for each, test bounding box against units (same side as target). On hit: set `_active = false`, emit `impact(position, voxel)` with the shot's `aoe_pattern`, then free self.

`ProjectileManager` needs the units provider already available (`_units_provider`). It calls it each frame only for bypass projectiles (identified by `p.bypass_mode`).

---

## §4 Gravity Pull Shot

**Behaviour:**  
Normal arc projectile. On impact, the `aoe_pattern` resolves as usual (can carry an element). Then, **before the settle beat**, a `GravityPullResolver` step runs.

**`ShotDefinition` fields added:**
```
pull_near_radius  : int = 0   # ≤ this many voxels → pull_near_voxels steps
pull_far_radius   : int = 0   # ≤ this → pull_far_voxels steps (> near_radius)
pull_near_voxels  : int = 0   # steps pulled toward impact
pull_far_voxels   : int = 0
```
All 0 = no pull (default). Gravity pull shot: near_radius=4, far_radius=8, near_voxels=2, far_voxels=1.

**`systems/gravity_pull_resolver.gd`** — new static class:
```gdscript
static func resolve(terrain: TerrainManager, units: Array,
        impact_voxel: Vector2i, shot: ShotDefinition) -> void
```

Algorithm:
1. Collect all living units within `pull_far_radius` voxels of `impact_voxel` (Chebyshev or Manhattan — use voxel centre distance).
2. Sort ascending by distance.
3. For each unit:
   - `pull = pull_near_voxels` if dist ≤ near_radius, else `pull_far_voxels`.
   - `dir = sign(impact_voxel.x - unit.center_voxel().x)` (horizontal).
   - Attempt to move the unit `pull` steps in `dir` one at a time, using the same terrain + unit-bbox collision logic as `CombatManager._resolve_move`. Stop on first blocked step.
   - Call `_settle_unit` equivalent after pull.

`ProjectileManager._on_impact` calls `GravityPullResolver.resolve(...)` at the pluggable seam **after AoE damage, before settle beat**.

---

## §5 Spiral Shot

**Behaviour:**  
Three simultaneous projectiles: a main arc (index 0) and two satellite arms (index 1 and 2). The satellites oscillate in the direction perpendicular to the main trajectory:

```
offset(t) = perp * amplitude * sin(TAU * frequency * t)
arm_a position = main.position + offset(t)
arm_b position = main.position - offset(t)
where perp = main.velocity.normalized().rotated(PI / 2.0)
```

All three carry the same `AoEPattern`. All plug into the same impact queue and salvo counter.

**`ShotDefinition` fields added:**
```
spiral_arms      : int   = 0    # 0 = disabled, 2 = two arms
spiral_amplitude : float = 0.0  # perpendicular offset amplitude (world px), e.g. 24.0
spiral_frequency : float = 1.0  # oscillations per second, e.g. 2.0
```

**`SpiralSatellite extends Node2D`** — new file `projectile/spiral_satellite.gd`:
```gdscript
var main_proj    : Projectile
var arm_sign     : float   # +1 or -1
var amplitude    : float
var frequency    : float
var proj_index   : int
var pattern      : AoEPattern
var is_enemy     : bool
var _elapsed     : float = 0.0
var _active      : bool  = true
var _terrain     : TerrainManager

func _physics_process(delta):
    if not _active or not is_instance_valid(main_proj):
        return
    _elapsed += delta
    var perp := main_proj.velocity.normalized().rotated(PI / 2.0)
    var prev_pos := position
    position = main_proj.position + perp * amplitude * sin(TAU * frequency * _elapsed) * arm_sign
    var hit := Trajectory.check_segment(_terrain, prev_pos, position)
    if hit["collided"]:
        _active = false
        # queue to ProjectileManager (signal or direct call)
        _on_hit(hit["contact_point"], hit["impact_voxel"])
```

Satellites are added as children of `ProjectileManager` (like regular projectiles). Despawn when main exits the map.

Visual: main projectile drawn at radius 4 (existing), arms drawn at radius 2.

---

## §6 Per-Unit Angle & Power Memory

**Angle:** `Unit.aim_angle_deg` already persists between turns (no `reset_for_turn` reset). No change needed.

**Power:**  
`units/unit.gd` — add:
```gdscript
var last_power_frac : float = 0.5
```

`systems/combat_manager.gd` — in `_fire_active()`, before resetting `charge_frac`:
```gdscript
u.last_power_frac = charge_frac
```

`ui/hud.gd` — `set_power(current_frac, charging)` → `set_power(current_frac, charging, last_frac)`.  
HUD draws the charge bar normally, then draws a small triangle (▼, 6px) at `last_frac * bar_width` in white/light colour.

---

## §7 Action Economy

| Change | Old | New |
|--------|-----|-----|
| `Const.MAX_ACTIONS` | 5 | 10 |
| Fire shell `action_cost` | 1 | 2 |
| Electric shell `action_cost` | 1 | 3 |
| Basic shell `action_cost` | 0 | 0 |

The HUD already greys out unaffordable shots (M3). No new UI code needed, just data updates.  
Shock AP reduction (unit status) interacts with the larger budget as before.

---

## §8 Squad Roster

Four player units replace the two from M2/M3:

| Unit | Shot specialty | Color | Spawn col |
|------|---------------|-------|-----------|
| Cluster | 5-way spread (r3 diamond each) | Goldenrod | 8 |
| Bypass | Drill + unit-stop explosion | Teal | 11 |
| Gravity Pull | Arc + pull effect | Coral/Red | 14 |
| Spiral | Main + 2 oscillating arms | Purple | 17 |

Each unit's `available_shots = [basic_<type>, fire_<type>, electric_<type>]`.  
All units: `move_range = 99`, `climb_max = 1`, `width = 2, height = 3`, `max_hp = 6` (tunable).

---

## §9 Files Changed

### Modified
| File | What changes |
|------|-------------|
| `constants.gd` | `MAX_ACTIONS = 10` |
| `data/shots/shot_definition.gd` | Add `projectile_count`, `spread_deg`, `bypass_terrain`, `pull_near_radius`, `pull_far_radius`, `pull_near_voxels`, `pull_far_voxels`, `spiral_arms`, `spiral_amplitude`, `spiral_frequency` |
| `projectile/projectile.gd` | Add `proj_index`, `bypass_mode`, `_bypass_hit`. Modified `_physics_process` for bypass trail. Add `queue_impact` path (pauses instead of freeing) |
| `projectile/projectile_manager.gd` | Impact queue (`_pending_impacts`, `_salvo_remaining`). Bypass unit-check in `_process`. New `fire_multi()` entry point for cluster/spiral. Pull resolver call in `_on_impact` |
| `systems/combat_manager.gd` | Save `last_power_frac` on fire. Spawn 4 player units. Update `_unhandled_input` key mapping if shot count changes |
| `units/unit.gd` | Add `last_power_frac : float = 0.5` |
| `ui/hud.gd` | `set_power` draws last-power triangle marker |
| `scripts/bake_resources.gd` | New shot definitions (12 shots: 4 types × 3 elements), new AoE patterns (r3, r4), 4 player unit .tres |

### New
| File | Purpose |
|------|---------|
| `projectile/spiral_satellite.gd` | Satellite arm node for spiral shot |
| `systems/gravity_pull_resolver.gd` | Static class — pull step logic |
| `data/shots/aoe/diamond_r3.tres` | Cluster sub-projectile pattern |
| `data/shots/aoe/diamond_r4*.tres` | Bypass unit-hit explosion (base, fire, electric variants) |
| `data/shots/cluster_*.tres` | 3 cluster shell definitions |
| `data/shots/bypass_*.tres` | 3 bypass shell definitions |
| `data/shots/pull_*.tres` | 3 pull shell definitions |
| `data/shots/spiral_*.tres` | 3 spiral shell definitions |
| `data/units/player_cluster.tres` | ... |
| `data/units/player_bypass.tres` | ... |
| `data/units/player_pull.tres` | ... |
| `data/units/player_spiral.tres` | ... |

---

## §10 Deviations & decisions made during execution

1. **Friendly fire stays off** (bypass). The drill stops only on an *opposing* unit, matching
   `AoEResolver`'s established rule — player shots hit enemies, enemy shots hit players.
2. **Spiral main projectile collides** like a real shot (it's not just a guide path). Its two
   arms collide independently and feed the same impact queue.
3. **Spiral arms don't outlive the main projectile.** If the main resolves or leaves the map,
   remaining arms despawn that frame (a satellite derives its position from the main, so it has
   no trajectory to follow once the main is gone). Arms that hit the *same* frame as the main
   still resolve (drain is index-ordered, manager runs before child bodies). Acceptable for a
   prototype; revisit if arms-after-main becomes desirable.
4. **Pull direction is fixed at the unit's initial side**, not recomputed per step. The spec is
   "pulled *by* N voxels," so a unit is dragged the full distance even if that carries it up to
   or just past the impact column — rather than halting the instant its centre aligns.
5. **Settle beat is salvo-level, not per-impact.** Cluster/spiral sub-impacts resolve back-to-
   back (synchronous AoE), then one `SHOT_RESOLVE_DELAY` plays before `shot_resolved`. Keeps a
   5-pellet cluster from taking 5×0.45 s to clear.
6. **Impact ordering uses `Engine.get_physics_frames()` + salvo index.** The manager's
   `_physics_process` runs before its child bodies (tree order), so `pending` only ever holds
   impacts from strictly-earlier frames — no frame is half-collected when drained.
7. **Pull settles units after shoving** (vertical fall into craters) via `UnitMovement.settle`,
   reusing the same fall logic as `AoEResolver`-driven settling.

---

## §11 Bake Workflow

Same as M3:
```
godot --headless --import
godot --headless -s scripts/bake_resources.gd
godot --headless --import
```

---

## §12 Smoke Test Checklist

```
[cluster] fire cluster shot → 5 projectiles visible in flight
[cluster] sub-projectile hits terrain before others → terrain destroyed → later sub-projectile passes through that spot
[cluster] shot_resolved only fires after last sub-projectile resolves
[bypass] projectile flies through terrain visually
[bypass] terrain voxels along path lose HP; no voxel damaged twice
[bypass] projectile stops and explodes on overlapping enemy unit
[bypass] projectile despawns on exit with no explosion
[pull] unit within 4 voxels pulled 2 steps toward impact
[pull] unit 4–8 voxels away pulled 1 step
[pull] unit blocked by terrain not pulled
[pull] closer unit pulled first; its new position blocks farther unit
[spiral] 3 visual objects in flight
[spiral] arm hits terrain → queued → resolves before main if earlier frame
[memory] after firing, next turn aim_angle_deg unchanged
[memory] power marker visible on charge bar at last_power_frac
[economy] fire variant greys when actions_left < 2
[economy] electric variant greys when actions_left < 3
[economy] 10 AP available at turn start (no shock)
```
