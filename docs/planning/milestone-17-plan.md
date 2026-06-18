# Milestone 17 — Collapsible Terrain & Crush Collapse

## What was built

Collapsible terrain falls column-wise in a single engine tick when `TerrainManager.resolve_collapses()`
(or `resolve_all_collapses()`) runs. Falling tiles crush units/deployables they land on (damage =
tile `max_hp`), then the tile is consumed. `Tile.collapsible` is a mutable bool for future
transmutation effects.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **`Tile.collapsible`** stays a mutable `bool` (not a bitmask flag) so transmutation can flip it at runtime. |
| 2 | **Row index increases downward** — tiles fall toward higher row indices until they rest on a blocking tile or the map bottom. |
| 3 | **Bottom-up per column** — scan `row` from `MAP_HEIGHT-2` down to `0` each pass; repeat whole column set until stable (stacked collapsibles settle in one tick). |
| 4 | **Crush damage** = falling tile's **`max_hp`** (durability). All units and deployables occupying the impact voxel take that damage; the tile is destroyed (not placed). |
| 5 | **`resolve_collapses(units, deployables)`** — processes **queued** columns (from `damage_tile` destroys) until stable. **`resolve_all_collapses(units, deployables)`** — scans every column (end-of-turn / transmute hooks). |
| 6 | **No deferred collapse** — callers pass occupants so crush damage applies; `AoEResolver` passes its unit/deployable lists after each blast. |
| 7 | **Default generated terrain is not collapsible** (`collapsible = false`). Specific tiles opt in via content/transmutation later; indestructible spawn platform stays `collapsible = false`. |
| 8 | **`EventBus.terrain_crushed(col, row, damage, victims)`** — fired when a falling tile crushes occupants. |
| 9 | **`Features.collapse_enabled`** kill switch at `TerrainManager` entry points. |

---

## Files changed

| File | Change |
|---|---|
| `terrain/tile.gd` | Document `collapsible` as transmutation-ready |
| `terrain/terrain_manager.gd` | Crush-aware fall; `resolve_collapses` / `resolve_all_collapses` / `queue_collapse` |
| `terrain/aoe_resolver.gd` | `resolve_collapses(units, deployables)` after blast |
| `autoloads/event_bus.gd` | `terrain_crushed` signal |
| `autoloads/features.gd` | `collapse_enabled` |
| `world/combat_scene.gd` | `_m17_smoke()` |
| `PROGRESS.md` | M17 entry |

---

## Verification

`ARTILLERY_SMOKE=1 godot --headless` — `_m17_smoke()` spot-checks crush damage, multi-tile stack, and queued-column resolve.
