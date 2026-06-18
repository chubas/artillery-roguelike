# Milestone 16 — Dig vs Unit Damage Separation + Battle Rewards

## What was built

1. **Dig vs unit damage** — decoupled terrain destruction from unit-damage scaling (run-design §4.1).
2. **Battle rewards** — pre-run and post-combat reward screens growing squad/deck/artifacts from pools.

Full technical spec for the dig channel below; reward flow lives in `world/run_controller.gd` and
`ui/reward_screen.gd`.

---

## Overview (dig channel)

Per `artillery-space-run-design.md` §4.1, terrain destruction must decouple from unit damage so
late-game attack scaling does not dissolve the battlefield. Today `AoEResolver` applies one
`strength × zone_multiplier` value to **both** `terrain.damage_tile()` and unit hits — a high-attack
drill blast chips as much rock as it hurts enemies.

This milestone splits each impact into two channels on the **same projectile / same salvo**:

| Channel | Spatial extent | Magnitude |
|---|---|---|
| **Unit damage** | `ShotDefinition.aoe_pattern` (unchanged) | `unit.attack × shot.strength_mult × power` × per-zone `AoEGroup.multiplier` |
| **Dig damage** | `ShotDefinition.dig_pattern` (new; defaults to damage footprint) | Flat `unit.dig × shot.dig_mult` — **no zone tiers** |

There is still **one projectile body** and one impact resolution — not two projectiles, not two
collision passes. The resolver applies both channels when the salvo detonates.

**Bypass / drill** (`bypass_terrain = true`) is explicitly **outside** the dig system: it signals
“goes through terrain” via the existing centre-voxel trail (1 HP per unique voxel along the path)
and has **no dig strength and no dig footprint** on the unit-hit blast. The blast still applies
normal **unit-damage** AoE to enemies/deployables.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **One projectile, two scalar properties** at fire time: `Salvo.strength` (unit damage, exists) and `Salvo.dig_strength` (terrain only, new). No second projectile body. |
| 2 | **Unit-damage hitbox is unchanged** — same `aoe_pattern`, same zone multipliers, same dominant-hit-per-unit rule (M7). |
| 3 | **Dig hitbox is a separate `AoEPattern`** (`dig_pattern`). For all existing shots in M16, `dig_pattern` is baked to the **same offset union** as `aoe_pattern` (the full blast footprint). Future demolition content can author a wider/narrower dig pattern without touching unit damage. |
| 4 | **Dig has a single flat strength** across every voxel in `dig_pattern` — no `AoEGroup.multiplier` scaling for terrain. Zone tiers apply only to unit damage. |
| 5 | **Dig strength formula mirrors attack but without `power`:** `max(0, round(unit.dig × shot.dig_mult) + dig_modifier)` — `dig_modifier` on `Unit` is a seam (default 0); no artifact hook in M16 (`modify_projectile_strength` stays unit-damage-only). |
| 6 | **Bypass shots opt out entirely:** when `shot.bypass_terrain`, `dig_strength` is not computed, `dig_pattern` is ignored on impact, and the targeting preview draws **no dig overlay**. Trail terrain chips stay at the existing hardcoded **1** per unique centre voxel (`projectile.gd`) — not wired through `dig_strength`. |
| 7 | **Mines** gain a separate `dig: int` (default equals current blast `strength` for M16 parity on terrain; unit damage still uses `strength`). |
| 8 | **Visual (targeting preview only in M16):** on each dig footprint voxel, draw the existing unit-damage zone fill first, then a **light opaque overlay** plus a **dig outline** on top. No new HUD stat icon yet — inspector dig readout is deferred. |
| 9 | **Minimum dig:** `maxi(1, dig_strength)` when dig applies (same convention as unit damage minimum 1). Skipped entirely for bypass. |

---

## Dig strength model

`projectile/projectile_manager.gd` `fire()` — alongside existing `salvo.strength`:

```gdscript
var dig : int = firing_unit.dig if firing_unit != null else 1
var dig_mod : int = firing_unit.dig_modifier if firing_unit != null else 0
if shot.bypass_terrain:
    salvo.dig_strength = 0          # sentinel: resolver skips terrain dig channel
else:
    salvo.dig_strength = maxi(0, roundi(dig * shot.dig_mult) + dig_mod)
```

- `data/units/unit_definition.gd`: `@export var dig : int = 1`
- `units/unit.gd`: `var dig : int` from definition in `_ready()`; `var dig_modifier : int = 0`
  (symmetry with `attack_modifier`; unused in M16 content)
- `data/shots/shot_definition.gd`: `@export var dig_mult : float = 1.0`
- Enemies: baked `dig` on `UnitDefinition` same as players (default 1) unless a specific enemy
  needs terrain interaction later.

**Balance intent for M16 bake:** keep **unit damage identical** to pre-M16 (`attack` / `strength_mult`
unchanged). Terrain erosion becomes **weaker on edge voxels** (flat dig vs old `strength × 0.5`) and
**decoupled from attack scaling** — the main gameplay shift. Tune `unit.dig` upward in a later
pass if stages feel too static.

---

## Dig area model

`data/shots/shot_definition.gd`:

```gdscript
## Terrain-only blast footprint. null → use every offset in aoe_pattern (flat dig strength).
## Ignored when bypass_terrain (drill uses trail, not dig AoE).
@export var dig_pattern : AoEPattern = null
```

**Resolver rule:** effective dig offsets = `dig_pattern.to_map()` if set, else `aoe_pattern.to_map()`
keys only (footprint union — one dig strength per voxel regardless of which damage zone covered it).

Dig may target voxels with **no unit damage** (future content): extra offsets in `dig_pattern` only
get `terrain.damage_tile(dig_strength)` and are included in the dig preview overlay.

---

## Resolver & combat pipeline

`terrain/aoe_resolver.gd` — `resolve()` signature gains dig params:

```gdscript
static func resolve(terrain: TerrainManager, units: Array, origin: Vector2i,
        pattern: AoEPattern, strength: int, is_enemy: bool,
        deployables: Array = [],
        dig_strength: int = 0, dig_pattern: AoEPattern = null) -> Array
```

**Per-voxel loop (unit damage — unchanged logic):** for each offset in `pattern.to_map()`:
- `zone_dmg = _zone_damage(strength, group.multiplier)` → units / deployables (dominant hit)
- **Do not** call `terrain.damage_tile` here anymore.

**Dig pass (new):** if `dig_strength > 0`:
- Build dig offset set from `dig_pattern` or `pattern` footprint (see above).
- For each dig offset: `terrain.damage_tile(target.x, target.y, maxi(1, dig_strength))`.
- Tile statuses from elements still come from the **unit-damage** loop only (unchanged).

**Call sites:**
- `projectile/projectile_manager.gd` `_resolve_impact()` — pass `salvo.dig_strength` and
  `salvo.shot.dig_pattern` (or `salvo.pattern` for null dig_pattern footprint).
- `systems/combat_manager.gd` `_on_mine_detonated()` — pass `mine.dig` and `mine.dig_pattern`
  (null → explosion pattern footprint).
- `world/combat_scene.gd` — update direct `resolve()` smoke calls; add `_m16_smoke()`.

`Salvo` gains `dig_strength: int = 0`.

---

## Bypass / drill exception

| Behaviour | Unit damage | Terrain |
|---|---|---|
| Flight trail (`bypass_mode`) | — | 1 HP per unique centre voxel (unchanged; **not** `dig_strength`) |
| Impact blast on unit | `aoe_pattern` + `strength` | **No dig pass** (`dig_strength == 0`) |
| Impact if leaves map | — | — |

Rationale: dig footprint on a drill would contradict “this shot bypasses terrain.” The trail is the
terrain interaction; the burst is for enemies.

---

## Visual indicator — targeting overlay

`ui/targeting_overlay.gd` — extend `_draw_pattern_footprint()` (and cluster/bypass call sites as
needed):

1. Draw **unit-damage** fill exactly as today (`AoEPattern.zone_color`, unit-voxel orange highlight).
2. If the active shot is **not** bypass and has a dig footprint, for each dig offset:
   - `draw_rect(rect, Color(1.0, 0.95, 0.75, 0.22))` — warm light overlay on top of the zone fill.
   - `draw_rect(rect, Color(0.85, 0.70, 0.35, 0.85), false, 1.5)` — dig outline (earth/gold).

**Bypass preview:** arc dots + unit-hit blast footprint with **step 1 only** (no dig overlay).

**Cluster:** each pellet footprint gets the dig overlay independently (same rules).

Constants live as locals in `_draw_pattern_footprint` for now; extract to `AoEPattern.dig_overlay_color()`
only if a third consumer appears.

**Out of scope M16:** unit-card dig glyph, `UnitInspector` dig stat, in-world dig tint on fired
shots (preview-only is enough to learn the mechanic).

---

## Bake script & balance defaults

`scripts/bake_resources.gd`:

- `_save_player_unit(...)`: add `dig` param (default **1** for cluster/pull/spiral; bypass unit
  still `attack = 10`, `dig = 1` — only matters if a non-bypass shot is added to drill later).
- `_family_shots()`: set `dig_mult = 1.0` on all families; for each shot, set
  `dig_pattern = s.aoe_pattern` (same `.tres` reference is fine — shared footprint).
- Enemy units: `dig = 1`.
- Mines are script-instantiated: add `@export var dig : int = 4` on `world/mine.gd` (match
  `strength` for parity).

Re-bake workflow unchanged (§9 below).

---

## Files changed

| File | Change |
|---|---|
| `data/units/unit_definition.gd` | `@export var dig : int = 1` |
| `units/unit.gd` | `dig`, `dig_modifier` runtime fields |
| `data/shots/shot_definition.gd` | `dig_mult`, `dig_pattern` |
| `terrain/aoe_resolver.gd` | Split terrain dig pass; new params |
| `projectile/projectile_manager.gd` | `Salvo.dig_strength`; compute at fire; pass to resolver |
| `world/mine.gd` | `dig: int` |
| `systems/combat_manager.gd` | Mine detonation passes dig |
| `ui/targeting_overlay.gd` | Dig overlay + outline on preview footprint |
| `scripts/bake_resources.gd` | Bake `dig`, `dig_mult`, `dig_pattern` |
| `world/combat_scene.gd` | Update `resolve()` call sites; `_m16_smoke()` |
| `PROGRESS.md` | Dated entry when implemented |
| `milestone-16-plan.md` | This document |

---

## Verification

### Bake

```
godot --headless --import
godot --headless -s scripts/bake_resources.gd
godot --headless --import
```

### `_m16_smoke()` (new — `world/combat_scene.gd`)

Headless spot-checks after existing M4–M15 chain:

```
[dig decoupled]   resolve(strength=10, dig=1) on a 3-HP tile: terrain takes 1 per dig voxel,
                  not 10 — tile survives more hits than pre-M16 at same unit attack
[dig footprint]   dig_pattern null uses full aoe_pattern offset count
[bypass skip]     bypass shot: salvo.dig_strength == 0; impact resolve does not reduce tile HP
                  via dig pass (trail path not exercised in this smoke block)
[mine dig]        mine detonation passes mine.dig to resolver
[preview seam]    TargetingOverlay has dig overlay path (compile-time; no pixel assert headless)
```

### Regression

`ARTILLERY_SMOKE=1 godot --headless` — all prior milestone headers still pass; 0 ERROR lines.

### Manual

- Charge a cluster shell: blast preview shows zone colors **plus** gold-outlined dig overlay on the
  same footprint.
- Charge drill/bypass: **no** dig overlay on the unit-hit blast; trail behaviour unchanged.
- Fire a high-attack unit at terrain edge: crater forms slower than before (flat dig vs scaled edge).

---

## Deviations & open tuning (post-implementation)

| Item | Notes |
|---|---|
| Default `unit.dig = 1` | May feel too weak after playtest — bump to 2 globally or per-faction in a tune pass |
| Trail damage = 1 | Intentionally not `dig_strength`; renaming to `trail_chip` is cosmetic |
| Artifact dig hooks | Deferred — `modify_dig` can mirror `modify_projectile_strength` when needed |
| `dig_pattern` ≠ `aoe_pattern` | Schema ready; no M16 content uses a mismatched dig area yet |

---

## Seams for later

- **Demolition build content:** high `dig_mult` or wider `dig_pattern` without raising unit damage.
- **Terrain durability axis** (run-design §4.1): tile-type dig resistance (`Tile.dig_resist`) —
  dig_strength vs durability, not vs HP directly.
- **HUD / inspector:** dig stat chip next to attack (M10 icon pattern); optional dig glyph on unit
  card.
- **Keywords / DRILLING flag:** bypass remains `bypass_terrain`; a future non-bypass “high dig” shell
  uses `dig_mult` only.
