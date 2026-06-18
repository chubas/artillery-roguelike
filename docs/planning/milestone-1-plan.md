# Artillery Space — Milestone 1 Implementation Plan

*Companion to [terrain spec v2](artillery-space-terrain-spec-v2.md) and [general spec v2](artillery-space-general-spec-v2.md).*

This document is the build-order plan for the M1 terrain-destruction prototype. It locks the
open decisions, reconciles inconsistencies found in the spec, adapts the node architecture to the
chosen rendering approach, and breaks the work into phases that each end in something runnable.

---

## 0. Locked Decisions

| Topic | Decision | Source |
| :---- | :---- | :---- |
| Engine | Godot 4.6.1 stable (installed) | environment |
| `VOXEL_SIZE` | **16 px** | spec rec. |
| Map size | **300 × 100** voxels (4800 × 1600 px) | spec rec. |
| `CHUNK_SIZE` | **16** voxels | spec rec. |
| Destruction result | **VOID** (RUBBLE schema only) | spec rec. |
| Collapse | **Column-fall only** | spec rec. |
| `AOE_RADIUS` | **2** | spec rec. |
| `GRAVITY` / `BASE_PROJECTILE_SPEED` | start **980 / 600**, tune to feel | spec rec. |
| **Rendering** | **Custom `_draw()` per chunk node** (not TileMapLayer / MultiMesh) | this session |
| **Testing** | **Manual in-engine** validation only (no GUT) | this session |
| Constants access | A single `class_name Const` static script (`Const.VOXEL_SIZE`, `Const.world_to_voxel(...)`); no autoload needed | this session |
| Placeholder art | Colored rectangles drawn in `_draw()`; no PNGs for M1 | this session |
| **Firing input** | **Gunbound-style** (supersedes terrain spec §13.2 mouse aim): ↑/↓ adjusts angle (HUD readout + barrel indicator), Space hold-to-charge min→max power with auto-fire at max, release fires. Full simulated arc + predicted-impact AoE shown while charging, via a `Trajectory` util shared with the live projectile so preview = reality. | user decision 2026-06-12 |

---

## 1. Spec Reconciliation (decisions that fix real issues)

These were caught reading the spec; building as-written would produce bugs or surprises.

### 1.1 AoE damage falloff — RESOLVED to distance-based

The §8.2 table (dist 1 → 75%, 2 → 50%, 3 → 25%) and the §8.3 code
`1.0 - dist/(radius+1)` **disagree** for any radius ≠ 3. At the locked `R = 2` the code yields
100% / 67% / 33%, not the table's 100% / 75% / 50%.

**Decision:** use the table as the intended feel — falloff is a function of *absolute* Manhattan
distance, independent of radius:

```
multiplier = max(0.0, 1.0 - 0.25 * dist)   # 100% / 75% / 50% / 25% / 0% at dist 0..4
```

This is simpler, matches the table, and keeps a tile's damage stable when only the radius changes.
Final applied damage is still `max(1, int(base_damage * multiplier))` for any tile inside the radius.
With `BASE_DAMAGE = 3`: dist0→3 (one-shots a standard 3-HP tile), dist1→2, dist2→1.

### 1.2 Concave-corner rule — DEFER to a phase-9 stretch goal

§9.4 adds corner-origin double-hit geometry. It is genuinely nice but is the most fiddly part of
collision and not required by any acceptance criterion. Build the plain face-contact path first
(§9.3); only add the concave-corner branch if time remains. The `CORNER_THRESHOLD` constant is
defined now so adding it later is local.

### 1.3 Collapse is animation-free in M1

The spec's `_fall_tile` teleports a tile to its rest row in one frame (no per-frame falling
animation). That matches the acceptance criterion ("unsupported tiles fall"). We keep it
instantaneous for M1; a `CollapseSimulator` that animates descent is post-M1. No separate
`CollapseSimulator` node is needed — column-fall lives inside `TerrainManager`.

### 1.4 Minor code-hygiene fixes carried into the scaffold

- `Tile.init()` returns `self` for fluent construction — keep, but call it `setup()` to avoid any
  confusion with object lifecycle. (`init` is not reserved in GDScript, but `setup` reads clearer.)
- Out-of-bounds reads return `null` / `false` everywhere (already in spec) — projectiles rely on
  the explicit bounds check in `_physics_process`, not on collision, to despawn.

---

## 2. Adapted Node Architecture

The spec's `ChunkRenderer` + `CollapseSimulator` + stateless-`AoEResolver`-as-Node are folded into
a structure that fits custom `_draw()` rendering:

```text
World                    (Node2D — scene root, world.gd)
 ├─ TerrainManager       (Node    — owns _grid, all tile logic, generation, collapse, signals)
 ├─ TerrainRenderer      (Node2D  — owns a Chunk child per CHUNK_SIZE region)
 │    └─ Chunk × N       (Node2D  — _draw() paints its voxels + crack overlays; redraws when dirty)
 ├─ ProjectileManager    (Node2D  — spawns/tracks Projectile instances)
 │    └─ Projectile × N  (Node2D  — arc physics + DDA collision; calls AoEResolver on impact)
 ├─ UnitLayer            (Node2D  — draws the one static PlayerUnit placeholder box)
 ├─ TargetingUI          (CanvasLayer — AoE preview overlay, hitbox highlight, aim line)
 └─ Camera2D             (pan/scroll, clamped to map bounds; follows projectile in flight)

AoEResolver              (class_name, all-static — pure function, no node)
LoS                      (class_name, all-static — DDA raycast, firing-validation only)
Const                    (class_name, all-static — constants + coordinate helpers)
Tile                     (class_name — per-voxel data object)
```

**Invariant:** `TerrainManager` is the only writer of `_grid`. Everything else reads via its public
API or reacts to its signals (`tile_damaged`, `tile_destroyed`, `tile_changed`, `projectile_impact`,
`aoe_resolved`). `TerrainRenderer` maps `tile_changed(col,row)` → mark the owning `Chunk` dirty →
that chunk calls `queue_redraw()` next frame.

---

## 3. Build Phases

Each phase ends in a runnable state you can eyeball. Phases map directly onto the 12 deliverables
in terrain spec §1.1.

| Phase | Goal | Ends when you can see… | Deliverables |
| :---- | :---- | :---- | :---- |
| **0. Scaffold** | Project, constants, node tree, stubs compile and run | Empty window, no errors | — |
| **1. Grid + data** | `Tile`, flat `_grid`, `TerrainManager` access API | Console dump of grid stats | 2 |
| **2. Generation** | 6-pass procedural map (fixed seed) | Grid populated (verify via logs) | 3 |
| **3. Rendering** | `Chunk._draw()` of solid voxels + variants; camera scroll | The terrain on screen, scrollable | 1, 2 |
| **4. Unit + camera** | Static `PlayerUnit` box on spawn platform | Unit rectangle on the platform | 4 |
| **5. Firing** | Click-drag aim line, launch `Projectile`, gravity arc | A dot flying in an arc | 5, 6 |
| **6. Collision** | DDA face-contact collision, projectile stops on terrain | Projectile halts at terrain face | 7 |
| **7. Destruction** | `damage_tile` → AoE diamond → VOID, crack states, falloff | Diamond hole punched; cracked tiles | 8, 9 |
| **8. Collapse** | Column-fall after destruction | Overhangs drop after a hit | 10 |
| **9. Targeting UI** | Hover/targeting hitbox highlight + live AoE preview overlay | Hover outline; red diamond at cursor | 11, 12 |
| **9b. (stretch)** | Concave-corner double-hit (§1.2) | Corner hits damage both tiles | — |

### Per-phase acceptance checks (manual)

- **P2:** with `NOISE_SEED = 12345`, regenerating twice produces an identical grid (log a checksum
  of solid-tile count + a hash of the first row's surface heights).
- **P3:** scroll covers the full 4800 px width; reinforced tiles and variants are visually
  distinguishable; no gaps/seams at chunk boundaries.
- **P6:** fire at a wall point-blank and at a shallow grazing angle — collision registers on the
  approached face, never one tile early/late; no false positives over empty caves.
- **P7:** a direct hit on a 3-HP tile destroys it; an `R=2` blast leaves a diamond hole; tiles at
  dist 2 drop to 1 HP and show heavy cracks; reinforced (6-HP) tiles survive a single dist-2 hit.
- **P8:** blast out the base of a column/overhang → the tiles above fall to rest, no floaters in the
  common case (full island detection is post-M1, so a cave roof anchored only sideways may float —
  that's expected).
- **P9:** AoE preview diamond tracks the cursor every frame and clears on fire / exit targeting.

---

## 4. Tuning Pass (Phase 5–7, the "feel" gate)

Per spec §9.6, establish a **reference shot** before tuning anything else: fire at 45°, hold
`SPEED = 600`, and adjust `GRAVITY` until the impact lands a satisfying ~15–25 tiles away with a
readable arc apex. Lock that `GRAVITY/SPEED` pair, *then* sanity-check steep and flat angles. Record
the chosen values back into this table:

| Constant | Start | Final (fill in) |
| :---- | :---- | :---- |
| `GRAVITY` | 980 | |
| `BASE_PROJECTILE_SPEED` | 600 | |
| `AOE_RADIUS` | 2 | |
| `BASE_DAMAGE` | 3 | **4** — at 3, falloff means only the center tile dies (no visible crater); at 4 the dist-1 ring dies too (plus-shaped crater), dist-2 cracks, reinforced tiles take two hits |

---

## 5. File Map (created by the scaffold step)

```text
project.godot                 # Godot 4.6 config; main scene = world/world.tscn
constants.gd                  # class_name Const — all constants + coord helpers
terrain/
  tile.gd                     # class_name Tile — full (small, spec-complete)
  terrain_manager.gd          # grid storage + signals + API; logic stubbed by phase
  aoe_resolver.gd             # class_name AoEResolver — static resolve()/falloff stub
  los.gd                      # class_name LoS — static has_los() stub
rendering/
  terrain_renderer.gd         # builds Chunk children, routes tile_changed → dirty
  chunk.gd                    # Node2D, _draw() stub
projectile/
  projectile.gd               # arc physics + collision stub
  projectile_manager.gd       # spawn/track stub
units/
  player_unit.gd              # static placeholder box
ui/
  targeting_ui.gd             # CanvasLayer; AoE preview + hitbox overlay stub
world/
  world.gd                    # wires children together
  world.tscn                  # the node tree above
milestone-1-plan.md           # this file
```

Stubs compile and run (Phase 0). Each later phase fills in the marked `# TODO(Pn)` bodies.

---

## 6. Out of Scope (unchanged from spec §1.2 / §15)

Enemies, AI, movement, turns, multiple unit types, roguelite systems, audio, RUBBLE/LIQUID behavior,
full island collapse, wind, scrap, elemental effects, firing-power variation, preview toggle. The
schema and signals are laid down so these slot in later without a rewrite.
