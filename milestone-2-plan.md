# Artillery Space — Milestone 2 Implementation Plan

*Companion to [M2 spec](artillery-space-m2-spec.docx) and [M1 plan](milestone-1-plan.md).*

M2 introduces the first playable combat loop: 2 player units vs 2 enemy units, HP, turn structure,
shared action bar, movement, enemy IK firing, and win/loss detection. It builds directly on the M1
terrain and ballistic foundation.

---

## 0. Locked Decisions (M2)

| Topic | Decision | Rationale |
| :---- | :---- | :---- |
| **Firing model** | **Gunbound** (↑/↓ angle · Space charge · release fires) | User decision; carried from M1 |
| **Arrow key split** | ↑/↓ = angle · ←/→ = movement | Natural split; no conflict |
| **Enemy spawn** | **Surface-snap** (no indestructible platform on right) | User decision; keeps terrain fair |
| **Unit-unit collision** | Units cannot share any voxel in their bounding box | User-added constraint (missing from spec) |
| **Scene evolution** | Evolve `world.tscn` in place; rename to `combat_scene.tscn` | Avoids duplication |
| **Unit node type** | `Node2D` (not CharacterBody2D) | Discrete tile movement; no physics body needed |
| `AoEResolver` | Stays static class (no node); signature changes to accept `AoEPattern` + units | Matches M2 spec §6.3 |
| **Mouse aim (spec §5.3)** | **Not implemented.** AimLine tracks stored `aim_angle_deg` (Gunbound). Left-click = unit selection only. | Gunbound model supersedes spec §5.3–5.4 |

---

## 1. Spec Reconciliations

### 1.1 `diamond_r2.tres` damage values vs. M1 `BASE_DAMAGE=4`

The spec defines diamond_r2 as damage **3 / 2 / 1** (center / ring-1 / ring-2). M1 used
`BASE_DAMAGE=4` to make craters visible on 3-HP terrain. At damage 3:
- center tile: destroyed (3 HP → 0)
- ring-1 tiles: 2 damage → 1 HP remaining (heavy cracks) ✓
- ring-2 tiles: 1 damage → 2 HP remaining (light cracks) ✓

The 3/2/1 values are **correct** for M2 because unit HP is now 4–9; damage 3 at center (half a
heavy unit's HP) is well-scaled. The M1 `BASE_DAMAGE=4` constant is superseded by the .tres file.

### 1.2 AimLine interpretation

Spec §3.1 defines AimLine as pointing toward cursor. In the Gunbound model, AimLine tracks
`unit.aim_angle_deg` (updated by ↑/↓). No mouse-direction tracking. The Line2D on the Unit scene
shows a short barrel-direction indicator — same visual outcome, different input.

### 1.3 Left-click routing

Spec §5.4 says left-click fires. In M2: left-click = unit selection. Space = charge + fire. HUD
hint text updated accordingly. This is consistent with M1's click-to-select intent.

### 1.4 `AoEResolver` breaking change

M1 `AoEResolver.resolve(terrain, cx, cy, radius, base_damage)` is replaced by
`AoEResolver.resolve(terrain, units, origin, pattern, is_enemy)`. The `Trajectory` preview is also
updated to use `AoEPattern.to_map()` for the footprint overlay — the preview will show the actual
pattern shape, not just a diamond estimate.

### 1.5 Unit-unit collision (user-added rule)

Missing from spec. Applied in two places:
1. **Spawn placement**: `_find_valid_spawn(col, side)` surface-snaps then checks all placed units.
   If occupied, tries adjacent columns until clear.
2. **Movement**: `_find_landing_row` rejects a landing position if any voxel of the moving unit's
   resulting bounding box overlaps an existing unit's bounding box.

---

## 2. Architecture Changes M1 → M2

### New files
```
data/
  shots/
    aoe_group.gd          class_name AoEGroup extends Resource
    aoe_pattern.gd         class_name AoEPattern extends Resource
    shot_definition.gd     class_name ShotDefinition extends Resource
    basic_shell.tres
    aoe/diamond_r2.tres
  units/
    unit_definition.gd     class_name UnitDefinition extends Resource
    player_heavy.tres
    player_light.tres
    enemy_static.tres
units/
  unit.gd                  class_name Unit extends Node2D  (replaces player_unit.gd)
  unit.tscn                scene with HPBar, SelectionIndicator, AimLine, BarrelOrigin
systems/
  combat_manager.gd        owns: game_state, action_bar, unit selection, input routing
  enemy_system.gd          IK solver, target selection, fire sequence, error application
world/
  combat_scene.tscn        evolved from world.tscn
  combat_scene.gd          evolved from world.gd (thin; delegates to CombatManager)
```

### Modified files
| File | Change |
| :---- | :---- |
| `terrain/aoe_resolver.gd` | New signature; adds unit damage loop; friendly-fire filter |
| `projectile/projectile.gd` | Accepts `gravity_scale` + `AoEPattern`; calls new resolver |
| `projectile/projectile_manager.gd` | `spawn(origin, dir, shot, is_enemy)` via ShotDefinition |
| `projectile/trajectory.gd` | Preview uses `AoEPattern.to_map()` for footprint; accepts shot |
| `ui/targeting_overlay.gd` | Tracks active `Unit`'s `aim_angle_deg`; uses pattern footprint |
| `ui/hud.gd` | Adds action pips, unit info panel, End Turn + Undo buttons, turn indicator |
| `terrain/terrain_manager.gd` | `generate()` gets second enemy-side spawn search |
| `constants.gd` | Add `MAX_ACTIONS`, `ENEMY_FIRE_DELAY`, `ENEMY_LAUNCH_ANGLE/ALT/ERROR_PCT` |

### Deprecated
- `units/player_unit.gd` — replaced by `Unit` + `UnitDefinition`

---

## 3. Build Phases

| Phase | Goal | Ends when… |
| :---- | :---- | :---- |
| **P1** | Data resource classes + .tres files | `.tres` files load without errors; `AoEPattern.to_map()` returns correct offsets |
| **P2** | `Unit` scene + visual states | Unit renders with HP bar; `take_damage()` depletes bar and triggers death visual |
| **P3** | `AoEResolver` upgrade | Pattern-based AoE damages terrain AND units; friendly fire off; signals correct |
| **P4** | `Projectile` + `ProjectileManager` upgrade | Shot fires with gravity_scale from ShotDefinition; impact resolves new AoE |
| **P5** | `CombatManager` scaffold + unit placement | 4 units appear on map at valid, non-overlapping surface positions |
| **P6** | Unit selection + HUD info panel | Tab cycles, click selects; name/HP updates in HUD; per-unit aim state in overlay |
| **P7** | Movement (←/→) + unit-unit collision + undo | Unit moves, climbs, falls; blocks on walls and on other units; undo restores position |
| **P8** | Action bar + End Turn | Pip HUD depletes on move; End Turn button; Done state desaturates unit |
| **P9** | Enemy system | Enemies fire at correct angle+speed toward nearest player; ±5% spread visible |
| **P10** | Win/loss + game state blocking | STAGE CLEAR / GAME OVER logged; input blocked after terminal state |

### Per-phase acceptance checks (manual)
- **P1:** In the editor inspector, open `diamond_r2.tres` → `groups[0].offsets = [(0,0)]`, `damage = 3`.
- **P2:** Fire a shot directly at Unit1 with a point-blank shot → HP bar drops; two shots kill it → dark red tint, bar hides.
- **P3:** Shot landing at a unit's feet → terrain craters AND unit HP depletes; enemy shot misses a player → no player damage.
- **P5:** Relaunch 3× with different seeds — units always land on solid ground, never overlap.
- **P7:** Walk a unit into the other player unit → blocked. Walk to a 1-voxel cliff → falls to ground, no damage.
- **P9:** Observe 5 consecutive enemy turns — some shots land left/right of the player, not all center (visible ±5% spread).
- **P10:** Kill both enemies → "STAGE CLEAR" in output, ←/→ no longer moves units.

---

## 4. Key Implementation Notes

### 4.1 Surface-snap spawn with collision check

```gdscript
func _find_valid_spawn(preferred_col: int, all_units: Array) -> Vector2i:
    var col := preferred_col
    var max_tries := 10
    for _i in range(max_tries):
        var surface_row := terrain.get_surface_row(col)
        if surface_row == -1:
            col += 1
            continue
        var top_left := Vector2i(col, surface_row - unit_def.height_voxels)
        if not _overlaps_any_unit(top_left, unit_def, all_units):
            return top_left
        col += 1   # try next column
    push_error("Could not find valid spawn near col %d" % preferred_col)
    return Vector2i(preferred_col, 0)
```

### 4.2 Gunbound input in CombatManager + Movement split

```
↑ / ↓      → adjust active_unit.aim_angle_deg (held = continuous, rate = ANGLE_RATE_DEG)
← / →      → try_move(active_unit, direction)   (one keypress = one voxel; no hold repeat)
Space hold  → charge_frac += delta / CHARGE_TIME; auto-fire at 1.0
Space release → _fire_active_unit()
```

Hold-repeat for ←/→ would feel sloppy for tactical positioning — single-press per voxel is correct.
Implement via `_unhandled_input` for the keypress (not _process).

### 4.3 Charge preview uses ShotDefinition

`TargetingOverlay` receives the active `Unit` and its `ShotDefinition`. Speed interpolates
`MIN_PROJECTILE_SPEED → shot.base_speed` (not the old `MAX_PROJECTILE_SPEED` constant).
AoE footprint calls `shot.aoe_pattern.to_map()` and draws each group with opacity proportional to
`group.damage / max_group_damage` so the damage gradient is visible in the preview.

### 4.4 Enemy direction

Enemy units are on the right side of the map and fire left. Direction flips based on sign of
`(target.vox_position.x - enemy.vox_position.x)`:
```gdscript
var aim_to_left := target_pos.x < barrel.x
var angle := deg_to_rad(ENEMY_LAUNCH_ANGLE)   # always upward
var dir := Vector2(cos(angle) * (-1.0 if aim_to_left else 1.0), sin(angle))
```
(The IK `dx` in `solve_launch_speed` is always positive; the direction vector handles orientation.)

### 4.5 IK solver edge cases

- `solve_launch_speed` returns `-1.0` → try `ENEMY_ALT_ANGLE` (-60°) → still -1 → skip + warn.
- Clamped to `[MIN_PROJECTILE_SPEED, MAX_PROJECTILE_SPEED * 1.5]` after error application to
  prevent runaway values on near-miss edge cases.

### 4.6 `aoe_resolved` signal and `flush_collapses`

The existing M1 `AoEResolver.resolve()` calls `terrain.flush_collapses()` after the blast.
The M2 version does the same — collapse is always batched and flushed once per projectile impact,
after terrain AND unit damage have both been applied.

---

## 5. Open Questions (from spec §11)

These are already answered or unchanged from the spec's recommendations:

| # | Question | Answer |
| :---- | :---- | :---- |
| 1 | Fire cost? | 0 actions; firing ends activation. |
| 2 | Undo refunds actions? | Yes; full refund of all move actions from this activation. |
| 3 | Enemy launch angle configurable? | Hardcoded -45° / -60° fallback for M2. |
| 4 | IK no-solution? | Try alt angle; skip + warn if still none. |
| 5 | Dead units removed? | Stay visible as greyed wrecks. |
| 6 | Action bar auto-end-turn? | No; red border signals, player must press. |

---

## 6. Out of Scope (unchanged from spec §1.2)

Enemy movement, intent telegraphing UI, faction mechanics, upgrades, audio, RUBBLE tile,
special shots, step-by-step undo, stage reset/scene transition, arc clearance validation.
