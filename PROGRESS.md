# Artillery Space — Progress Log

Chronological record of what's been built and changed. Newest first.

## How the docs fit together

| Doc | Purpose |
| :-- | :-- |
| **PROGRESS.md** (this file) | Chronological log of what shipped + small fixes. Start here to see *what changed and when*. |
| `milestone-N-plan.md` | Per-milestone design decisions, locked choices, and spec deviations with rationale. The *why*. |
| `artillery-space-*-spec.md` / `.md` | Source design specs (the brief we implement against). |

**Working agreement for picking up later:** read the top of this file for current state, then the
relevant `milestone-N-plan.md` for design context before touching a system. When you finish a
chunk of work, add an entry here (and update the milestone plan if a decision changed).

## Current state (2026-06-15)

- **Milestones complete:** M1 (terrain), M2 (combat loop), M3 (elements/status engine),
  M4 (shot varieties & 4-unit squad), M5 (card system: shield + direct damage, reinforcements).
- **Main scene:** `world/combat_scene.tscn`. Map is 120×100 voxels.
- **Verify:** `ARTILLERY_SMOKE=1 godot --headless` runs the M3 §10 + M4 §12 + M5 §10 checklists
  headless (all pass).
- **Re-bake resources** after changing any generator in `scripts/bake_resources.gd`:
  `godot --headless --import` → `godot --headless -s scripts/bake_resources.gd` → `godot --headless --import`.
- **Known orphan:** `world/world.tscn` references a deleted `world/world.gd` and logs a harmless
  load error on import. Left in place intentionally.

---

## 2026-06-15 — Milestone 5: Card system & reinforcement waves

First slice of the card-engine vision, scoped entirely inside the combat stage (no map/shops/
deck progression yet). Full design + deviations in [milestone-5-plan.md](milestone-5-plan.md).

- **Shield mitigation layer.** `Unit.shield`/`max_shield`; `take_damage()` now drains shield
  before HP (armor would slot in above shield later — seam comment marks the spot). Gated by
  new `Features.shields_enabled` kill switch. A thin shield bar draws above the HP bar.
- **Two cards**, baked as `CardDefinition` resources: `shield_buff` (ally, +4 shield, 2 AP) and
  `direct_strike` (enemy, 3 dmg routed through shield like any other hit, 3 AP). Both spend from
  the shared `actions_left` pool and are captured by the existing turn-wide checkpoint/undo —
  same as firing, a card's own spend isn't itself undone, only moves made after it are.
- **Targeting flow.** `Q`/`E` or HUD chips arm a card; click a valid ally/enemy to apply it
  (green/red highlight on valid targets), `Esc` cancels without spending AP. Doesn't require an
  active unit or end any unit's turn.
- **Reinforcements.** A hardcoded round → unit schedule (round 2 → EnemyC, round 5 → EnemyD)
  spawns directly on the surface row with no collision-avoidance (enemies don't move, so the
  landing space is assumed clear). A world-space guide line + countdown number telegraphs each
  incoming drop before it lands.
- **Feature flag:** `Features.card_deck_enabled` (previously an unused M3-era stub) now gates
  the whole card UI/input path and is flipped on.

---

## 2026-06-14 — Milestone 4: Shot varieties & unit roster

Four distinct shot behaviors, each its own player unit. Full design + deviations in
[milestone-4-plan.md](milestone-4-plan.md).

- **Salvo system.** `ProjectileManager` rebuilt around a `Salvo` (one logical shot = many
  bodies). Bodies that hit terrain **pause** (not freed) and report an impact; the manager
  drains impacts in collision order — `(physics_frame, salvo index)` — re-checking each voxel
  first, so a pellet whose blocker an earlier impact already destroyed **resumes** and flies on.
  One settle beat per salvo, then `shot_resolved`. `is_busy()` = "any salvo alive."
- **Cluster** (`Cluster` unit): 5 pellets fanned 1° apart, R3 diamond each.
- **Bypass / drill** (`Drill` unit): ignores terrain, deals 1 dmg per unique trail voxel,
  stops on an opposing unit for a heavy R4 blast. Unit overlap checked in the manager.
- **Gravity pull** (`Magnet` unit): post-impact `GravityPullResolver` drags units toward the
  blast — inner band (≤4 vox) 2 steps, outer (≤8) 1 step, closest-first, blocked-stays-put.
- **Spiral** (`Spiral` unit): main projectile + 2 `SpiralSatellite` arms oscillating
  perpendicular to the heading; arms share the salvo/impact queue.
- **UnitMovement** static module extracted from `CombatManager` so the pull shot shoves units
  with **identical** climb/fall/collision rules as walking.
- **Power memory.** Each unit remembers its last charge fraction; HUD draws a triangle marker
  on the charge bar (angle already persisted). Action budget raised to **10 AP**; fire = 2 AP,
  electric = 3 AP (unaffordable shots already grey out from M3).
- **Content (baked):** R3/R4 diamonds (+ elemental variants); 12 shots (4 families × phys/fire/
  electric); 4 player unit `.tres`.
- **Key deviations:** spiral arms don't outlive the main projectile (despawn if it resolves
  first); pull direction is fixed at the unit's initial side (pull *by* N voxels, may overshoot
  the blast rather than stop at column alignment). See plan §10.

## 2026-06-14 — Shot resolution routine

- **Shot resolution pipeline.** `ProjectileManager._on_impact` is now an ordered, async
  *resolution routine*: (1) AoE damage, (2) explosion FX, (3) [pluggable seam for future
  consequences — death animations, terrain collapse, knockback], (4) a settle beat
  (`Const.SHOT_RESOLVE_DELAY`, 0.45s). It emits `shot_resolved(is_enemy)` only when the whole
  routine finishes, and `is_busy()` stays true throughout.
- **Next-unit focus is deferred to resolution.** `_fire_active` no longer auto-advances; the
  camera follows the projectile, lingers on the impact through the settle beat, then
  `CombatManager._on_shot_resolved` focuses the next available unit. Enemy sequencing now waits on
  `is_busy()` (full resolution), not just `has_active()` (flight only).
  Files: `projectile/projectile_manager.gd`, `systems/combat_manager.gd`, `constants.gd`.

## 2026-06-14 — Post-M3 usability & terrain tweaks

- **Camera focus on selection.** Selecting an ally (Tab cycle, click, turn-start first-available,
  or post-fire auto-advance) now eases the camera to that unit. Implemented as a one-shot pan that
  releases once centered, so WASD free-panning isn't fought. Only allied units are selectable/
  focusable (enemies were never click-selectable). `CombatManager.unit_focused` signal →
  `CombatScene._on_unit_focused`. After a unit fires, the camera follows the projectile and only
  pans to the next unit once the shot has **resolved** (the projectile-follow branch owns the
  camera while a shot is live, so the deferred focus lands afterward).
  Files: `systems/combat_manager.gd`, `world/combat_scene.gd`.
- **Terrain is fixed (no collapse).** Added `Tile.collapsible` (default **false**). The column-fall
  pass in `TerrainManager._collapse_column` now skips non-collapsible tiles, so nothing falls when
  the tile beneath it is destroyed. Collapse *rules* will opt specific tiles in later. Units still
  settle into craters (separate from terrain collapse).
  Files: `terrain/tile.gd`, `terrain/terrain_manager.gd`.
- Added this `PROGRESS.md`.

## (earlier 2026-06-14) — Milestone 3: Elements, Status Effects & Combat Engine

Engine for emergent combat. Full design + deviations in [milestone-3-plan.md](milestone-3-plan.md).

- **Architecture:** `EventBus` + `Features` autoloads. Gameplay events routed through EventBus;
  high-frequency per-tile render signal kept local.
- **Elements:** `ElementDef` (Fire, Electric); `element` field on `AoEGroup`; affinity table +
  structural `tags` on `UnitDefinition`. `AoEResolver` applies affinity damage + statuses, gated
  by `Features.elements_enabled`.
- **Unit statuses:** `StatusEffectDef`/`StatusInstance`/`UnitStatusSystem` — Burn, Shock; cap-3
  refresh; Shock cuts the shared action pool. Stack badges on units.
- **Tile statuses:** `TileStatusDef`/`TileStatusInstance`/`TileStatusSystem` — Burning (spreads to
  exposed FLAMMABLE), Electrified (chains through CONDUCTIVE). Tints on chunks.
- **Turn loop** restructured to spec §6 resolution order (round → tile tick → player statuses →
  actions → enemy statuses → fire).
- **Shot selection:** `available_shots`/`selected_shot`, keys `1/2/3` + HUD chips, action-cost
  spend (elemental = 1 AP, basic = 0). **Player full-charge power ×2.5** (`Const.PLAYER_POWER_MULT`).
- **Content (baked):** fire/electric shells + patterns; organic (weak fire) / mechanical (weak
  electric) enemies; updated player loadouts.
- **Key deviation:** dropped the spec's fire↔burning circular resource reference (Godot's `.tres`
  loader can't resolve it) — `TileStatusDef` stores `applied_status` instead; tile tick damage is
  physical. See plan for full list.

## (earlier 2026-06-14) — Post-M2 bug fixes

Six fixes from manual playtest (`systems/combat_manager.gd`, `ui/hud.gd`, bake/resources):

1. End-turn alert only reddens when all living units have **fired**, not at 0 actions.
2. Enemies fire one at a time, each shot fully resolving before the next (drain moved inside loop).
3. HUD buttons `focus_mode = NONE` — Tab no longer cycles button focus (it cycles units).
4. Same fix stops Space from triggering a focused button while firing.
5. Removed the per-unit move cap (units now move as far as action points allow; `move_range = 99`).
6. Undo is a **turn-wide checkpoint** — restores all unfired units to their positions since the
   last fire, refunding all actions, rather than only the last unit's last move.

## Milestone 2: Combat loop prototype

Full design in [milestone-2-plan.md](milestone-2-plan.md). 2 players vs 2 enemies, HP, shared
5-action turn bar, ←/→ movement with climb/fall/collision, undo, Gunbound ↑/↓ angle + Space charge,
enemy parabolic IK firing, win/loss, `AoEPattern` resource system, surface-snap spawning.

## Milestone 1: Destructible voxel terrain

Full design in [milestone-1-plan.md](milestone-1-plan.md). 300→120-wide voxel grid, chunked dirty
`_draw` rendering, ballistic projectiles with shared `Trajectory` (preview = reality), six-pass
procedural generation (fixed seed, reproducible), AoE destruction + (then-)column collapse, camera
pan/zoom.
