# Artillery Space — Terrain Generation
**Design & Technical Specification · v0.1**

> Defines the profile-driven, two-pass terrain generation system: what strategic constructs must be producible, how they are placed, how difficulty scales across acts, and the authoring tools needed to iterate on them. Builds on the existing noise-based generator (M1/M13) without replacing it — adds a deterministic skeletal pass in front of the existing noise pass.

---

## 1. Design Principle: One Terrain Story Per Stage

Every stage has exactly one spatial problem — a "terrain story" — that the player must read and respond to. Features can be stacked in late-game stages, but each feature should contribute a sentence to the same story, not a different story.

Examples of coherent terrain stories:
- "The enemy holds the high ground — you need arc mastery or demolition."
- "The approach is underground — you need drilling or burrowing."
- "A lava pit separates the sides — mobility or arc mastery or flood wins, low-ground stalling loses."

A stage with three features that each demand a different terrain relationship has no story — it rewards ignoring terrain entirely. This is the most common failure mode of procedural terrain and the one this spec is designed to prevent.

**Content rule for profile authoring:** before writing a profile definition, state the terrain story in one sentence. If you can't, the profile needs to be simplified.

---

## 2. The Two-Pass Generation Model

Generation always runs in exactly two passes, in this order. Pass 1 runs first and its output is never overwritten by pass 2.

### Pass 1 — Skeletal features (deterministic, profile-driven)

Places the strategic geometry of the stage: elevated platforms, bunkers, caves, pits, crystal deposits. Feature positions are determined by **slot assignment** (§4), not by noise. The seed governs within-range parameter variation (exact height, width, depth within a specified range) but not whether or where a feature appears. A "ridge stage" always has a ridge; it just varies in exact size.

Feature tiles are placed with their final durability values assigned directly (§6). Indestructible tiles use `TileFlags.INDESTRUCTIBLE`; high-durability fill uses explicit HP values from the profile.

### Pass 2 — Surface noise (existing generator, constrained amplitude)

The existing FastNoiseLite Simplex pass runs over all columns that pass 1 did not claim. Amplitude is clamped to a maximum value from the profile (`noise_max_amplitude`), preventing noise hills from merging with placed features or accidentally filling in placed voids. The spawn platform column range is always excluded from noise variation (already established behavior from M1).

---

## 3. Map Width Scaling

Map width scales with act, not fixed at 120 voxels for all stages. The current 120×100 map is appropriate for act 1. Late-game stages should feel significantly larger.

| Act | Map width (voxels) | Notes |
|---|---|---|
| 1 | 100–130 | Narrow; few features; fast fights |
| 2 | 140–180 | Mid-size; 2 features common |
| 3 | 180–240 | Wide; 3 features + background; adventure feel |
| Boss stages | Fixed per boss | Hand-tuned width per boss design |

Map height stays at 100 voxels across all acts. Vertical scaling is expressed through feature height and underground depth, not by making the map taller.

---

## 4. Slot System

The horizontal map is divided into three **feature slots** plus a **background layer**. A profile declares which feature (if any) occupies each slot.

```
[spawn_platform] [LEFT SLOT] [CENTER SLOT] [RIGHT SLOT]
```

Slot positions are expressed as fractions of map width, resolved to voxel columns at generation time:

| Slot | Approximate center | Width budget |
|---|---|---|
| Left | 20–30% of map width | ~25% of map width |
| Center | 45–55% of map width | ~30% of map width |
| Right | 70–80% of map width | ~25% of map width |
| Background | Full map | Any depth, avoids slot footprints |

The spawn platform always occupies the leftmost columns (fixed, never varies). Enemy initial placement is biased toward the right slot or center-right, determined per profile.

**Slot rules:**
- A slot may be empty (no feature placed; noise fills in).
- A slot may hold at most one primary feature.
- Background features (caves, crystal deposits) occupy depth bands that avoid slot footprint columns unless specifically designed to pass beneath them (e.g. a cave tunnel passing under a ridge).

---

## 5. Natural Constructs Catalogue

Each construct entry defines: what strategic problem it poses, what tile composition it uses, and its generation parameters.

### 5.1 Open field
**Terrain story:** none (reference state).
**Tile composition:** noise-generated surface, all normal-durability SOLID.
**Parameters:** none beyond noise amplitude.
**Act range:** 1–2 (as full stage), 3 (as partial slot in multi-feature stages).

### 5.2 Ridge / elevated platform
**Terrain story:** "the enemy holds the high ground."
**Tile composition:** indestructible base (bottom 30% of feature height), normal-durability carveable fill (top 70%).
**Parameters:** `height_range: [8, 18]`, `width_range: [20, 40]`, `slope_edges: bool`.
**Strategic role:** forces Go Over or Remove terrain relationship. Primary non-flat feature for act 1.
**Generation:** rectangular block placed at slot center column, raised from the terrain surface by `height` voxels. Edge columns optionally slope (staircase of 1-voxel steps) to allow climbing at cost.

### 5.3 Bunker / fortification
**Terrain story:** "the enemy is inside a protected structure."
**Tile composition:** reinforced outer shell (2–3 voxels thick, high HP), normal-durability interior fill, 1–2 aperture gaps in the facing wall.
**Parameters:** `width_range: [12, 24]`, `height_range: [8, 14]`, `wall_hp: [8, 12]`, `aperture_count: [1, 2]`.
**Strategic role:** forces Go Through (drilling), Go Around (precision), or Remove (sustained demolition). Anti-synergy with flooding, arc mastery. Primary feature for Act 1 boss.
**Generation:** hollow rectangular shell at surface level. Interior enemies placed at generation time by StageDescriptor.

### 5.4 Cave / tunnel system
**Terrain story:** "there is an underground path."
**Tile composition:** carved void through solid terrain mass. Ceiling and floor are normal-durability. Passage width minimum 4 voxels, height minimum 3 voxels (unit passage clearance).
**Parameters:** `passage_count: [1, 3]`, `depth_range: [20, 60]`, `connects_to_surface: bool`.
**Strategic role:** rewards drilling/burrowing shots; enables below-ground unit paths if mobility allows. Background feature; does not occupy a surface slot.
**Generation:** carve connected ellipses or spline paths at a depth band. If `connects_to_surface`, carve a narrow vertical shaft (2 voxels wide) from passage to surface. Shaft is tight enough to require deliberate traversal.

### 5.5 Underground chamber
**Terrain story:** "the enemy controls a hidden arena."
**Tile composition:** large carved void with narrow entry shafts. Chamber walls are normal-durability; shaft walls are reinforced.
**Parameters:** `chamber_width: [30, 50]`, `chamber_height: [20, 35]`, `shaft_width: 2–3`, `shaft_count: [1, 2]`.
**Strategic role:** rewards excavation and burrowing approach. Natural habitat for boss-type enemies. Acts as a mid-right slot feature for hive-style encounters.
**Generation:** large ellipse carve at depth 40–70 voxels. Entry shafts carved from surface to chamber ceiling, reinforced walls to discourage easy widening.

### 5.6 Natural bridge / arch
**Terrain story:** "there is a chokepoint that can be collapsed."
**Tile composition:** span tiles explicitly tagged COLLAPSIBLE, normal durability. Supporting columns are indestructible.
**Parameters:** `span_width: [10, 20]`, `span_thickness: [2, 4]`, `gap_depth: [20, 40]`.
**Strategic role:** rewards Weaponize (collapse) relationship. Anti-synergy with units needing to use the bridge for mobility. Requires units to have crossed before collapsing.
**Generation:** two elevated landmasses with a narrow span of COLLAPSIBLE tiles connecting them. Void below span of defined depth.

### 5.7 Pit / canyon
**Terrain story:** "the terrain gap punishes ground movement."
**Tile composition:** void to defined depth. Bottom is empty (early stages), hazard liquid (late stages), or lava (act 3).
**Parameters:** `width_range: [15, 30]`, `depth_range: [30, 70]`, `bottom: [void, goo, lava]`.
**Strategic role:** forces mobility answer (flying, teleport, arc over). Rewards flooding if bottom is accessible from the player's side. Punishes ground-movement-dependent builds. Critical terrain for lava-crossing profile.
**Generation:** column removal to depth. Bottom fill applied if specified. Lava fill uses a tile status applied at generation (not a tile type); rise rate is set by the stage hazard schedule, not by the generator.

### 5.8 Isolated pillar
**Terrain story:** "elevation advantage is available but exposed."
**Tile composition:** narrow elevated block, indestructible base, carveable top.
**Parameters:** `width_range: [4, 8]`, `height_range: [12, 20]`, `gap_from_other_terrain: [6, 12]`.
**Strategic role:** rewards pre-combat placement decisions (place a unit on the pillar during the placement phase for elevation advantage; accept the exposure). Disconnected from ground by a gap wider than standard climbing range.
**Generation:** narrow elevated block placed at slot position, isolated by carving a gap wider than `climb_max` on both sides.

### 5.9 Crystal deposit
**Terrain story:** "resources are buried here — worth reaching?"
**Tile composition:** CRYSTAL-tagged tiles (3–8 tiles per vein), embedded in normal terrain at defined depth.
**Parameters:** `vein_count: [1, 3]`, `depth_range: [10, 40]`, `tiles_per_vein: [3, 8]`.
**Strategic role:** extraction risk/reward sub-objective. Placed within reach of demolition paths from the player's side.
**Generation:** seed a small cluster of CRYSTAL tiles at a specified depth band, within the left or center horizontal zone. Covered by 5–15 voxels of normal terrain; reachable via digging.

### 5.10 Regenerating structure (act 3+)
**Terrain story:** "the fortification rebuilds itself — speed matters."
**Tile composition:** outer shell tiles flagged REGENERATING (new flag). Interior normal.
**Parameters:** `rebuild_rate: [1 tile per N rounds]`, `max_rebuild_depth: [1, 3]` (how many layers deep it rebuilds from the surface inward).
**Strategic role:** punishes slow demolition; rewards drilling/bypass or precision. Makes arc mastery viable (shoot through the rebuilt wall without removing it).
**Generation:** identical to bunker generation, with REGENERATING flag on outer shell tiles. Rebuild behavior implemented by the terrain status system (per-round tick), not by the generator.

### 5.11 Lava pool / rising lava
**Terrain story:** "the low ground becomes uninhabitable."
**Tile composition:** LIQUID-type tile with fire element status applied at generation. Causes burn damage to units touching it; interacts with existing LIQUID and fire systems.
**Parameters:** `initial_depth: [40, 70]`, `rise_rate: [0, 3]` (voxels per round; 0 = static), `rise_start_round: [2, 6]`.
**Strategic role:** adds urgency; punishes stalling and low-ground units; rewards elevation and arc mastery. Anti-synergy with flooding (player liquid vs. lava — fire element interaction). Rise rate is set by the StageDescriptor hazard schedule, not by the generator.
**Generation:** fill pit bottom or canyon floor with lava tiles at initial depth. Rise behavior is a per-round system event; generator only places initial state.

---

## 6. Tile Durability by Role

Durability values for tile types within generated features. These are the intended gameplay values; the generator assigns them directly. All values are in "hits" (dig points), consistent with the M16 dig/damage decoupling.

| Role | Durability (hits) | INDESTRUCTIBLE flag | Notes |
|---|---|---|---|
| Spawn platform | — | Yes | Never destroyed |
| Skeletal base (feature foundations) | — | Yes | The permanent geometry |
| Reinforced shell (bunker walls) | 8–12 | No | Requires sustained fire |
| Carveable fill (feature interiors) | 3–4 | No | Normal terrain feel |
| Cave / tunnel walls | 3–4 | No | Normal; naturally destroyed by AoE |
| Shaft walls (entry to chamber) | 6–8 | No | Resists casual widening |
| Bridge span | 3–5 + COLLAPSIBLE | No | Collapses when support removed |
| Crystal deposit tiles | 4–6 | No | Freed by dig; drops pickup |
| Regenerating shell | 6–8 + REGENERATING | No | Rebuilds per round |
| Noise-fill terrain | 4 | No | Standard surface terrain |

---

## 7. Profile Schema

A terrain profile is a small data structure (authored as a `.tres` resource, consistent with the rest of the data-definition architecture) that the generator reads before running pass 1.

```gdscript
# res://data/terrain/terrain_profile.gd
class_name TerrainProfile
extends Resource

## One-sentence terrain story (authoring note only, not used in generation)
@export var story : String = ""

## Act range this profile is valid for (for validation / editor tooling)
@export var act_min : int = 1
@export var act_max : int = 3

## Map width range (voxels); resolved by act difficulty at stage instantiation
@export var map_width_min : int = 100
@export var map_width_max : int = 130

## Noise pass amplitude cap (voxels above/below mean surface)
@export var noise_max_amplitude : int = 6

## Slot assignments — null = empty slot
@export var left_slot   : FeatureDefinition = null
@export var center_slot : FeatureDefinition = null
@export var right_slot  : FeatureDefinition = null

## Background features (caves, crystal deposits); may be multiple
@export var background  : Array[FeatureDefinition] = []

## Hazard schedule — applied to StageDescriptor, not to terrain directly
@export var hazards     : Array[HazardDescriptor] = []

## Enemy placement bias (right-biased by default)
@export var enemy_zone_start : float = 0.55  # fraction of map width
@export var enemy_zone_end   : float = 0.90
```

```gdscript
# res://data/terrain/feature_definition.gd
class_name FeatureDefinition
extends Resource

@export var type           : FeatureType  # enum: RIDGE, BUNKER, CAVE, PIT, etc.
@export var width_min      : int
@export var width_max      : int
@export var height_min     : int
@export var height_max     : int
@export var special_params : Dictionary   # feature-specific params (slope_edges, aperture_count, etc.)

enum FeatureType {
    RIDGE, BUNKER, CAVE_TUNNEL, UNDERGROUND_CHAMBER,
    BRIDGE_ARCH, PIT, PILLAR, CRYSTAL_DEPOSIT,
    REGENERATING_STRUCTURE, LAVA_POOL
}
```

---

## 8. Starter Profile Set

Five profiles cover act 1–3 variety without over-engineering. Additional profiles are content work, not architecture work.

| Profile ID | Story | Left | Center | Right | Background | Valid acts |
|---|---|---|---|---|---|---|
| `open_field` | No terrain problem | — | — | — | crystal (1 vein) | 1 |
| `ridge_assault` | Enemy holds high ground | — | ridge | — | cave (1 passage) | 1–2 |
| `fortress_siege` | Enemy inside protection | — | — | bunker | cave (1 passage) | 2–3 |
| `underground_approach` | Path is underground | — | — | — | chamber + tunnels | 2–3 |
| `lava_crossing` | Gap punishes ground | pillar | pit + lava | enemy platform | crystal (2 veins) | 3 |

Act 1 stages use `open_field` and `ridge_assault` only. Act 2 introduces `fortress_siege` and `underground_approach`. Act 3 introduces `lava_crossing` and allows combining features across profiles (e.g. fortress on the right slot with a lava pit in the center).

---

## 9. Terrain Profile Visualizer (First Thing to Build)

Before implementing any feature generator, build a debug visualizer in the existing sandbox. This is the tool that makes all subsequent generation iteration fast.

**What it shows:** a top-down or side-view render of a generated map with each tile colored by its generation origin:
- Spawn platform → fixed color
- Pass 1 feature tiles, per slot → one color per slot (left/center/right/background)
- Pass 1 feature tile roles → optionally shade by role (indestructible base, reinforced shell, carveable fill)
- Pass 2 noise tiles → distinct neutral color
- Void → transparent

**Controls:** profile selector dropdown, seed field, "regenerate" button. Output is rendered in the debug overlay (§3 of the sandbox spec) without launching a real combat scene.

**Why first:** every generation decision is immediately auditable without running a fight. Profile parameters can be tuned in minutes. Pass 1 / pass 2 boundary issues, feature bleeds, and slot collisions are visible at a glance. Without this tool, tuning generation is slow and error-prone regardless of headless test coverage.

---

## 10. Open Decisions

| # | Decision | Notes |
|---|---|---|
| 1 | REGENERATING tile flag implementation | Needs a per-round tile rebuild behavior — tile status system or a separate terrain-tick pass? |
| 2 | Lava rise mechanics | Rise rate is in the StageDescriptor hazard schedule; the generator only places initial state. Confirm rise is a system event, not a tile property. |
| 3 | Multi-profile blending for act 3 | Can a stage combine features from two profiles (fortress right + lava center)? Or does act 3 need dedicated blended profiles? Recommend: allow slot-level mixing from the profile schema rather than profile blending. |
| 4 | Enemy spawn placement within features | Generator places terrain; StageDescriptor places enemies. Generator should export named "enemy anchor points" (e.g. "bunker interior center") for StageDescriptor to reference. |
| 5 | Cave passage unit traversal | Caves need minimum clearance for unit bounding boxes. Minimum passage height of 3 voxels established above; confirm against the tallest unit definition (currently 3 voxels). |
| 6 | Exact lava tile type | Is lava a tile type or a tile status (LIQUID + fire element applied at generation)? Recommend tile status for consistency with the existing LIQUID/fire interaction system. |
