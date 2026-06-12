# Artillery Space

Terrain System — Technical Specification

*Version 0.2*

*Milestone 1 — Destructible Voxel Terrain Prototype*

*■ = Decide before coding    ▷ = Deferred post-M1    ⚠ = Implementation note*

---

# 1. Purpose and Scope

This document is the implementation-ready specification for the Milestone 1 terrain prototype of Artillery Space. Its purpose is to define every system the developer needs to build the prototype without ambiguity, and to explicitly mark decisions that must be made before coding begins, and work that is intentionally deferred to later milestones.

Milestone 1 has one goal: prove that the voxel terrain and ballistic systems feel correct and satisfying before any roguelite, unit, or progression systems are built. Everything in this document serves that goal. Anything that does not serve that goal is explicitly deferred.

## 1.1 Milestone 1 Deliverables

| # | Deliverable | Acceptance Criteria |
| :---- | :---- | :---- |
| 1 | Scrollable voxel terrain map | Map renders at correct voxel size, camera scrolls, terrain is readable |
| 2 | Two tile types (SOLID, VOID) | SOLID tiles render with visual variety; VOID is empty air |
| 3 | Procedural test map | Reproducible terrain with hills, caves, and a spawn platform |
| 4 | Static player unit placeholder | Unit bounding box renders at correct voxel dimensions on spawn platform |
| 5 | Mouse-aimed ballistic projectile | Player clicks to aim; projectile fires with correct arc physics |
| 6 | Gravity and arc physics | Projectile follows realistic arc; gravity constant is tunable |
| 7 | Projectile-terrain collision | Collision detects on face contact, not corners; no false positives |
| 8 | AoE terrain destruction | Impact destroys tiles in diamond pattern with damage falloff |
| 9 | Tile damage states | Tiles show visual crack states at 66% and 33% HP thresholds |
| 10 | Tile collapse | Unsupported tiles fall after destruction (simplified column rule) |
| 11 | Hitbox visualisation | Unit bounding box highlights on hover and in targeting mode |
| 12 | AoE preview overlay | Diamond footprint renders on terrain as cursor moves in targeting mode |

## 1.2 Explicitly Out of Scope for Milestone 1

* Enemy units, enemy AI, or any opposing actor
* Unit movement, turn structure, or command budget
* Multiple unit types or race-specific behavior
* Roguelite systems: maps, shops, runs, resources
* Audio (any)
* RUBBLE and LIQUID tile types (schema defined, not implemented)
* Full connected-component collapse (island detection)
* Line of sight for cover or AI (LoS for firing validation only)
* Wind or environmental hazards
* Scrap generation from terrain destruction

# 2. Critical Pre-Coding Decisions

The following decisions must be made before any code is written. They are not tunable after the fact without significant rework. Recommended values are provided but the developer must commit to one answer before proceeding.

| # | Decision | Options | Recommendation | Impact if Changed Later |
| :---- | :---- | :---- | :---- | :---- |
| 1 | Voxel pixel size | 16px, 24px, 32px | 16px for desktop (clean power-of-two, efficient rendering, unit at 3 tiles = 48px readable) | All art assets, all hitbox math, camera zoom range, UI overlay sizing — visual-only change but touches everything |
| 2 | Map dimensions (prototype) | Any; suggestion: 300w x 100h voxels | 300 × 100 = 30,000 tiles; at 16px = 4800 × 1600px world; fits in memory easily, gives meaningful scroll | Generation parameters, camera bounds, memory budget |
| 3 | Chunk size for rendering | 8×8, 16×16, 32×32 | 16×16 voxels. Balance between draw calls and dirty-region granularity. | Rendering architecture; defer until rendering is implemented but decide before ChunkRenderer |
| 4 | Destruction leaves RUBBLE or VOID | RUBBLE (tile remains, 1HP, passable) or VOID (empty space) | VOID for M1. RUBBLE schema is defined; implement behavior post-M1. | Minor: schema is already compatible. Visual feel difference only in M1. |
| 5 | Collapse rule scope | Column-fall only vs. full island detection | Column-fall only for M1. Island detection is post-M1. | Adds flood-fill pass post-M1; no architectural conflict if signals are in place. |

**■  DECIDE BEFORE CODING: Voxel pixel size: set VOXEL_SIZE as a single project constant before any other code. All other measurements derive from it.**

# 3. Voxel Grid

## 3.1 Grid Definition

| Property | Value | Notes |
| :---- | :---- | :---- |
| Grid type | 2D uniform square grid | All cells identical in size |
| Coordinate origin | Top-left (0, 0) | X increases right, Y increases down (Godot default) |
| Voxel size | VOXEL_SIZE pixels (const) | Single source of truth; recommended 16px |
| Map width | MAP_WIDTH voxels (const) | Recommended 300 for prototype |
| Map height | MAP_HEIGHT voxels (const) | Recommended 100 for prototype |
| Chunk size | CHUNK_SIZE voxels (const) | Recommended 16; used by ChunkRenderer |
| World pixel width | MAP_WIDTH * VOXEL_SIZE | e.g. 300 * 16 = 4800px |
| World pixel height | MAP_HEIGHT * VOXEL_SIZE | e.g. 100 * 16 = 1600px |

## 3.2 Coordinate System

Voxel coordinates are integer pairs (col, row). World pixel position of a voxel's top-left corner is (col * VOXEL_SIZE, row * VOXEL_SIZE). All gameplay calculations operate in voxel coordinates. Pixel coordinates are used only by the rendering layer.

```gdscript
# GDScript — project constants (res://constants.gd or autoload)

const VOXEL_SIZE : int = 16       # pixels per voxel — DECIDE BEFORE CODING
const MAP_WIDTH  : int = 300      # voxels wide
const MAP_HEIGHT : int = 100      # voxels tall
const CHUNK_SIZE : int = 16       # voxels per chunk side

# Coordinate conversion helpers

static func world_to_voxel(world_pos: Vector2) -> Vector2i:
    return Vector2i(int(world_pos.x / VOXEL_SIZE), int(world_pos.y / VOXEL_SIZE))

static func voxel_to_world(vox: Vector2i) -> Vector2:
    return Vector2(vox.x * VOXEL_SIZE, vox.y * VOXEL_SIZE)

static func voxel_center_world(vox: Vector2i) -> Vector2:
    return Vector2((vox.x + 0.5) * VOXEL_SIZE, (vox.y + 0.5) * VOXEL_SIZE)
```

*⚠  Never hard-code pixel distances anywhere. Always express as N * VOXEL_SIZE or as voxel counts. This guarantees changing VOXEL_SIZE remains a single-constant operation.*

# 4. Tile Data Model

## 4.1 Tile Schema

Every occupied voxel stores a Tile object. VOID voxels store null in the grid array — no object, minimal memory. The schema is defined for all future tile types now to prevent costly refactors when RUBBLE, LIQUID, and elemental tiles are implemented post-M1.

```gdscript
# GDScript — res://terrain/tile.gd

class_name Tile

# Tile types — only SOLID active in M1
enum TileType { SOLID, RUBBLE, LIQUID }

# Elemental properties — schema only in M1, no behavior
enum Element { NONE, FIRE, ELECTRIC, EXPLOSIVE, CORROSIVE }

# Flags bitmask — see section 4.2
const FLAG_CLIMBABLE     : int = 1 << 0
const FLAG_LOS_CLEAR     : int = 1 << 1  # does not block LoS
const FLAG_CONDUCTIVE    : int = 1 << 2  # electricity chains through
const FLAG_EXPLOSIVE     : int = 1 << 3  # chain explosion on destroy
const FLAG_INDESTRUCTIBLE: int = 1 << 4  # cannot be damaged
const FLAG_PASSABLE      : int = 1 << 5  # units can move through
const FLAG_SLOWING       : int = 1 << 6  # extra movement cost

var type    : TileType = TileType.SOLID
var hp      : int      = 3
var max_hp  : int      = 3
var element : Element  = Element.NONE
var flags   : int      = 0
var variant : int      = 0   # visual variant index 0–3; no gameplay effect

# Derived — computed from hp/max_hp, not stored
func damage_state() -> int:
    if hp >= max_hp:           return 0  # pristine
    if hp > max_hp * 0.33:     return 1  # cracked
    return 2                              # heavily damaged

func has_flag(f: int) -> bool:
    return (flags & f) != 0

func init(t: TileType, hp_val: int, var_idx: int) -> Tile:
    type = t; hp = hp_val; max_hp = hp_val; variant = var_idx
    return self
```

## 4.2 Flag Reference

| Bit | Constant | M1 Active | Effect |
| :---- | :---- | :---- | :---- |
| 0 | FLAG_CLIMBABLE | No (post-M1) | Units can climb this tile face without movement penalty |
| 1 | FLAG_LOS_CLEAR | No (post-M1) | Does not block line of sight (e.g. mesh fence, glass) |
| 2 | FLAG_CONDUCTIVE | No (post-M1) | Electricity element arcs through this tile to adjacent |
| 3 | FLAG_EXPLOSIVE | No (post-M1) | Triggers chain_explosion() before tile is removed |
| 4 | FLAG_INDESTRUCTIBLE | No (post-M1) | damage_tile() calls are ignored; used for boss arena walls |
| 5 | FLAG_PASSABLE | No (post-M1) | Units can move through tile (used by RUBBLE, LIQUID) |
| 6 | FLAG_SLOWING | No (post-M1) | Movement through costs 2 points instead of 1 |
| 7 | (reserved) | No | Unused |

*⚠  In M1, no flags are set on any tile. The bitmask field exists in the schema so post-M1 tile types do not require a schema change.*

## 4.3 Tile Types Reference

| Type | M1 Active | Destructible | Passable | HP Default | Notes |
| :---- | :---- | :---- | :---- | :---- | :---- |
| SOLID | Yes | Yes | No | 3 (reinforced: 6) | Standard terrain block; provides cover; primary tile type |
| RUBBLE | Schema only | Yes | Yes (slowing) | 1 | Left behind when SOLID destroyed; post-M1 behavior |
| LIQUID | Schema only | No | Yes (slowing) | N/A | Flood, goo; post-M1 |
| VOID | N/A — null | N/A | Yes | N/A | Empty air; stored as null in grid array |

# 5. Grid Data Structure

## 5.1 Storage

The tile grid is a flat Array of size MAP_WIDTH * MAP_HEIGHT. Null entries represent VOID. Index formula: idx = row * MAP_WIDTH + col.

```gdscript
# GDScript — inside TerrainManager
var _grid : Array = []   # size = MAP_WIDTH * MAP_HEIGHT, null = VOID
func _ready():
    _grid.resize(MAP_WIDTH * MAP_HEIGHT)
    _grid.fill(null)
func _idx(col: int, row: int) -> int:
    return row * MAP_WIDTH + col
func get_tile(col: int, row: int) -> Tile:
    if col < 0 or col >= MAP_WIDTH or row < 0 or row >= MAP_HEIGHT:
        return null
    return _grid[_idx(col, row)]
func is_solid(col: int, row: int) -> bool:
    var t = get_tile(col, row)
    return t != null and t.type == Tile.TileType.SOLID
func is_blocked(col: int, row: int) -> bool:
    # Blocked = not passable. In M1: any SOLID tile blocks.
    var t = get_tile(col, row)
    return t != null and not t.has_flag(Tile.FLAG_PASSABLE)
```

*⚠  Use a flat Array, not a Dictionary. Dictionary keyed on Vector2i is acceptable for early prototype work but has significant lookup overhead at scale. Switch to flat Array before any performance measurement.*

## 5.2 Chunk Tracking

Chunks are 2D regions of CHUNK_SIZE x CHUNK_SIZE voxels used to localise rendering updates. Each chunk has a dirty flag. When any tile in a chunk changes, the chunk is marked dirty. On the next render frame, only dirty chunks are redrawn.

```gdscript
var _chunk_dirty : Array = []  # bool array, size = chunks_wide * chunks_tall
func _chunk_idx(col: int, row: int) -> int:
    var cx = col / CHUNK_SIZE
    var cy = row / CHUNK_SIZE
    var chunks_wide = int(ceil(float(MAP_WIDTH) / CHUNK_SIZE))
    return cy * chunks_wide + cx
func _mark_chunk_dirty(col: int, row: int):
    _chunk_dirty[_chunk_idx(col, row)] = true
```

# 6. Terrain Generation (Prototype)

Milestone 1 uses procedural generation sufficient to demonstrate terrain interaction across varied surface shapes and enclosed spaces. Full biome, hazard, and multi-region generation is post-M1.

## 6.1 Generation Algorithm

Execute the following passes in order. Use a fixed noise seed during M1 to produce a reproducible test map. Random seeding comes post-M1.

### Pass 1 — Base fill

1. Fill all voxels from row (MAP_HEIGHT - BASE_FILL_ROWS) to row (MAP_HEIGHT - 1) with SOLID tiles. BASE_FILL_ROWS = 60 (60% of map height). This is the underground mass.

### Pass 2 — Surface noise

2. Apply FastNoiseLite (Godot built-in) to the top surface row of the fill. Noise type: Simplex. Frequency: 0.03. For each column, offset the surface row up or down by int(noise_value * SURFACE_VARIATION) voxels. SURFACE_VARIATION = 8 (creates hills and valleys of up to 8 voxels). Remove or add tiles accordingly.

### Pass 3 — Cave carving

3. Carve 3 cave chambers using ellipse subtraction. For each cave: pick a random center point in the underground mass (at least 10 voxels below surface, 15 voxels from map edges). Pick random radii: width 8–16 voxels, height 5–10 voxels. Set all tiles within the ellipse to null (VOID).

### Pass 4 — Spawn platform

4. Place a flat SOLID platform 8 voxels wide at column 10, at the surface row for that column. This is the player spawn zone. Mark these tiles as indestructible (FLAG_INDESTRUCTIBLE) so the prototype always has a valid firing position.

### Pass 5 — HP assignment

5. Assign HP to all SOLID tiles: default HP = 3, max_hp = 3. For 10% of tiles (random selection), set HP = 6, max_hp = 6 (reinforced). Use a second fixed-seed RNG pass for this so it is separately reproducible.

### Pass 6 — Visual variants

6. For each SOLID tile, assign a random variant index 0–3. This is cosmetic only (selects which sprite frame to render). No gameplay effect.

*⚠  The spawn platform being indestructible is a prototype convenience only. Post-M1, spawn platforms will be normal terrain with rules around unit deployment.*

## 6.2 Generation Constants

| Constant | Recommended Value | Notes |
| :---- | :---- | :---- |
| BASE_FILL_ROWS | 60 | Rows of solid base; 60% of 100-row map |
| SURFACE_VARIATION | 8 | Max voxels of surface deviation from base line |
| NOISE_SEED | 12345 | Fixed for M1; change to randomise post-M1 |
| NOISE_FREQUENCY | 0.03 | Lower = broader hills; higher = rougher terrain |
| CAVE_COUNT | 3 | Number of cave chambers |
| CAVE_WIDTH_MIN / MAX | 8 / 16 | Cave horizontal radius range (voxels) |
| CAVE_HEIGHT_MIN / MAX | 5 / 10 | Cave vertical radius range (voxels) |
| SPAWN_PLATFORM_COL | 10 | Left-edge column of spawn platform |
| SPAWN_PLATFORM_WIDTH | 8 | Width of spawn platform in voxels |
| REINFORCED_TILE_CHANCE | 0.10 | 10% of tiles get double HP |

# 7. Destruction System

## 7.1 Damage Application

The damage_tile() function is the single entry point for all tile damage. Nothing else modifies tile HP directly.

```gdscript
# GDScript — TerrainManager
func damage_tile(col: int, row: int, dmg: int) -> void:
    var tile = get_tile(col, row)
    if tile == null: return                          # VOID, nothing to damage
    if tile.has_flag(Tile.FLAG_INDESTRUCTIBLE): return
    var prev_state = tile.damage_state()
    tile.hp -= dmg
    tile.hp = max(tile.hp, 0)
    var new_state = tile.damage_state()
    if new_state != prev_state:
        _mark_chunk_dirty(col, row)                  # visual update needed
    tile_damaged.emit(col, row, dmg, tile.hp)
    if tile.hp <= 0:
        _destroy_tile(col, row, tile)
```

## 7.2 Tile Destruction Sequence

```gdscript
func _destroy_tile(col: int, row: int, tile: Tile) -> void:
    # Step 1: chain explosion if flagged (post-M1 flag; no-op in M1)
    if tile.has_flag(Tile.FLAG_EXPLOSIVE):
        _trigger_chain_explosion(col, row)           # post-M1
    # Step 2: replace tile
    # M1: always VOID. Post-M1: SOLID becomes RUBBLE.
    _grid[_idx(col, row)] = null                     # VOID for M1
    _mark_chunk_dirty(col, row)
    # Step 3: signals
    tile_destroyed.emit(col, row, tile.type)
    tile_changed.emit(col, row)
    # Step 4: collapse check on tiles above
    _collapse_check_column(col, row - 1)
```

## 7.3 Collapse System

### M1 Rule: Column Fall

After any tile is destroyed, check the column above for unsupported tiles. A tile is unsupported if the tile directly below it is null (VOID). Unsupported tiles fall one row at a time until they find support or reach the map bottom.

```gdscript
func _collapse_check_column(col: int, start_row: int) -> void:
    # Walk upward from start_row; find lowest unsupported tile
    var row = start_row
    while row >= 0:
        var tile = get_tile(col, row)
        if tile == null:
            row -= 1
            continue
        # Check support
        if get_tile(col, row + 1) == null:           # nothing below
            _fall_tile(col, row)
            # After falling, re-check from same position
        else:
            row -= 1
func _fall_tile(col: int, from_row: int) -> void:
    # Find how far this tile falls
    var to_row = from_row + 1
    while to_row < MAP_HEIGHT - 1 and get_tile(col, to_row + 1) == null:
        to_row += 1
    # Move tile
    var tile = _grid[_idx(col, from_row)]
    _grid[_idx(col, from_row)] = null
    _grid[_idx(col, to_row)]   = tile
    _mark_chunk_dirty(col, from_row)
    _mark_chunk_dirty(col, to_row)
    tile_changed.emit(col, from_row)
    tile_changed.emit(col, to_row)
```

*▷  DEFERRED (post-M1): Full island detection (connected-component flood-fill to find floating regions). Column-fall covers ~95% of visible cases for M1.*

# 8. Area of Effect (AoE) Resolution

## 8.1 AoE Shape

The default AoE shape is a diamond defined by Manhattan distance. This is the universal standard for Artillery Space. Circular AoE is a named special property of specific weapons introduced post-M1.

All tiles (col, row) satisfying the following condition are within AoE radius R centered on impact voxel (cx, cy):

```
abs(col - cx) + abs(row - cy) <= R
```

Radius is always a positive integer. R = 0 means impact voxel only. Default explosive radius for M1 is R = 2. Reinforced areas may warrant R = 3 for testing.

## 8.2 Damage Falloff

| Manhattan distance from center | Damage multiplier | Notes |
| :---- | :---- | :---- |
| 0 | 100% | Direct hit voxel |
| 1 | 75% | Adjacent tiles |
| 2 | 50% | Two steps out |
| 3 | 25% | Three steps out (if R ≥ 3) |
| > R | 0% | No damage applied |

*⚠  Damage after multiplier is rounded down to int. Minimum applied damage within radius is 1 (never zero for a tile inside AoE).*

## 8.3 AoE Execution

```gdscript
# GDScript — AoEResolver (stateless; called by ProjectileManager on impact)
static func resolve(terrain: TerrainManager, cx: int, cy: int,
                    radius: int, base_damage: int) -> Array:
    var affected : Array = []
    for col in range(cx - radius, cx + radius + 1):
        for row in range(cy - radius, cy + radius + 1):
            var dist = abs(col - cx) + abs(row - cy)
            if dist > radius: continue
            var multiplier = _falloff(dist, radius)
            var dmg = max(1, int(base_damage * multiplier))
            terrain.damage_tile(col, row, dmg)
            affected.append(Vector2i(col, row))
    return affected
static func _falloff(dist: int, radius: int) -> float:
    if radius == 0: return 1.0
    return 1.0 - (float(dist) / (radius + 1))
```

*⚠  AoEResolver is stateless. It takes a TerrainManager reference and calls damage_tile() for each affected cell. It does not own any state and can be tested in isolation.*

## 8.4 AoE Preview (UI)

When the player is in targeting mode, render a live AoE footprint overlay centered on the cursor's current voxel position. The overlay updates every frame as the cursor moves.

| Tile state during preview | Visual |
| :---- | :---- |
| Within AoE radius, no unit | Red tint overlay at 40% opacity |
| Within AoE radius, contains unit voxel | Bright red / orange at 70% opacity |
| Outside AoE radius | No overlay |
| Impact voxel (center) | Distinct marker (crosshair or bright center dot) |

The preview is rendered on a separate CanvasLayer above terrain and units. It does not affect gameplay state. It is cleared when the player exits targeting mode or fires.

*▷  DEFERRED (post-M1): Preview is disabled in no-preview ascension mode. The architecture should support toggling the preview layer; the toggle itself is post-M1.*

# 9. Projectile Physics and Collision

## 9.1 Projectile Physics Model

Projectiles are point objects with no physical radius. They travel along a ballistic arc determined by initial velocity and continuous gravity. All physics operate in world pixel space; collision detection converts to voxel space.

```gdscript
# GDScript — Projectile.gd (extends Node2D)
const GRAVITY : float = 980.0   # px/s^2 — tune to feel during M1
var velocity  : Vector2 = Vector2.ZERO
var _terrain  : TerrainManager
var _active   : bool = true
func launch(origin: Vector2, direction: Vector2, speed: float,
            terrain: TerrainManager) -> void:
    position  = origin
    velocity  = direction.normalized() * speed
    _terrain  = terrain
    _active   = true
func _physics_process(delta: float) -> void:
    if not _active: return
    velocity.y += GRAVITY * delta
    var new_pos = position + velocity * delta
    # Check collision along movement step
    var hit = _check_collision(position, new_pos)
    if hit.collided:
        _on_impact(hit.impact_voxel, hit.contact_point)
    else:
        position = new_pos
    # Out of bounds check
    if position.x < 0 or position.x > MAP_WIDTH * VOXEL_SIZE \
    or position.y > MAP_HEIGHT * VOXEL_SIZE:
        queue_free()
```

## 9.2 Collision Detection

Collision is checked by stepping along the movement vector and sampling the voxel grid. For M1, a simple DDA (Digital Differential Analyzer) step is sufficient.

```gdscript
func _check_collision(from: Vector2, to: Vector2) -> Dictionary:
    # Returns { collided: bool, impact_voxel: Vector2i, contact_point: Vector2 }
    var step_count = int(from.distance_to(to) / (VOXEL_SIZE * 0.5)) + 1
    for i in range(1, step_count + 1):
        var t   = float(i) / step_count
        var pt  = from.lerp(to, t)
        var vox = world_to_voxel(pt)
        if _terrain.is_blocked(vox.x, vox.y):
            return {
                collided:      true,
                impact_voxel:  _resolve_face_contact(from, pt, vox),
                contact_point: pt
            }
    return { collided: false, impact_voxel: Vector2i.ZERO, contact_point: Vector2.ZERO }
```

## 9.3 Face Contact Rule

Projectiles resolve collision against voxel faces only, never corners or edges. This prevents ambiguous hits at tile boundaries and ensures the AoE center is always a well-defined tile.

When a collision is detected, determine which face the projectile was approaching:

```gdscript
func _resolve_face_contact(from: Vector2, contact: Vector2,
                           vox: Vector2i) -> Vector2i:
    # Sub-voxel position within the hit voxel (0.0 — 1.0 range)
    var vox_world = voxel_to_world(vox)
    var local = contact - vox_world
    var nx = local.x / VOXEL_SIZE   # 0 = left face, 1 = right face
    var ny = local.y / VOXEL_SIZE   # 0 = top face,  1 = bottom face
    # Penetration depth per face
    var pen_left   = nx
    var pen_right  = 1.0 - nx
    var pen_top    = ny
    var pen_bottom = 1.0 - ny
    # Face with smallest penetration = entry face
    var min_pen = min(pen_left, pen_right, pen_top, pen_bottom)
    # The impact voxel IS the hit voxel for standard face hits
    # (corner case handled separately — see 9.4)
    return vox
```

## 9.4 Concave Corner Rule

If the contact point is within CORNER_THRESHOLD of a voxel corner, and both adjacent tiles at that corner are solid, the AoE origin is placed at the corner point. Both adjacent tiles receive full direct-hit damage. The concave corner is treated as a more explosive geometry — intentional design.

```gdscript
const CORNER_THRESHOLD : float = 0.15  # fraction of VOXEL_SIZE
func _is_concave_corner(contact: Vector2, vox: Vector2i) -> bool:
    var vox_world = voxel_to_world(vox)
    var local = (contact - vox_world) / VOXEL_SIZE
    var near_x = local.x < CORNER_THRESHOLD or local.x > (1.0 - CORNER_THRESHOLD)
    var near_y = local.y < CORNER_THRESHOLD or local.y > (1.0 - CORNER_THRESHOLD)
    return near_x and near_y
```

## 9.5 Impact Response

```gdscript
func _on_impact(impact_voxel: Vector2i, contact_point: Vector2) -> void:
    _active = false
    # Resolve AoE
    AoEResolver.resolve(_terrain, impact_voxel.x, impact_voxel.y,
                        AOE_RADIUS, BASE_DAMAGE)
    # Signals for VFX
    projectile_impact.emit(contact_point, impact_voxel)
    queue_free()
```

## 9.6 Physics Tuning Constants

| Constant | Starting Value | Notes |
| :---- | :---- | :---- |
| GRAVITY | 980.0 px/s² | Tune during M1 for feel; lower = floatier, higher = snappier |
| BASE_PROJECTILE_SPEED | 600.0 px/s | Starting speed; will vary by unit/weapon post-M1 |
| AOE_RADIUS | 2 voxels | Default explosion radius for M1 prototype |
| BASE_DAMAGE | 3 | Destroys a standard tile in one direct hit; tune with HP values |
| CORNER_THRESHOLD | 0.15 | Fraction of voxel size for corner detection; smaller = rarer corners |

**■  DECIDE BEFORE CODING: Tune GRAVITY and BASE_PROJECTILE_SPEED together as a pair. The ratio between them determines the arc shape at mid-range. Establish a 'reference shot' (45 degree angle, hits X tiles away) and tune until that feels right before testing other angles.**

# 10. Line of Sight

Line of sight (LoS) in M1 is used exclusively for firing arc validation: checking whether the player's barrel origin has a clear path in the aimed direction. Cover calculation and enemy AI targeting are post-M1.

```gdscript
# GDScript — LoS utility (static, no state)
static func has_los(terrain: TerrainManager,
                    from: Vector2i, to: Vector2i) -> bool:
    # DDA voxel raycast
    # Returns false if any blocked tile (no FLAG_LOS_CLEAR) lies between from and to
    var dx = to.x - from.x
    var dy = to.y - from.y
    var steps = max(abs(dx), abs(dy))
    if steps == 0: return true
    var sx = float(dx) / steps
    var sy = float(dy) / steps
    for i in range(1, steps):
        var col = int(round(from.x + sx * i))
        var row = int(round(from.y + sy * i))
        if terrain.is_blocked(col, row):
            return false
    return true
```

For firing arc visualisation: at each frame in targeting mode, sample LoS from the barrel origin voxel toward the cursor position. If blocked, show the arc as red/invalid past the obstruction point. This is a preview-only feature; the actual collision detection governs what the projectile actually hits.

# 11. Rendering

## 11.1 Node Architecture

```text
World                          (Node2D — scene root)
  ├─ TerrainManager             (Node — owns grid, all tile logic)
  ├─ ChunkRenderer              (Node2D — draws terrain from dirty chunks)
  ├─ ProjectileManager          (Node2D — spawns and tracks projectiles)
  ├─ CollapseSimulator          (Node — processes column-fall after destruction)
  ├─ AoEResolver                (Node — stateless; exposes static resolve())
  ├─ UnitLayer                  (Node2D — renders unit sprites and bounding boxes)
  ├─ UILayer                    (CanvasLayer — AoE preview, hitbox overlays, HUD)
  └─ Camera2D                   (follows action; scroll bounds = map bounds)
```

*⚠  TerrainManager owns all tile data and all tile mutation. No other node modifies tiles directly. All other nodes read tile state through TerrainManager's public API or react to its signals.*

## 11.2 ChunkRenderer

ChunkRenderer listens for tile_changed signals and maintains a dirty flag per chunk. On _process(), it redraws any dirty chunk to a CanvasTexture or uses a TileMap layer per chunk. After redrawing, the dirty flag is cleared.

Tile rendering per voxel: draw the base sprite for the tile's type and variant index. If damage_state() == 1, draw crack overlay A on top. If damage_state() == 2, draw crack overlay B. Overlays are separate semi-transparent textures, not separate tiles.

| damage_state() | Visual Layer 1 | Visual Layer 2 |
| :---- | :---- | :---- |
| 0 (pristine) | Base sprite (type + variant) | None |
| 1 (cracked) | Base sprite (type + variant) | Crack overlay A (light cracks) |
| 2 (damaged) | Base sprite (type + variant) | Crack overlay B (heavy cracks) |

## 11.3 Tile Visual Assets (M1 Placeholder)

For M1, placeholder art is sufficient. Minimum required assets:

* 4 SOLID tile base variants (solid_0.png through solid_3.png): single-color blocks with slight texture variation
* 1 crack overlay A (cracks_light.png): transparent PNG with light crack pattern
* 1 crack overlay B (cracks_heavy.png): transparent PNG with heavy crack pattern
* 1 projectile sprite (projectile.png): small circle or dot, 8px
* 1 explosion VFX (can be a simple expanding circle drawn in code for M1)

*⚠  Art quality does not matter for M1. What matters is that the tile grid is readable, damage states are visually distinct, and the projectile arc is followable on screen. Placeholder colored rectangles are acceptable.*

## 11.4 Hitbox Visualisation

Rendered on UILayer (CanvasLayer, drawn above everything). Two distinct display modes:

| Mode | Trigger | Visual |
| :---- | :---- | :---- |
| Hover | Mouse over unit bounding box | Thin outline in neutral white; no fill; 1px border |
| Targeting mode | Player selects a unit to fire | Filled tint overlay: allied units blue 30% opacity, enemy units red 30% opacity |
| AoE intersection | Unit voxels within AoE preview radius | Bright orange tint 70% opacity, overrides targeting tint |

Bounding box coordinates are expressed in voxels and converted to pixel rectangles for drawing. Rect2(voxel_to_world(top_left), Vector2(width * VOXEL_SIZE, height * VOXEL_SIZE)).

# 12. TerrainManager Public API

Complete public interface for TerrainManager. No other system accesses _grid directly.

## 12.1 Tile Access

```gdscript
func get_tile(col: int, row: int) -> Tile
    # Returns Tile or null (VOID / out of bounds)
func set_tile(col: int, row: int, tile: Tile) -> void
    # Sets tile, marks chunk dirty, emits tile_changed
func is_solid(col: int, row: int) -> bool
    # True if tile exists and type == SOLID
func is_blocked(col: int, row: int) -> bool
    # True if tile exists and not FLAG_PASSABLE (blocks movement and projectiles)
func get_surface_row(col: int) -> int
    # Returns row index of topmost solid tile in column; -1 if column is empty
```

## 12.2 Mutation

```gdscript
func damage_tile(col: int, row: int, dmg: int) -> void
    # Applies damage; handles visual state update, destruction, signals
func clear_tile(col: int, row: int) -> void
    # Immediately sets tile to null (VOID); used by cave generation
```

## 12.3 Query

```gdscript
func get_tiles_in_diamond(cx: int, cy: int, radius: int) -> Array
    # Returns Array of Vector2i for all voxels within Manhattan distance radius
func has_los(from: Vector2i, to: Vector2i) -> bool
    # DDA raycast; returns false if any blocked tile lies between points
func get_chunk_dirty_flags() -> Array
    # Returns the dirty flag array for ChunkRenderer
func clear_all_dirty_flags() -> void
    # Called by ChunkRenderer after completing a redraw pass
```

## 12.4 Signals

| Signal | Arguments | Emitted When | Listeners |
| :---- | :---- | :---- | :---- |
| tile_damaged | col, row, dmg, remaining_hp | Tile takes damage (not necessarily destroyed) | VFX system, audio |
| tile_destroyed | col, row, tile_type | Tile HP reaches 0 and is removed | ChunkRenderer, CollapseSimulator, (post-M1: ScrapSystem) |
| tile_changed | col, row | Any tile mutation (damage or set) | ChunkRenderer (marks dirty flag) |
| projectile_impact | world_pos, impact_voxel | Projectile hits terrain | VFX system, UILayer |
| aoe_resolved | center, radius, affected[] | AoE calculation completes | (post-M1: UnitManager for unit damage) |

# 13. Player Unit Placeholder (M1)

Milestone 1 requires one static unit to demonstrate firing and hitbox visualisation. This is a placeholder, not the full unit system.

## 13.1 M1 Unit Spec

| Property | M1 Value | Post-M1 Notes |
| :---- | :---- | :---- |
| Size | 2 voxels wide, 3 voxels tall | Standard unit dimensions; races will vary |
| Position | Fixed on spawn platform; no movement | Movement system post-M1 |
| Barrel origin | Top-center voxel of bounding box | Will vary by unit type post-M1 |
| HP | Not tracked in M1 | Full HP system post-M1 |
| Visual | Colored rectangle (placeholder) | Sprite per race/unit type post-M1 |

## 13.2 Firing Input (M1)

For M1, use a simplified firing input to validate the physics. The full hold-to-charge vs. manual power decision is post-M1.

* Left-click and hold: draws a direction line from barrel origin toward cursor
* Release: fires projectile in cursor direction at BASE_PROJECTILE_SPEED
* No power variation in M1; all shots fire at the same speed
* Fire angle is computed as: (cursor_world_pos - barrel_origin_world).normalized()

*⚠  The firing input model is intentionally minimal for M1. Its only job is to produce a projectile with a direction vector. Power modulation, charge timing, and preview modes are post-M1.*

# 14. Open Questions

Items requiring a decision before or during Milestone 1 development:

| # | Question | Must Decide | Recommendation |
| :---- | :---- | :---- | :---- |
| 1 | Voxel pixel size? | Before any code | 16px. Clean power-of-two; 3-tall unit = 48px; readable at 1x zoom. |
| 2 | Map dimensions? | Before generation code | 300 × 100 voxels. ~30k tiles; fast to generate; meaningful scroll distance. |
| 3 | Chunk size? | Before ChunkRenderer | 16 × 16 voxels. Profile against 32 × 32 if render performance is poor. |
| 4 | RUBBLE or VOID on destruction? | Before destruction code | VOID for M1. Schema supports RUBBLE; add behavior post-M1. |
| 5 | Gravity / speed tuning? | During M1 | Start: GRAVITY=980, SPEED=600. Tune together using 45-degree reference shot. |
| 6 | AoE radius for prototype? | Before first test | R=2. Feels impactful without destroying too much per shot. |
| 7 | Spawn platform indestructible? | Before generation | Yes for M1 convenience. Remove post-M1. |
| 8 | Placeholder art approach? | Before ChunkRenderer | Solid-color rectangles with distinct colors per damage state. Fast to implement; clearly readable. |

# 15. Deferred to Post-Milestone 1

The following systems are explicitly not part of M1. They are listed here so that M1 architecture decisions do not accidentally close them off.

| System | Why Deferred | Architecture Consideration |
| :---- | :---- | :---- |
| RUBBLE tile behavior | Not needed to validate core destruction feel | Schema already defined; add destroy-to-rubble logic in _destroy_tile() |
| LIQUID tile behavior | Flood/goo hazards are late-design features | Schema defined; add passable + slowing logic to is_blocked() |
| Elemental tile effects | Requires element system and unit interaction | Element enum defined on Tile; add effect resolution to damage_tile() |
| Full island collapse | Complex flood-fill; column-fall sufficient for M1 | Add as second pass in CollapseSimulator after column-fall; signals already in place |
| Scrap generation from destruction | Requires resource system | tile_destroyed signal already emitted; ScrapSystem subscribes post-M1 |
| Cover calculation | Requires unit positioning system | has_los() already implemented; cover = LoS tile count post-M1 |
| Enemy AI | Requires full turn system | TerrainManager API is enemy-agnostic; no changes needed |
| Wind / environmental hazards | Requires hazard system | Projectile velocity is a Vector2; wind = per-frame velocity addition post-M1 |
| Firing power variation | Requires input model decision | Projectile.launch() takes speed param; add charge multiplier to speed post-M1 |
| AoE preview toggle (ascension) | Requires difficulty system | UILayer preview is a toggle; expose show_aoe_preview bool on UILayer post-M1 |
