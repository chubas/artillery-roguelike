# Milestone 7 — AoE Zone Model & Pattern Indicator

## Overview

Through M1–M6, `AoEGroup` baked a flat `damage: int` per ring, fusing shape and magnitude:
changing a shot's power meant re-baking the pattern, and there was no way to scale a unit's
overall punch without touching every pattern it uses. Per `artillery-space-ui-visual-indicators.md`
§2, this milestone decouples them: the **pattern** defines shape + a small number of strength
**zones** (core 1.0×, edge 0.5×, extensible to more later), and the **source** (a unit's power, or
a mine's fixed value) supplies the **magnitude**. Final damage = `strength × zone multiplier`.
This also unblocks a compact, terrain-independent pattern-zone glyph in the unit details card
(orange = core, yellow = edge), distinct from the existing in-world targeting preview.

---

## §1 Locked Decisions

| # | Decision |
|---|----------|
| 1 | Strength = `ShotDefinition.strength × Unit.power`; mines carry their own fixed `strength` field with no unit-power factor (confirmed with user, option "A1"). |
| 2 | Zones are a plain `multiplier: float = 1.0` directly on `AoEGroup` — no enum. A third zone later is just another `AoEGroup` with a different multiplier (confirmed, "A2"). |
| 3 | The new pattern-zone glyph lives inside the existing `UnitInspector` class in `ui/hud.gd`, not a new standalone widget (confirmed, "A3"). |
| 4 | The zone→color palette (`AoEPattern.zone_color()`) is a single static function shared by both the in-world `targeting_overlay.gd` preview and the unit-card glyph, so the two views stay visually consistent. |
| 5 | `make_diamond()` keeps producing exactly two groups (core/edge) regardless of pattern size — directly mirrors the design doc's two-tier model; other shapes (line, cross, irregular) would produce the same `AoEGroup`/`AoEPattern` structures via their own authoring helpers, needing no resolver changes. |

---

## §2 Data model changes

**`data/shots/aoe_group.gd`** — `damage: int` → `multiplier: float = 1.0`. `offsets`/`element`
unchanged.

**`data/shots/aoe_pattern.gd`** — `make_diamond(radius, base_dmg, falloff)` →
`make_diamond(core_radius: int, edge_radius: int) -> AoEPattern`: rings `0..core_radius` go into
one `AoEGroup` with `multiplier = 1.0`, rings `core_radius+1..edge_radius` into a second with
`multiplier = 0.5`. Dropped `max_damage()` (no longer meaningful). Added:

```gdscript
static func zone_color(multiplier: float) -> Color:
    if multiplier >= 1.0:
        return Color(1.0, 0.55, 0.1)
    if multiplier >= 0.5:
        return Color(0.95, 0.85, 0.2)
    return Color(0.6, 0.6, 0.6).lerp(Color(0.95, 0.85, 0.2), multiplier / 0.5)
```

**`data/shots/shot_definition.gd`** — added `@export var strength: int = 3`, the shot's baseline
magnitude, now independent of pattern shape.

**`data/units/unit_definition.gd`** — added `@export var base_power: float = 1.0`.
**`units/unit.gd`** — added `var power: float = 1.0`, initialized from `definition.base_power` in
`_ready()`, mutable so future upgrades can scale it without touching any pattern.

**`world/mine.gd`** — added `@export var strength: int = 4` (mines aren't fired by a unit, so they
carry their own fixed blast magnitude rather than going through `Unit.power`).

---

## §3 AoEResolver & call sites

`resolve()` gained a `strength: int` param:

```gdscript
static func resolve(terrain: TerrainManager, units: Array, origin: Vector2i,
        pattern: AoEPattern, strength: int, is_enemy: bool, deployables: Array = []) -> Array
```

Every read of `group.damage` became `_zone_damage(strength, group.multiplier)`:

```gdscript
static func _zone_damage(strength: int, multiplier: float) -> int:
    return maxi(1, int(round(strength * multiplier)))
```

(matches the existing minimum-1-damage convention from `_calc_damage`). Affinity multipliers in
`_calc_damage()` still apply on top of this, unchanged.

**Callers updated:**
- `projectile/projectile_manager.gd` — `Salvo` gained a `strength: int` field, set when the salvo
  is created: `roundi(shot.strength * (firing_unit.power if firing_unit != null else 1.0))`.
- `systems/combat_manager.gd` — `_on_mine_detonated()` passes `mine.strength` (no unit factor).
- `world/combat_scene.gd` — the smoke-test-only `resolve()` calls got an explicit literal
  `strength` argument (mostly `3`, matching the old ring-0 magnitudes; not gameplay-critical).

---

## §4 World preview rework

`ui/targeting_overlay.gd`'s `_draw_pattern_footprint()` previously read `group.damage`/
`pattern.max_damage()` for a continuous opacity gradient; both are gone. Replaced with
`AoEPattern.zone_color(group.multiplier)` for a flat, discrete fill — still tinting unit-occupied
voxels orange per the existing direct-hit highlight, unchanged. This was the minimum change
needed to keep the preview compiling and correct; a terrain-conforming preview redesign stays out
of scope.

---

## §5 New unit-card pattern-zone indicator

`UnitInspector._draw()` (in `ui/hud.gd`) gained a call to a new `_draw_pattern_glyph(pattern,
rect)`, sourced from the unit's active shot (`shot.aoe_pattern`), placed in the card's top-right
corner (`Rect2(Vector2(size.x - 58, 6), Vector2(50, 50))` — doesn't enlarge the panel):

```gdscript
func _draw_pattern_glyph(pattern: AoEPattern, rect: Rect2) -> void:
    var aoe_map := pattern.to_map()
    if aoe_map.is_empty():
        return
    # bounding box of all offsets -> cell size, clamped 3..8px
    # draw each cell colored via AoEPattern.zone_color(group.multiplier)
    # white outline on the (0,0) impact cell
```

Uses the same shared `zone_color()` palette as the world preview, so a player reading either view
sees the same orange/yellow tiers.

---

## §6 Bake script updates

`scripts/bake_resources.gd`:
- `_elemental_diamond()`/`_diamond_pattern()` updated to the new `make_diamond(core_radius,
  edge_radius)` signature (dropped the `falloff` param entirely — no longer meaningful).
- New core/edge radii: `diamond_r2`/`diamond_mine` → core 1 / edge 2; `diamond_r3` → core 1 /
  edge 3; `diamond_r4` → core 2 / edge 4.
- `ShotDefinition.strength` set explicitly per shot: basic/fire/electric shells + cluster +
  pull/spiral families = 3 (roughly matches each pattern's old ring-0 damage); bypass family = 10
  (heavy unit-hit blast). New `_family_strength(type_id)` helper for the four shot families.
- `Mine.strength = 4` lives directly on `world/mine.gd`'s own default rather than baked onto a
  `.tres`, since `Mine` is script-instantiated, not loaded from a resource the way shots/units are.

---

## §7 Files Changed

| File | Change |
|---|---|
| `data/shots/aoe_group.gd` | `damage: int` → `multiplier: float = 1.0` |
| `data/shots/aoe_pattern.gd` | `make_diamond(core_radius, edge_radius)`; drop `max_damage()`; add `zone_color()` |
| `data/shots/shot_definition.gd` | add `strength: int = 3` |
| `data/units/unit_definition.gd` | add `base_power: float = 1.0` |
| `units/unit.gd` | add `power: float = 1.0`, initialized from definition in `_ready()` |
| `world/mine.gd` | add `strength: int = 4` |
| `terrain/aoe_resolver.gd` | `resolve()` gains `strength` param; `_zone_damage()` helper |
| `projectile/projectile_manager.gd` | `Salvo.strength`, computed at fire time |
| `systems/combat_manager.gd` | `_on_mine_detonated` passes `mine.strength` |
| `systems/enemy_system.gd` | `fire_enemy()` call site passes `enemy` as `firing_unit` |
| `world/combat_scene.gd` | smoke-test `resolve()` calls updated; new `_m7_smoke()` |
| `ui/targeting_overlay.gd` | discrete zone-color fill instead of damage gradient |
| `ui/hud.gd` | `UnitInspector._draw_pattern_glyph()` |
| `scripts/bake_resources.gd` | new pattern/strength baking |
| `PROGRESS.md` | new dated entry |
| `milestone-7-plan.md` | this document |

---

## §8 Deviations & decisions made during execution

1. No deviations from the approved plan — all method signatures, hook points, and the file list
   were followed as written during plan mode.
2. The initial `_m7_smoke()` draft asserted `strength=10` on EnemyA's core voxel would deal
   exactly `-10`, but EnemyA only has 8 max HP, so the hit clamps at `-8`. Fixed by lowering the
   test's strength to `5` (well under any unit's HP) so the assertion reflects the zone-strength
   math itself rather than incidentally exercising the HP floor.
3. A `ui/hud.gd` edit initially mis-indented `_draw_pattern_glyph()` as a body statement nested
   inside `_draw()` instead of a sibling method — caught immediately by the headless smoke run
   (`Parse Error: Could not parse global class "HUD"`), fixed by dedenting it to class-member
   level.

---

## §9 Bake Workflow

Same as M3–M6:
```
godot --headless --import
godot --headless -s scripts/bake_resources.gd
godot --headless --import
```

---

## §10 Smoke Test Checklist

All items verified via `ARTILLERY_SMOKE=1 godot --headless` (`_m7_smoke()` in
`world/combat_scene.gd`):

```
[zone strength] a pattern with explicit core/edge groups resolves to the expected zone-scaled
                 damage for a given strength (strength=5 on the core voxel -> -5)
[unit power]     shot.strength * Unit.power scales the computed salvo strength proportionally
                 (without re-baking or touching the pattern)
[mine strength]  Mine.strength is fixed and independent of any unit's power
[zone_color]     AoEPattern.zone_color() returns distinct colors for multiplier 1.0 vs 0.5
```

Manual playtest (not done in this headless pass — recommended before shipping): fire each of the
4 shot families and confirm the world preview renders two visually distinct fill colors; open the
unit inspector and confirm the new glyph shows the active shot's pattern with orange core /
yellow edge cells and a marked impact cell.
