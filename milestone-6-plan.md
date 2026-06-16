# Milestone 6 — Turn-Phase Clarity & Deployable Objects (Mines, Shield Generators)

## Overview

M5 added cards and the first mitigation layer (Shield). The card-engine design doc envisions
effects that trigger on specific turn phases (e.g. "at the start of your turn") and a category
of non-unit, on-map entities ("deployables"/"artifacts") that cards or future content can place.
Before building more cards/artifacts, this milestone makes the turn structure explicit (so
phase-triggered effects have a clear, loggable hook) and introduces the first deployable
entities — mines and shield generators — proving out the entity type, its damage/falling
physics, and its proximity/phase trigger hooks that later content will reuse.

---

## §1 Locked Decisions

| # | Decision |
|---|----------|
| 1 | The 5 requested phases (round start, player-turn start/end, enemy-turn start/end) map onto existing `EventBus` signals (`round_started`, `turn_started`/`turn_ended` with `"player"`/`"enemy"`) — **no new turn signals added**. Nomenclature stays consistent with what already exists (confirmed with user). |
| 2 | Phase visibility is solved with a `_log_phase(label)` console banner next to each of the 5 existing emits — no UI work this milestone, per explicit scope ("this can be done right now with some debug text in the console"). |
| 3 | Deployables are hand-placed at fixed columns via a hardcoded `_DEPLOYABLE_PLACEMENTS: Array[Dictionary]` on `CombatManager`, mirroring the M5 reinforcement-schedule pattern (confirmed with user: "hardcoded test placements," no scatter/editor tooling). |
| 4 | `Deployable` is a sibling type to `Unit`, not a subclass — it has HP/position/falling but none of `Unit`'s action economy, statuses, or shot loadout. Falling physics is shared by extracting `UnitMovement.settle_at(pos, w, h, terrain)` as the position-only core of `UnitMovement.settle(unit, terrain)`. |
| 5 | Mine proximity trigger reuses a **generalized** `EventBus.unit_moved` signal (confirmed with user's own suggestion) rather than a bespoke per-frame distance check. The emit moves from `CombatManager.try_move()` into the single chokepoint `Unit.set_vox_position()`, so every movement cause (player move, knockback, gravity pull, falling, undo) notifies listeners uniformly. Signature gains `from`/`to`: `unit_moved(unit, from, to)`. |
| 6 | A mine's two death triggers (hit by AoE, player proximity) funnel through the **same** `_die()` path: proximity calls `mine.take_damage(mine.hp)` directly (lethal self-damage) rather than introducing a separate `detonate()` method. |
| 7 | `Mine` never calls `AoEResolver` directly — it only emits `EventBus.mine_detonated`; `CombatManager` (the orchestrator) listens and runs the actual blast. This preserves the project's "no direct cross-system calls" rule. |
| 8 | `AoEResolver.resolve()` gains an optional `deployables: Array = []` 6th param and a parallel dominant-hit-per-blast pass for them — **without** element/affinity logic (deployables are inert structures, unlike units). Kept as a separate loop rather than retrofitting the existing `Unit`-typed helpers (`_should_damage`/`_voxel_in_bbox`/`_calc_damage`), since `Deployable` isn't a `Unit` and forcing a shared interface would touch well-tested code for no benefit. |
| 9 | Shield generators are ally-only this milestone (per explicit instruction — "not a hard constraint," easy to widen later) and pulse once per player-turn-start via `CombatManager._pulse_shield_generators()`, reusing `Unit.add_shield()` from the M5 shield fix so the shield bar redraw fires correctly. |
| 10 | New `Features.deployables_enabled: bool = true` kill switch, following the `shields_enabled` precedent, gating `_spawn_deployables()`, `_pulse_shield_generators()`, and `_check_mine_triggers()`. |

---

## §2 Deployable Base Class

`world/deployable.gd` — HP, voxel position/bbox, damage, and a generic death signal:

```gdscript
class_name Deployable
extends Node2D

var max_hp : int = 1
var hp : int = 1
var vox_position : Vector2i = Vector2i.ZERO
var width_voxels : int = 1
var height_voxels : int = 1
var display_name : String = "Deployable"
var color : Color = Color.GRAY

func set_vox_position(p: Vector2i) -> void:
    vox_position = p
    position = Const.voxel_to_world(p)

func bounds_rect_world() -> Rect2:
    return Rect2(Const.voxel_to_world(vox_position),
        Vector2(width_voxels, height_voxels) * Const.VOXEL_SIZE)

func contains_voxel(vox: Vector2i) -> bool:
    return vox.x >= vox_position.x and vox.x < vox_position.x + width_voxels \
        and vox.y >= vox_position.y and vox.y < vox_position.y + height_voxels

func take_damage(dmg: int) -> void:
    if hp <= 0:
        return
    hp = maxi(0, hp - dmg)
    queue_redraw()
    if hp == 0:
        _die()

func _die() -> void:
    EventBus.deployable_died.emit(self)

func _draw() -> void:
    var w := width_voxels * Const.VOXEL_SIZE
    var h := height_voxels * Const.VOXEL_SIZE
    draw_rect(Rect2(0, 0, w, h), color)
    draw_rect(Rect2(0, 0, w, h), color.darkened(0.4), false, 1.0)
```

Mirrors `Unit`'s `set_vox_position`/`bounds_rect_world`/`contains_voxel` exactly, so it slots
into the existing click-hit-test and AoE-overlap patterns without new geometry code.

**Falling physics reuse**: extracted the position-only core out of `UnitMovement.settle()`:

```gdscript
static func settle_at(pos: Vector2i, w: int, h: int, terrain: TerrainManager) -> Vector2i:
    var foot := pos.y + h - 1
    while foot < Const.MAP_HEIGHT - 1 and not grounded(terrain, pos.x, foot, w):
        foot += 1
    return Vector2i(pos.x, foot - h + 1)

static func settle(unit: Unit, terrain: TerrainManager) -> Vector2i:
    return settle_at(unit.vox_position, unit.definition.width_voxels,
            unit.definition.height_voxels, terrain)
```

`CombatManager._on_aoe_resolved()` settles every deployable the same beat it settles units, via
`UnitMovement.settle_at(d.vox_position, d.width_voxels, d.height_voxels, _terrain)`.

---

## §3 Mine (`world/mine.gd`, extends Deployable)

- `max_hp = 1`, `hp = 1` — any hit is instant death.
- `@export var trigger_radius : int = 3` (voxels, Chebyshev distance).
- `@export var explosion_pattern : AoEPattern` — baked `res://data/shots/aoe/diamond_mine.tres`
  (`AoEPattern.make_diamond(2, 4, 1.0)`, same helper already used for shot patterns).
- Overrides `_die()`: emits `EventBus.mine_detonated(self)` in addition to the inherited
  `deployable_died`, so `CombatManager` can run the actual explosion.

Two ways a mine dies, same `_die()` path:
1. **Hit by AoE** → `take_damage()` (via the AoEResolver deployable pass) drains its 1 HP.
2. **Proximity** → `CombatManager._check_mine_triggers()` (listening on the generalized
   `unit_moved`) calls `mine.take_damage(mine.hp)` when a **player** unit moves within
   `trigger_radius`. Enemies don't trigger mines.

`CombatManager._on_mine_detonated()` runs the actual blast:
```gdscript
func _on_mine_detonated(mine: Deployable) -> void:
    AoEResolver.resolve(_terrain, all_units, mine.vox_position,
            mine.explosion_pattern, false, deployables)
```

---

## §4 Shield Generator (`world/shield_generator.gd`, extends Deployable)

- `max_hp = 5`, `hp = 5` — destructible like a unit, no special death behavior.
- `@export var aura_radius : int = 10` (voxels, Chebyshev).
- `@export var shield_amount : int = 2`.

`CombatManager._pulse_shield_generators()` (called from `_start_player_turn()`, right after
`_save_checkpoint()`):
```gdscript
func _pulse_shield_generators() -> void:
    for d in deployables:
        if d is ShieldGenerator and d.hp > 0:
            for u in player_units:
                if u.hp > 0 and _chebyshev(d.vox_position, u.vox_position) <= d.aura_radius:
                    u.add_shield(d.shield_amount)
                    EventBus.unit_shield_changed.emit(u, u.shield)
```

---

## §5 AoEResolver: deployables take splash damage

`resolve()` gains a 6th param and a parallel dominant-hit-per-blast pass:

```gdscript
static func resolve(terrain: TerrainManager, units: Array, origin: Vector2i,
        pattern: AoEPattern, is_enemy: bool, deployables: Array = []) -> Array:
    ...
    var deployable_hit : Dictionary = {}   # Deployable -> dmg
    for offset in aoe_map:
        ...
        for d in deployables:
            if d.hp <= 0 or not d.contains_voxel(target):
                continue
            var prev = deployable_hit.get(d, null)
            if prev == null or group.damage > prev:
                deployable_hit[d] = group.damage
    for d in deployable_hit:
        d.take_damage(deployable_hit[d])
    ...
```

Wired through `ProjectileManager._deployables_provider: Callable` (mirrors the existing
`_units_provider`), set via `setup()`, called lazily at impact time — set from
`world/combat_scene.gd` (`projectiles.setup(terrain, combat.get_units, combat.get_deployables)`).
The few smoke-test-only `AoEResolver.resolve(...)` calls without the 6th arg still work (default
`[]`).

---

## §6 Mine proximity trigger via generalized `unit_moved`

`unit_moved` was previously emitted only from `CombatManager.try_move()` — missing knockback/
gravity-pull/falling. Moved into the single chokepoint, `Unit.set_vox_position()`:

```gdscript
func set_vox_position(p: Vector2i) -> void:
    var from := vox_position
    vox_position = p
    position = Const.voxel_to_world(p)
    if from != p:
        EventBus.unit_moved.emit(self, from, p)
```

`event_bus.gd` signature: `signal unit_moved(unit: Unit, from: Vector2i, to: Vector2i)`. The
redundant manual emit at the end of `try_move()` was removed.

`CombatManager.setup()` connects `EventBus.unit_moved.connect(_check_mine_triggers)`:
```gdscript
func _check_mine_triggers(unit: Unit, _from: Vector2i, to: Vector2i) -> void:
    if not Features.deployables_enabled:
        return
    if not unit.is_player or unit.hp <= 0:
        return
    for d in deployables:
        if d is Mine and d.hp > 0 and _chebyshev(d.vox_position, to) <= d.trigger_radius:
            d.take_damage(d.hp)
```

A shared `_chebyshev(a, b) -> int` helper (`maxi(absi(a.x-b.x), absi(a.y-b.y))`) is used by both
this and §4's aura check.

---

## §7 Spawning, layering, cleanup

**Scene wiring**: two new `Node2D` children — `DeployableLayerBack` (between `TerrainRenderer`
and `ProjectileManager`, so mines sit visually under projectiles/units) and
`DeployableLayerFront` (after `UnitLayer`, before `CombatManager`, so a shield generator's
footprint renders over units). Both passed through `CombatManager.setup()`'s extended signature.

**CombatManager additions:**
- `var deployables : Array = []`
- ```gdscript
  const _DEPLOYABLE_PLACEMENTS : Array[Dictionary] = [
      { "type": "mine", "col": 40 },
      { "type": "mine", "col": 60 },
      { "type": "shield_generator", "col": 95 },
  ]
  ```
- `_spawn_deployables()` (called once from `setup()`, after `_spawn_all_units()`, gated by
  `Features.deployables_enabled`): builds a `Mine.new()` or `ShieldGenerator.new()` per entry,
  snaps to `_terrain.get_surface_row(col)`, sets position, adds to the back layer (mine) or
  front layer (shield generator), appends to `deployables`.
- `_on_deployable_died(d)`: `deployables.erase(d); d.queue_free()` — connected once globally in
  `setup()`, not per-instance.
- `get_deployables() -> Array` — for the `ProjectileManager` provider callable.

---

## §8 Files Changed

### New
| File | Purpose |
|---|---|
| `world/deployable.gd` | `Deployable` base class (HP, voxel position, draw, take_damage). |
| `world/mine.gd` | `Mine` — 1 HP, proximity + hit detonation, explosion AoE. |
| `world/shield_generator.gd` | `ShieldGenerator` — aura shield buff to allies on player-turn start. |
| `data/shots/aoe/diamond_mine.tres` | Mine explosion AoE pattern (baked). |
| `milestone-6-plan.md` | This document. |

### Modified
| File | What changes |
|---|---|
| `systems/combat_manager.gd` | `_log_phase()` at the 5 transition points; `deployables` array + `_DEPLOYABLE_PLACEMENTS` + `_spawn_deployables()`; `_pulse_shield_generators()`; `_check_mine_triggers()`; `_chebyshev()`; `_on_mine_detonated()`; `_on_deployable_died()`; `get_deployables()`; settle deployables alongside units in `_on_aoe_resolved()`. |
| `systems/unit_movement.gd` | Extracted `settle_at(pos, w, h, terrain)` core from `settle(unit, terrain)`. |
| `units/unit.gd` | `set_vox_position()` emits generalized `unit_moved(unit, from, to)`. |
| `autoloads/event_bus.gd` | `unit_moved` signature gains `from`/`to`; added `deployable_died(deployable)`, `mine_detonated(mine)`. |
| `autoloads/features.gd` | Added `deployables_enabled : bool = true`. |
| `terrain/aoe_resolver.gd` | `resolve()` gained optional `deployables: Array = []` param + parallel damage pass. |
| `projectile/projectile_manager.gd` | Added `_deployables_provider: Callable`, passed through to `AoEResolver.resolve()`. |
| `world/combat_scene.tscn` / `combat_scene.gd` | Added `DeployableLayerBack`/`DeployableLayerFront` nodes; wired into `CombatManager.setup()` and `ProjectileManager.setup()`; added `_m6_smoke()`. |
| `scripts/bake_resources.gd` | Baked `diamond_mine.tres`. |

---

## §9 Deviations & decisions made during execution

1. No deviations from the plan as approved — all method signatures, hook points, and the file
   list were followed as written during plan mode. The only addition beyond the original plan
   sketch was making `_check_mine_triggers()` explicitly re-check `Features.deployables_enabled`
   at its own entry point (belt-and-suspenders with the `setup()`-time connect), matching the
   project's "systems check their flag at their ENTRY POINT" convention in `features.gd`'s header
   comment.

---

## §10 Bake Workflow

Same as M3/M4/M5:
```
godot --headless --import
godot --headless -s scripts/bake_resources.gd
godot --headless --import
```

---

## §11 Smoke Test Checklist

All items verified via `ARTILLERY_SMOKE=1 godot --headless` (`_m6_smoke()` in
`world/combat_scene.gd`):

```
[phase] 5 === [PHASE] === banners print in order across one round (visual check)
[mine] hit by AoE: drains to 0 hp, removed from deployables, nearby unit takes splash damage
[mine] proximity: a player unit moving within trigger_radius detonates the mine without a direct hit
[mine] proximity: an enemy unit moving within trigger_radius does NOT detonate the mine
[shield generator] an ally within aura_radius gains shield_amount at player-turn start
[shield generator] an ally outside aura_radius gains nothing
[shield generator] destruction (hp -> 0) removes it from deployables and frees the node
[deployable] falls via UnitMovement.settle_at when terrain beneath it is destroyed
[feature flag] Features.deployables_enabled = false: aura pulse is a no-op
```

Manual playtest (not done in this headless pass — recommended before shipping): confirm mines
visually sit behind units/projectiles, the shield generator's footprint renders in front, walking
a unit near a mine blows it up, and the generator visibly buffs the shield bar each player-turn
start.
