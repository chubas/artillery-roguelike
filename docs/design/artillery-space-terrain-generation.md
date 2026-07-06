# Artillery Space — Terrain Generation
**Design & Technical Specification · v0.2**

> **STATUS (M44, 2026-07-06):** the procedural generator described here is **dormant**. Combat
> maps are hand-authored ASCII text files (`data/maps/*.txt`, drop-in `user://maps/`) — see
> `docs/planning/milestone-44-plan.md` for the format and pipeline. The generator, placer
> contract, and visualizer remain implemented and smoke-tested for possible later use
> (e.g. seed-varied hand maps or hybrid generation).

> Defines the profile-driven terrain generation system: what strategic constructs must be producible, how they are placed and connected, how their purpose is guaranteed, and the authoring tools needed to iterate on them.
>
> **v0.2 changes:** the two-pass model becomes a five-stage pipeline (noise now runs *before* features so seams are well-defined); feature placers gain a formal **contract** (`FeatureInstance` with footprint, **anchor manifest**, and edge specs); a **seam pass** connects feature edges to the surrounding terrain; a **validation pass** with bounded reroll guarantees each stage's mechanical preconditions. The slot system, constructs catalogue, durability tiers, and profile schema carry over from v0.1. The v0.1 two-pass generator, profile/feature resources, and sandbox visualizer are implemented (M32); v0.2 describes their evolution.

---

## 1. Design Principle: One Terrain Story Per Stage

Every stage has exactly one spatial problem — a "terrain story" — that the player must read and respond to. Features can be stacked in late-game stages, but each feature should contribute a sentence to the same story, not a different story.

Examples of coherent terrain stories:
- "The enemy holds the high ground — you need arc mastery or demolition."
- "The approach is underground — you need drilling or burrowing."
- "A lava pit separates the sides — mobility or arc mastery or flood wins, low-ground stalling loses."

A stage with three features that each demand a different terrain relationship has no story — it rewards ignoring terrain entirely. This is the most common failure mode of procedural terrain and the one this spec is designed to prevent.

**Content rule for profile authoring:** before writing a profile definition, state the terrain story in one sentence. If you can't, the profile needs to be simplified.

**Division of responsibility (resolves v0.1 open decision):** the *designer* states the thesis in the profile; the *generator* checks the mechanical preconditions for it (validation pass, §7). The generator never invents the story; it guarantees the story is physically present in the map.

---

## 2. The Generation Pipeline (v0.2)

Generation runs in five stages, in this order. Each stage is deterministic from the seed.

| Stage | Name | Summary |
|---|---|---|
| A | **Base + noise surface** | Existing FastNoiseLite pass fills the whole map with a base fill and a noise-varied surface, amplitude clamped by `noise_max_amplitude`. Spawn platform columns excluded (fixed). |
| B | **Skeletal features** | Placer modules (§5) stamp features into their slots (§4), *overwriting* noise within their footprint, anchored against the real surface produced by stage A. Each placer returns a `FeatureInstance`. |
| C | **Seam pass** | Reconciles each feature's boundary with the neighboring surface according to the feature's declared edge specs (§6): ramp, cliff, gap, or flush. |
| D | **HP + variants** | Existing passes: reinforced-tile sprinkle, visual variant assignment. Never touches feature tiles' assigned durability. |
| E | **Validation + reroll** | Runs reachability, clearance, and per-feature function checks (§7). On failure, re-generates with a derived seed (bounded attempts), then fails loudly in the sandbox. |

**Why the order changed from v0.1:** the v0.1 generator ran features first, then noise. That meant placers computed the "surface" against an essentially empty map, and the noise later met feature edges wherever it happened to land — seams were undefined and unfixable. In v0.2 the noise surface exists before any feature is placed, so placers anchor to real terrain and the seam pass has a well-defined boundary to reconcile. The invariant "feature tiles are never overwritten by noise" is preserved in the opposite direction: features overwrite noise inside their footprint, and stages C–D never alter a feature's interior.

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

## 5. Feature Placer Contract (new in v0.2)

The core extensibility mechanism. Adding a new terrain structure = one new placer script + one `FeatureDefinition` `.tres`. No edits to the generator core.

### 5.1 Placer modules and registry

Each `FeatureType` maps to a self-contained placer (one script per feature) registered in a placer registry. The generator core only knows the interface:

```gdscript
# Conceptual interface — every placer implements this.
func place(data: MapData, slot_rect: Rect2i, def: FeatureDefinition,
        rng: RandomNumberGenerator) -> FeatureInstance
```

The placer is responsible for its **internal invariants by construction** — this is what makes "the feature is guaranteed to serve its function" real:
- A bunker always has ≥1 aperture with clear line-of-sight out and interior clearance ≥ the tallest unit bounding box.
- A pit is always wider than the maximum climb/step range.
- A bridge span is always COLLAPSIBLE tiles over a real void with supports.

What the placer *cannot* guarantee alone (how it meets the surrounding terrain, whether the whole map is solvable) is handled by the seam pass (§6) and validation pass (§7).

### 5.2 FeatureInstance

Every placement returns a `FeatureInstance` — the record the rest of the pipeline (and the StageDescriptor) consumes:

```gdscript
class_name FeatureInstance
var id         : String                 # e.g. "bunker_1" — type + ordinal, unique per map
var type       : FeatureDefinition.FeatureType
var footprint  : Rect2i                 # claimed voxel region (seam pass boundary)
var anchors    : Dictionary             # name -> Vector2i (exact) or Rect2i (zone)
var edge_specs : Dictionary             # side -> EdgeType (see §5.4)
```

`MapData` carries the array of `FeatureInstance`s produced during generation, so anchors survive to combat-scene setup.

### 5.3 Anchor manifest

Anchors are the handshake with the StageDescriptor (see the stage-design doc §4): the generator exports named positions; the descriptor places enemies, fixtures, and objectives **by anchor name, never by coordinate**. The same descriptor then produces a coherent stage across every seed.

Resolved design decisions (were open questions in the stage-design doc):
- **Namespacing:** anchors are addressed `<instance_id>.<anchor_name>` (e.g. `bunker_1.core`). Single-instance shorthand (`bunker.core`) resolves iff exactly one instance of that type exists.
- **Exact vs. zone:** both. An anchor value is a `Vector2i` (precise — an aperture) or a `Rect2i` zone (freeform — "anywhere in the interior cavity"). Zone anchors are resolved to a concrete voxel at placement time by the consumer (seeded, respecting unit footprints).
- **Fallback:** the descriptor declares a fallback chain per placement (`aperture_right → aperture_left → skip`). No silent nearest-match.
- **Validation:** before combat starts, every anchor a descriptor requires must resolve; a missing anchor is a loud sandbox failure, never a silently misplaced enemy.

Standard anchor names per construct (extended as constructs are implemented):

| Construct | Anchors |
|---|---|
| Ridge | `summit_center`, `reverse_slope` (hidden side), `foot_left`, `foot_right` |
| Bunker | `interior_center` (zone), `aperture_1..n`, `core`, `roof_center` |
| Pit | `rim_left`, `rim_right`, `bottom_center` (zone) |
| Pillar | `top_center` |
| Crystal deposit | `vein_center` |
| Cave / chamber | `chamber_center` (zone), `shaft_mouth` |

### 5.4 Edge specs (the seam contract)

Each placer declares, per side of its footprint, how that edge wants to meet the world:

| EdgeType | Meaning | Seam pass action |
|---|---|---|
| `RAMP` | Walkably connected | Build a staircase (≤ climb step per column) between feature edge and neighbor surface |
| `CLIFF` | Hard drop is fine | Leave as generated |
| `GAP` | Must NOT connect | Carve to guarantee minimum gap width vs. climb/step range |
| `FLUSH` | Sits on the surface | Fill foundation columns beneath the feature base down to the neighbor surface |

---

## 6. Seam Pass (new in v0.2)

Runs after features are placed. For each `FeatureInstance`, walk the boundary columns of its footprint, compare the feature's edge row to the adjacent terrain surface row, and apply the declared `EdgeType`. Rules of thumb:

- Seam modifications are confined to a small band (~2–6 columns) outside the footprint; the seam never edits feature interior tiles.
- Seam-placed tiles use normal-durability fill (they are connective tissue, not protection) and get their own `gen_origin` value so the visualizer can show them.
- `FLUSH` foundations use indestructible tiles only when the feature's own base is indestructible (don't create an undermining exploit the placer didn't intend — or do, if the profile wants collapse play; the placer decides via its edge spec).
- Deterministic: consumes the same seeded RNG stream as the rest of the pipeline.

---

## 7. Validation Pass + Reroll (new in v0.2)

Generation is not provably correct — it is *checked*. After the map is complete:

1. **Reachability:** flood-fill from the spawn platform over standable/climbable voxels, with a dig-cost weighting for destructible obstructions, must reach the enemy zone (or every anchor tagged `must_reach`).
2. **Clearance:** every cavity/passage/zone anchor has bounding-box room for the largest unit definition.
3. **Per-feature function checks:** each placer contributes a validator run against the *final* map (aperture LOS actually clear after seams, pit actually uncrossable, bridge span actually supported-collapsible).
4. **Solvability proxy:** approximate the "≥ 2 terrain relationships viable" rule from the stage-design doc — e.g. reinforced shell thickness within drill range *or* an over-the-top arc path exists.

On any failure: re-generate with a derived seed (`hash(seed, attempt)`), up to ~5 attempts, then **fail loudly** in the sandbox with the profile id, seed, and the failed check printed. In a shipped run, the last attempt's map is used with a logged warning (never block the player), but sandbox/smoke treats reroll exhaustion as an error to fix in the profile or placer.

---

## 8. Natural Constructs Catalogue

Each construct entry defines: what strategic problem it poses, what tile composition it uses, and its generation parameters. (Anchor names per construct: §5.3.)

### 8.1 Open field
**Terrain story:** none (reference state).
**Tile composition:** noise-generated surface, all normal-durability SOLID.
**Parameters:** none beyond noise amplitude.
**Act range:** 1–2 (as full stage), 3 (as partial slot in multi-feature stages).

### 8.2 Ridge / elevated platform
**Terrain story:** "the enemy holds the high ground."
**Tile composition:** indestructible base (bottom 30% of feature height), normal-durability carveable fill (top 70%).
**Parameters:** `height_range: [8, 18]`, `width_range: [20, 40]`, `slope_edges: bool`.
**Strategic role:** forces Go Over or Remove terrain relationship. Primary non-flat feature for act 1.
**Generation:** rectangular block placed at slot center column, raised from the terrain surface by `height` voxels. Edges use `RAMP` seams when `slope_edges`, else `CLIFF`.

### 8.3 Bunker / fortification
**Terrain story:** "the enemy is inside a protected structure."
**Tile composition:** reinforced outer shell (2–3 voxels thick, high HP), normal-durability interior fill, 1–2 aperture gaps in the facing wall.
**Parameters:** `width_range: [12, 24]`, `height_range: [8, 14]`, `wall_hp: [8, 12]`, `aperture_count: [1, 2]`.
**Strategic role:** forces Go Through (drilling), Go Around (precision), or Remove (sustained demolition). Anti-synergy with flooding, arc mastery. Primary feature for Act 1 boss.
**Generation:** hollow rectangular shell at surface level (`FLUSH` base seam). Interior enemies placed via anchors by the StageDescriptor.

### 8.4 Cave / tunnel system
**Terrain story:** "there is an underground path."
**Tile composition:** carved void through solid terrain mass. Ceiling and floor are normal-durability. Passage width minimum 4 voxels, height minimum 3 voxels (unit passage clearance).
**Parameters:** `passage_count: [1, 3]`, `depth_range: [20, 60]`, `connects_to_surface: bool`.
**Strategic role:** rewards drilling/burrowing shots; enables below-ground unit paths if mobility allows. Background feature; does not occupy a surface slot.
**Generation:** carve connected ellipses or spline paths at a depth band. If `connects_to_surface`, carve a narrow vertical shaft (2 voxels wide) from passage to surface. Shaft is tight enough to require deliberate traversal.

### 8.5 Underground chamber
**Terrain story:** "the enemy controls a hidden arena."
**Tile composition:** large carved void with narrow entry shafts. Chamber walls are normal-durability; shaft walls are reinforced.
**Parameters:** `chamber_width: [30, 50]`, `chamber_height: [20, 35]`, `shaft_width: 2–3`, `shaft_count: [1, 2]`.
**Strategic role:** rewards excavation and burrowing approach. Natural habitat for boss-type enemies. Acts as a mid-right slot feature for hive-style encounters.
**Generation:** large ellipse carve at depth 40–70 voxels. Entry shafts carved from surface to chamber ceiling, reinforced walls to discourage easy widening.

### 8.6 Natural bridge / arch
**Terrain story:** "there is a chokepoint that can be collapsed."
**Tile composition:** span tiles explicitly tagged COLLAPSIBLE, normal durability. Supporting columns are indestructible.
**Parameters:** `span_width: [10, 20]`, `span_thickness: [2, 4]`, `gap_depth: [20, 40]`.
**Strategic role:** rewards Weaponize (collapse) relationship. Anti-synergy with units needing to use the bridge for mobility. Requires units to have crossed before collapsing.
**Generation:** two elevated landmasses with a narrow span of COLLAPSIBLE tiles connecting them. Void below span of defined depth.

### 8.7 Pit / canyon
**Terrain story:** "the terrain gap punishes ground movement."
**Tile composition:** void to defined depth. Bottom is empty (early stages), hazard liquid (late stages), or lava (act 3).
**Parameters:** `width_range: [15, 30]`, `depth_range: [30, 70]`, `bottom: [void, goo, lava]`.
**Strategic role:** forces mobility answer (flying, teleport, arc over). Rewards flooding if bottom is accessible from the player's side. Punishes ground-movement-dependent builds. Critical terrain for lava-crossing profile.
**Generation:** column removal to depth (`GAP` semantics — validation confirms it is uncrossable on foot). Bottom fill applied if specified. Lava fill uses a tile status applied at generation (not a tile type); rise rate is set by the stage hazard schedule, not by the generator.

### 8.8 Isolated pillar
**Terrain story:** "elevation advantage is available but exposed."
**Tile composition:** narrow elevated block, indestructible base, carveable top.
**Parameters:** `width_range: [4, 8]`, `height_range: [12, 20]`, `gap_from_other_terrain: [6, 12]`.
**Strategic role:** rewards pre-combat placement decisions (place a unit on the pillar during the placement phase for elevation advantage; accept the exposure). Disconnected from ground by a gap wider than standard climbing range.
**Generation:** narrow elevated block placed at slot position, isolated by `GAP` seams on both sides (guaranteed wider than `climb_max`).

### 8.9 Crystal deposit → mineral veins (superseded by M42)
The M42 **MINERAL** terrain system implements this construct's role: MINERAL tiles (durability 2, pink) scattered by `TerrainManager.scatter_minerals`, dropping collectible **Ore** worth currency. A future placer can express *authored* deposits (deeper, richer veins at profile-chosen depths) using the same MINERAL tile type; the current scatter pass remains the ambient baseline.

### 8.10 Regenerating structure (act 3+)
**Terrain story:** "the fortification rebuilds itself — speed matters."
**Tile composition:** outer shell tiles flagged REGENERATING (new flag). Interior normal.
**Parameters:** `rebuild_rate: [1 tile per N rounds]`, `max_rebuild_depth: [1, 3]` (how many layers deep it rebuilds from the surface inward).
**Strategic role:** punishes slow demolition; rewards drilling/bypass or precision. Makes arc mastery viable (shoot through the rebuilt wall without removing it).
**Generation:** identical to bunker generation, with REGENERATING flag on outer shell tiles. Rebuild behavior implemented by the terrain status system (per-round tick), not by the generator.

### 8.11 Lava pool / rising lava
**Terrain story:** "the low ground becomes uninhabitable."
**Tile composition:** LIQUID-type tile with fire element status applied at generation. Causes burn damage to units touching it; interacts with existing LIQUID and fire systems.
**Parameters:** `initial_depth: [40, 70]`, `rise_rate: [0, 3]` (voxels per round; 0 = static), `rise_start_round: [2, 6]`.
**Strategic role:** adds urgency; punishes stalling and low-ground units; rewards elevation and arc mastery. Anti-synergy with flooding (player liquid vs. lava — fire element interaction). Rise rate is set by the StageDescriptor hazard schedule, not by the generator.
**Generation:** fill pit bottom or canyon floor with lava tiles at initial depth. Rise behavior is a per-round system event; generator only places initial state.

---

## 9. Tile Durability by Role

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
| Mineral (MINERAL type, M42) | 2 | No | Breaks into collectible Ore |
| Regenerating shell | 6–8 + REGENERATING | No | Rebuilds per round |
| Seam fill (ramps, foundations) | 3–4 | Matches feature base | Connective tissue, not protection |
| Noise-fill terrain | 4 | No | Standard surface terrain |

---

## 10. Profile Schema

Implemented as `terrain/terrain_profile.gd` + `terrain/feature_definition.gd`, authored as `.tres` resources in `data/terrain/profiles/` and `data/terrain/features/` (baked like all other data definitions).

```gdscript
class_name TerrainProfile
extends Resource

@export var story               : String = ""   # one-sentence terrain story (authoring note)
@export var act_min             : int = 1
@export var act_max             : int = 3
@export var map_width_min       : int = 100
@export var map_width_max       : int = 130
@export var map_height_min      : int = 90
@export var map_height_max      : int = 110
@export var noise_max_amplitude : int = 6
@export var left_slot           : FeatureDefinition = null
@export var center_slot         : FeatureDefinition = null
@export var right_slot          : FeatureDefinition = null
@export var background          : Array[FeatureDefinition] = []
@export var enemy_zone_start    : float = 0.55
@export var enemy_zone_end      : float = 0.90
```

```gdscript
class_name FeatureDefinition
extends Resource

@export var type           : FeatureType
@export var width_min      : int
@export var width_max      : int
@export var height_min     : int
@export var height_max     : int
@export var special_params : Dictionary   # feature-specific (slope_edges, aperture_count, ...)
```

Hazard schedules stay on the StageDescriptor, not the profile.

---

## 11. Starter Profile Set

Baked today: `open_field`, `ridge_assault`, `fortress_siege`, `pit_crossing`. Target set for act coverage:

| Profile ID | Story | Left | Center | Right | Background | Valid acts | Status |
|---|---|---|---|---|---|---|---|
| `open_field` | No terrain problem | — | — | — | crystal (1 vein) | 1 | baked |
| `ridge_assault` | Enemy holds high ground | — | ridge | — | cave (1 passage) | 1–2 | baked (no cave yet) |
| `fortress_siege` | Enemy inside protection | — | — | bunker | cave (1 passage) | 2–3 | baked (no cave yet) |
| `pit_crossing` | Gap punishes ground | — | pit | — | — | 1–2 | baked |
| `underground_approach` | Path is underground | — | — | — | chamber + tunnels | 2–3 | planned |
| `lava_crossing` | Gap punishes ground, floor kills | pillar | pit + lava | enemy platform | crystal (2 veins) | 3 | planned |

Act 1 stages use `open_field`, `ridge_assault`, `pit_crossing`. Act 2 introduces `fortress_siege` and `underground_approach`. Act 3 introduces `lava_crossing` and allows combining features across profiles (slot-level mixing from the schema, not profile blending).

---

## 12. Terrain Profile Visualizer

**Implemented** (M32) in the debug sandbox: profile dropdown (plus "(legacy noise)"), seed field, "regenerate terrain" button; tiles colored by `gen_origin` (spawn platform / left / center / right slot / background / noise fill).

v0.2 adjustments needed as the pipeline evolves:
- **Anchor overlay:** draw each `FeatureInstance`'s anchors as labeled markers (exact = dot, zone = outlined rect).
- **Seam origin color:** seam-pass tiles get their own `gen_origin` and color.
- **Validation readout:** show pass/fail per check, which attempt (reroll count) produced the final map, and the failed check + seed on exhaustion.
- The "regenerate terrain" flow must rebuild the `FeatureInstance` list and re-run seams + validation, not just re-stamp tiles.

---

## 13. Open Decisions

| # | Decision | Status / notes |
|---|---|---|
| 1 | REGENERATING tile flag implementation | Open — tile status system or a separate terrain-tick pass? |
| 2 | Lava rise mechanics | Confirmed direction: rise is a system event scheduled by the StageDescriptor; generator only places initial state. |
| 3 | Multi-profile blending for act 3 | Resolved: slot-level mixing via the profile schema; no profile blending. |
| 4 | Enemy anchor points | **Resolved in v0.2:** anchor manifest on `FeatureInstance` (§5.3); StageDescriptor consumes by name with fallback chains and loud validation. |
| 5 | Cave passage unit traversal | Minimum passage height 3 voxels; confirm against the tallest unit definition before implementing caves. |
| 6 | Exact lava tile type | Recommend tile status (LIQUID + fire element at generation) for consistency with existing LIQUID/fire interaction. |
| 7 | Dig-cost weighting in reachability | How many total dig hits count as "reachable" before the check fails? Tune in sandbox. |
| 8 | Zone-anchor resolution | Who picks the concrete voxel in a zone — generator (at validation) or StageDescriptor (at placement)? Leaning descriptor-side, seeded. |
| 9 | Shipped-run reroll exhaustion | Currently: use last attempt + logged warning. Revisit if playtests surface broken maps. |
