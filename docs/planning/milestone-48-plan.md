# Milestone 48 — Native LDtk Map Importer

## Why

LDtk is now the source of truth for authored maps. The temporary ASCII format proved the runtime
contract, but every new field required more ad-hoc syntax and duplicated validation in Python and
Godot. M48 replaces that interchange with typed Godot resources while preserving the mutable voxel
runtime that powers damage, destruction, collapse, statuses, and seeded terrain variation.

## Locked decisions

| Decision | Choice |
|---|---|
| Authoring source | Raw LDtk project JSON (`.ldtk`) |
| Source location | External repository, absolute path in `LDTK_PROJECT_PATH` |
| Import execution | Headless Godot command |
| Generated artifact | One `MapDefinition` `.tres` resource per LDtk level |
| Runtime terrain | Existing `MapData` → `TerrainManager`; no TileMap or imported scene |
| Gameplay layers | `Terrain` and `SpawnZones` IntGrid layers |
| Entities | Every instance from any LDtk Entity layer, with arbitrary custom fields |
| Encounter stages | Existing `StageDescriptor` resources remain separate |
| Pool eligibility | Optional LDtk level Bool `rl_pool`, default `true` |
| Compatibility | ASCII maps, parser, Python sync, and `user://maps` support are removed |
| External levels | Rejected in M48 with an actionable error |

## Data flow

```text
external map1.ldtk
    │ JSON.parse
    ▼
LdtkMapImporter
    │ validated MapDefinition resources
    ▼
res://data/maps/<rl_id>.tres
    ├── MapLibrary / zones / entities
    └── MapDefinition.to_map_data(stage_seed)
            ▼
        TerrainManager
```

The importer is a compiler, not a runtime dependency. Builds and play sessions load only generated
Godot resources. The original absolute source path is never serialized; each resource stores the
LDtk project filename, level IID, and source SHA-256 for provenance.

## LDtk schema

### Required level fields

- `rl_id: String` — stable game identifier and output filename.
- `rl_name: String` — display title.
- `rl_description: String`.
- `rl_notes: String`.

### Optional level fields

- `rl_pool: Bool = true` — eligibility for normal random-map selection.
- `autoFillTerrain: Bool = false`.
- `autoFillTerrainValues: String` — JSON `[N, M]`, required when auto-fill is enabled,
  with `1 <= N <= M <= 9`.

### Terrain IntGrid

`Terrain` must be an IntGrid layer. Its flat `intGridCsv` is stored row-major as a
`PackedByteArray` without first expanding it into tile dictionaries:

- `0`: empty
- `1`–`9`: destructible solid with that durability
- `10`: unbreakable solid
- `11`: mineral

Only value `1` is replaced by seeded coherent noise when auto-fill is enabled. Explicit values
`2`–`11` remain authorial overrides.

### SpawnZones IntGrid

`SpawnZones` must match Terrain's width, height, and grid size:

- `0`: none
- `1`, `2`: player zones, kept separate by value
- `3`, `4`: enemy zones, kept separate by value
- `5`: reserved and rejected until gameplay semantics are defined

Each value is converted to a deterministic exact rectangle cover by merging identical horizontal
runs on adjacent rows. Rectangle coordinates use Godot's half-open `Rect2i` representation.

### Entities

Every instance from every LDtk Entity layer is imported. The importer does not interpret names.
Each `MapEntity` resource stores:

- LDtk identifier (`name`)
- instance IID
- source layer identifier
- `__grid` coordinate
- arbitrary `fieldInstances`, keyed by `__identifier`

Multiple instances of the same identifier are valid. Runtime systems decide whether and how to
consume them; the boss convention remains `entity.name.to_lower()` → unit resource id.

## Validation and generation contract

Import is all-or-nothing. No generated resource is replaced unless every embedded level validates:

- supported LDtk JSON major/minor version and embedded-level mode
- object/array shapes required by the importer
- unique, filename-safe `rl_id`
- required layers and matching IntGrid dimensions
- `intGridCsv.size() == width * height`
- known terrain and spawn values
- at least one player and one enemy zone
- valid auto-fill range
- valid entity IID/name/grid coordinate and in-bounds position
- correct `rl_pool` type

Outputs are generated deterministically and written atomically. Stale generated `.tres` files that
carry M48 provenance are removed after a successful import; unrelated resources are never deleted.

## Runtime migration

`MapDefinition` deliberately exposes the same map-level concepts previously consumed from
`CustomMap`: metadata, dimensions, zones, entities, pool eligibility, and `to_map_data(seed)`.
`MapLibrary`, combat, sandbox, and UI switch to this typed resource. `MapData`, `TerrainManager`,
rendering, projectile collision, and terrain mutation remain unchanged.

## Commands

```sh
LDTK_PROJECT_PATH="/absolute/path/to/map1.ldtk" \
godot --headless --path . --script res://tools/import_ldtk_maps.gd
```

Verification uses a dedicated headless importer test, generated-resource parity checks, Godot
project parsing, and the full `ARTILLERY_SMOKE=1` combat smoke chain.

## Out of scope

- TileMap, tileset, PNG, composite, or scene import
- editor-time visual previews
- external LDtk level files
- binding `StageDescriptor` encounter data to LDtk levels
- trigger/entity gameplay beyond preserving custom fields
- spawn value `5`
