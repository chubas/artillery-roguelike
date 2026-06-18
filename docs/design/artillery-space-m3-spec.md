# Artillery Space — Milestone 3: Elements, Status Effects and Combat Engine

**Technical Specification · v0.1**

M3 builds the interaction engine that makes combat emergent. It introduces Fire and Electric as the first two elements, unit and tile status effects, the EventBus trigger system, and the Features flag autoload. By the end of M3 a fire shot should burn terrain, spread to adjacent flammable tiles, and apply Burn stacks to units standing in it — without any of those systems knowing about each other.

---

## 1\. Purpose and Scope

M2 proved the combat loop works. M3 makes it interesting. The goal is not to add content — it's to build the **engine that makes content cheap to add**. Every system built here should make adding Freeze, Corrosive, new keywords, and eventually the card deck trivially easy in later milestones.

M3 has three pillars:

1. **EventBus \+ Features** — the architectural backbone all other systems hook into  
2. **Element system** — Fire and Electric carried on `AoEGroup`s, with affinity multipliers on units  
3. **Status effect system** — Burn and Shock on units; Burning and Electrified on tiles

These three pillars are deliberately minimal. The architecture must be correct. The content can grow later.

---

## 1.1 Deliverables

| \# | Deliverable | Acceptance criteria |
| :---- | :---- | :---- |
| 1 | `EventBus` autoload | All M2 gameplay events re-routed through signals; no system imports another directly |
| 2 | `Features` autoload | Boolean flags per system; disabling `elements_enabled` makes all shots behave as physical |
| 3 | `ElementDef` resource | Fire and Electric defined as `.tres` files with affinity hooks and status references |
| 4 | Element field on `AoEGroup` | Each group can carry one element; resolver applies element on hit |
| 5 | Affinity table on `UnitDefinition` | Per-element multiplier dictionary; Bio and Awakened (Cell) have distinct affinities |
| 6 | `StatusEffectDef` resource | Burn and Shock defined as `.tres` files |
| 7 | `StatusInstance` runtime object | Per-unit tracking of stacks and remaining turns |
| 8 | Status tick system | Burn and Shock tick at correct phase; damage and action reduction applied |
| 9 | Stack cap and refresh | Re-applying at cap (3) refreshes duration; does not exceed cap |
| 10 | Tile status framework | `TileStatusDef` and `TileStatusInstance`; tiles can carry statuses |
| 11 | Burning tile status | Damages touching units per tick; spreads to `FLAMMABLE` neighbours; dies on `LIQUID` contact |
| 12 | Electrified tile status | Damages touching units; chains instantly through `CONDUCTIVE` neighbours |
| 13 | Tile tags | `FLAMMABLE`, `CONDUCTIVE`, `LIQUID`, `SPREADABLE` active on tile definitions |
| 14 | Unit tags | `ORGANIC`, `MECHANICAL`, `SHIELDED` on `UnitDefinition`; used by affinity and chain rules |
| 15 | Stack badge (placeholder) | Unit shows a small number badge per active status; colour-coded by element |
| 16 | Tile status overlay (placeholder) | Burning tile shows orange tint; Electrified shows blue-white tint |
| 17 | Two new enemy unit definitions | One `ORGANIC`\-tagged (weak to fire); one `MECHANICAL`\-tagged (weak to electric) |
| 18 | Two new shot definitions | Fire shell and Electric shell; same arc trajectory, different element |
| 19 | M3 test scenario | Reproducible map with one fire-weak and one electric-weak enemy; player has both shot types |

---

## 1.2 Out of Scope for M3

- Freeze, Corrosive, Resonant elements — content only, architecture is ready after M3  
- Keyword system (Piercing, Bouncing, Volatile, etc.) — M4  
- Chill, Frozen, Corrode, Goo, Shield, Regen, Anchor, Marked statuses — M4+  
- Wind system and hazard displacement — M4+  
- RUBBLE tile behavior — still produces VOID on destruction  
- Card / action deck — future milestone, explicitly open  
- Faction-specific mechanics (Bio regen, Cell network, Army combined arms) — post-M3  
- Enemy AI improvements — enemies still use M2 fixed-angle IK firing  
- Visual polish of any kind

---

## 2\. Architecture: EventBus and Features

### 2.1 EventBus Autoload

`EventBus` is a global signal hub. **No gameplay system imports or calls another system directly.** All communication goes through signals on `EventBus`. This is the rule that makes the interaction system emergent — fire does not call the wind system; both subscribe to shared signals and act on them independently.

\# res://autoloads/event\_bus.gd

extends Node

\# ── Turn signals ──────────────────────────────────────────────────────────

signal turn\_started(side: String)          \# "player" or "enemy"

signal turn\_ended(side: String)

\# ── Unit signals ──────────────────────────────────────────────────────────

signal unit\_moved(unit: Unit)

signal unit\_fired(unit: Unit, shot: ShotDefinition)

signal unit\_hit\_dealt(unit: Unit, target: Unit, damage: int, element: String)

signal unit\_hit\_taken(unit: Unit, damage: int, element: String, source: Unit)

signal unit\_killed(unit: Unit, killer: Unit)

signal unit\_died(unit: Unit)

signal unit\_tile\_entered(unit: Unit, tile\_pos: Vector2i)

\# ── Status signals ─────────────────────────────────────────────────────────

signal status\_applied(target: Unit, status\_id: String, stacks: int)

signal status\_removed(target: Unit, status\_id: String)

signal status\_ticked(target: Unit, status\_id: String, stacks: int)

\# ── Terrain signals ────────────────────────────────────────────────────────

signal tile\_damaged(col: int, row: int, dmg: int, remaining\_hp: int)

signal tile\_destroyed(col: int, row: int, tile\_type: int)

signal tile\_changed(col: int, row: int)

signal tile\_status\_applied(col: int, row: int, status\_id: String)

signal tile\_status\_removed(col: int, row: int, status\_id: String)

signal tile\_status\_ticked(col: int, row: int, status\_id: String)

\# ── Projectile signals ─────────────────────────────────────────────────────

signal projectile\_impact(world\_pos: Vector2, impact\_voxel: Vector2i, element: String)

signal aoe\_resolved(center: Vector2i, radius: int, affected\_tiles: Array)

⚠ Every signal that existed in M2 as a direct call or local signal must be migrated to `EventBus` in M3. This is refactor work, not new feature work, but it is mandatory — the status and element systems depend on it.

### 2.2 Features Autoload

\# res://autoloads/features.gd

extends Node

\# Systems — disable to make the system go dormant entirely

@export var elements\_enabled        : bool \= true

@export var tile\_statuses\_enabled   : bool \= true

@export var unit\_statuses\_enabled   : bool \= true

\# Content flags — disable specific effects without touching system code

@export var fire\_enabled            : bool \= true

@export var electric\_enabled        : bool \= true

@export var burning\_tile\_enabled    : bool \= true

@export var electrified\_tile\_enabled: bool \= true

\# Future systems — false until implemented

@export var wind\_enabled            : bool \= false

@export var keywords\_enabled        : bool \= false

@export var card\_deck\_enabled       : bool \= false

**Usage pattern — check at system entry point, not inside logic:**

\# Good — checked once at the entry point of the element resolver

func apply\_element(unit: Unit, element: String, damage: int) \-\> void:

    if not Features.elements\_enabled: return

    ...

\# Bad — checked deep inside a helper; harder to reason about

func \_apply\_burn\_stacks(unit: Unit) \-\> void:

    if not Features.fire\_enabled: return   \# don't do this inside status logic

---

## 3\. Element System

### 3.1 ElementDef Resource

\# res://data/elements/element\_def.gd

class\_name ElementDef

extends Resource

@export var id              : String \= ""

@export var display\_name    : String \= ""

\#\# Unit status applied on hit (reference to StatusEffectDef)

@export var unit\_status     : StatusEffectDef \= null

\#\# Tile status applied on hit (reference to TileStatusDef)

@export var tile\_status     : TileStatusDef \= null

\#\# Unit tag this element is strong against (×1.5 damage)

@export var strong\_vs\_tag   : String \= ""

\#\# Unit tag this element is weak against (×0.5 damage)

@export var weak\_vs\_tag     : String \= ""

\#\# Special multiplier vs SHIELDED tag (0 \= not special)

@export var vs\_shielded\_mult: float \= 0.0

**M3 element definitions:**

\# res://data/elements/fire.tres

id              \= "fire"

display\_name    \= "Fire"

unit\_status     \= preload("res://data/statuses/burn.tres")

tile\_status     \= preload("res://data/tile\_statuses/burning.tres")

strong\_vs\_tag   \= "ORGANIC"        \# ×1.5 vs Bio/organic units

weak\_vs\_tag     \= ""

vs\_shielded\_mult= 0.0

\# res://data/elements/electric.tres

id              \= "electric"

display\_name    \= "Electric"

unit\_status     \= preload("res://data/statuses/shock.tres")

tile\_status     \= preload("res://data/tile\_statuses/electrified.tres")

strong\_vs\_tag   \= "MECHANICAL"     \# ×1.5 vs Cell/mechanical units

weak\_vs\_tag     \= ""

vs\_shielded\_mult= 2.0              \# ×2 vs SHIELDED tag

### 3.2 Element Field on AoEGroup

Add one field to the existing `AoEGroup` resource:

\# Addition to res://data/shots/aoe\_group.gd

@export var element : ElementDef \= null   \# null \= physical (no element)

Each ring in an AoE pattern can now carry its own element. Inner ring fire, outer ring physical is a valid pattern for later content. In M3, all groups in a fire shell carry fire.

### 3.3 Affinity Table on UnitDefinition

\# Addition to res://data/units/unit\_definition.gd

\#\# Unit structural tags used by element and keyword systems

\#\# Valid values: ORGANIC, MECHANICAL, SHIELDED, HEAVY, FLYING

@export var tags : Array\[String\] \= \[\]

\#\# Element affinity overrides. Key \= element id, value \= damage multiplier.

\#\# If an element id is not present, multiplier defaults to 1.0.

\#\# Example: { "fire": 1.5, "electric": 0.5 }

@export var element\_affinities : Dictionary \= {}

**M3 unit affinity assignments:**

| Unit | Tags | fire | electric |
| :---- | :---- | :---- | :---- |
| player\_heavy | `[]` | 1.0 | 1.0 |
| player\_light | `[]` | 1.0 | 1.0 |
| enemy\_organic | `["ORGANIC"]` | 1.5 | 0.75 |
| enemy\_mechanical | `["MECHANICAL"]` | 0.75 | 1.5 |

### 3.4 Element Resolution in AoEResolver

Extend the existing `resolve()` function to apply element effects after damage:

\# Extension to res://systems/aoe\_resolver.gd

static func resolve(terrain: TerrainManager, units: Array,

                    origin: Vector2i, pattern: AoEPattern,

                    is\_enemy: bool) \-\> void:

    if not Features.elements\_enabled:

        \_resolve\_physical(terrain, units, origin, pattern, is\_enemy)

        return

    var aoe\_map := pattern.to\_map()

    for offset in aoe\_map:

        var target  : Vector2i \= origin \+ offset

        var group   : AoEGroup \= aoe\_map\[offset\]

        var element : ElementDef \= group.element

        \# Terrain damage (physical component always applies)

        terrain.damage\_tile(target.x, target.y, group.damage)

        \# Apply tile status if element has one

        if element and element.tile\_status and Features.tile\_statuses\_enabled:

            TileStatusSystem.apply(terrain, target, element.tile\_status)

        \# Unit damage with affinity

        for unit in units:

            if not \_should\_damage(unit, is\_enemy): continue

            if not \_voxel\_in\_bbox(target, unit): continue

            var final\_dmg := \_calc\_damage(unit, group.damage, element)

            unit.take\_damage(final\_dmg)

            EventBus.unit\_hit\_taken.emit(unit, final\_dmg,

                element.id if element else "physical", null)

            \# Apply unit status if element has one

            if element and element.unit\_status and Features.unit\_statuses\_enabled:

                UnitStatusSystem.apply(unit, element.unit\_status, 1\)

static func \_calc\_damage(unit: Unit, base\_dmg: int,

                          element: ElementDef) \-\> int:

    if element \== null: return base\_dmg

    var mult : float \= 1.0

    \# Check element's strong/weak tags against unit tags

    if element.strong\_vs\_tag \!= "" \\

    and element.strong\_vs\_tag in unit.definition.tags:

        mult \*= 1.5

    if element.weak\_vs\_tag \!= "" \\

    and element.weak\_vs\_tag in unit.definition.tags:

        mult \*= 0.5

    \# SHIELDED override

    if element.vs\_shielded\_mult \> 0.0 \\

    and "SHIELDED" in unit.definition.tags:

        mult \*= element.vs\_shielded\_mult

    \# Unit-specific affinity override (takes precedence over tag rules)

    if element.id in unit.definition.element\_affinities:

        mult \= unit.definition.element\_affinities\[element.id\]

    return max(1, int(base\_dmg \* mult))

---

## 4\. Unit Status Effect System

### 4.1 StatusEffectDef Resource

\# res://data/statuses/status\_effect\_def.gd

class\_name StatusEffectDef

extends Resource

@export var id          : String        \= ""

@export var display\_name: String        \= ""

@export var max\_stacks  : int           \= 3

@export var duration    : int           \= 2    \# turns; \-1 \= permanent for stage

\#\# Damage dealt per stack per tick (applied at tick phase)

@export var tick\_damage : int           \= 0

\#\# Action point reduction per stack per turn (applied to shared pool)

@export var ap\_reduction: int           \= 0

\#\# Tags on this status; used by cleanse and interaction rules

\#\# Valid values: FIRE, ELECTRIC, POISON, SPREADABLE, ORGANIC

@export var tags        : Array\[String\] \= \[\]

\#\# Status that cleanses this one on application (e.g. fire cleanses chill)

@export var cleansed\_by\_element: String \= ""

**M3 status definitions:**

\# res://data/statuses/burn.tres

id           \= "burn"

display\_name \= "Burn"

max\_stacks   \= 3

duration     \= 2

tick\_damage  \= 1      \# 1 dmg per stack per tick \= up to 3 dmg/turn at max stacks

ap\_reduction \= 0

tags         \= \["FIRE"\]

\# res://data/statuses/shock.tres

id           \= "shock"

display\_name \= "Shock"

max\_stacks   \= 3

duration     \= 1

tick\_damage  \= 0

ap\_reduction \= 1      \# reduces shared action pool by 1 per stack

tags         \= \["ELECTRIC"\]

### 4.2 StatusInstance Runtime Object

\# res://systems/status\_instance.gd

class\_name StatusInstance

extends RefCounted

var definition  : StatusEffectDef

var stacks      : int \= 1

var turns\_left  : int

func \_init(def: StatusEffectDef, initial\_stacks: int \= 1\) \-\> void:

    definition \= def

    stacks     \= initial\_stacks

    turns\_left \= def.duration

func apply\_stacks(n: int) \-\> void:

    \#\# Add stacks up to cap; refresh duration regardless

    stacks     \= min(stacks \+ n, definition.max\_stacks)

    turns\_left \= definition.duration

func tick() \-\> bool:

    \#\# Returns true if status should be removed after this tick

    turns\_left \-= 1

    return turns\_left \<= 0

### 4.3 UnitStatusSystem

\# res://systems/unit\_status\_system.gd

\# Autoload or static class — no instance state

static func apply(unit: Unit, def: StatusEffectDef, stacks: int \= 1\) \-\> void:

    if not Features.unit\_statuses\_enabled: return

    \# Check if unit already has this status

    if unit.active\_statuses.has(def.id):

        unit.active\_statuses\[def.id\].apply\_stacks(stacks)

    else:

        var instance := StatusInstance.new(def, stacks)

        unit.active\_statuses\[def.id\] \= instance

    EventBus.status\_applied.emit(unit, def.id, stacks)

static func tick\_all(unit: Unit) \-\> void:

    \#\# Called at the correct phase for this unit's side

    var to\_remove : Array\[String\] \= \[\]

    var total\_ap\_reduction : int  \= 0

    var total\_tick\_damage  : int  \= 0

    for id in unit.active\_statuses:

        var inst : StatusInstance \= unit.active\_statuses\[id\]

        var def  : StatusEffectDef \= inst.definition

        \# Accumulate effects — damage statuses before healing (see resolution order)

        total\_tick\_damage  \+= def.tick\_damage  \* inst.stacks

        total\_ap\_reduction \+= def.ap\_reduction \* inst.stacks

        EventBus.status\_ticked.emit(unit, id, inst.stacks)

        if inst.tick():

            to\_remove.append(id)

    \# Apply accumulated damage

    if total\_tick\_damage \> 0:

        unit.take\_damage(total\_tick\_damage)

    \# Apply AP reduction to shared pool this turn

    if total\_ap\_reduction \> 0:

        CombatManager.action\_bar.spend(total\_ap\_reduction)

    \# Remove expired statuses

    for id in to\_remove:

        unit.active\_statuses.erase(id)

        EventBus.status\_removed.emit(unit, id)

static func cleanse\_by\_element(unit: Unit, element\_id: String) \-\> void:

    \#\# Remove all statuses that list this element in cleansed\_by\_element

    var to\_remove : Array\[String\] \= \[\]

    for id in unit.active\_statuses:

        var def : StatusEffectDef \= unit.active\_statuses\[id\].definition

        if def.cleansed\_by\_element \== element\_id:

            to\_remove.append(id)

    for id in to\_remove:

        unit.active\_statuses.erase(id)

        EventBus.status\_removed.emit(unit, id)

### 4.4 Unit Scene Changes

Add to `unit.gd`:

\#\# Active status instances. Key \= status id, value \= StatusInstance.

var active\_statuses : Dictionary \= {}

---

## 5\. Tile Status Effect System

### 5.1 TileStatusDef Resource

\# res://data/tile\_statuses/tile\_status\_def.gd

class\_name TileStatusDef

extends Resource

@export var id              : String        \= ""

@export var display\_name    : String        \= ""

@export var duration        : int           \= 3       \# turns; \-1 \= permanent

\#\# Damage dealt to units touching this tile per tick

@export var tick\_damage     : int           \= 1

\#\# Element of the tick damage

@export var tick\_element    : ElementDef    \= null

\#\# Tags on this tile status; used by spread and cleanse rules

@export var tags            : Array\[String\] \= \[\]

\#\# Tile tag required on neighbour for spread (empty \= no spread)

@export var spreads\_to\_tag  : String        \= ""

\#\# Tile tag that instantly removes this status on contact

@export var removed\_by\_tag  : String        \= ""

**M3 tile status definitions:**

\# res://data/tile\_statuses/burning.tres

id            \= "burning"

display\_name  \= "Burning"

duration      \= 3

tick\_damage   \= 1

tick\_element  \= preload("res://data/elements/fire.tres")

tags          \= \["SPREADABLE", "FIRE"\]

spreads\_to\_tag= "FLAMMABLE"

removed\_by\_tag= "LIQUID"

\# res://data/tile\_statuses/electrified.tres

id            \= "electrified"

display\_name  \= "Electrified"

duration      \= 2

tick\_damage   \= 1

tick\_element  \= preload("res://data/elements/electric.tres")

tags          \= \["CHAIN", "ELECTRIC"\]

spreads\_to\_tag= ""           \# chains instantly (handled separately), does not spread

removed\_by\_tag= ""

### 5.2 TileStatusInstance

\# res://systems/tile\_status\_instance.gd

class\_name TileStatusInstance

extends RefCounted

var definition : TileStatusDef

var turns\_left : int

func \_init(def: TileStatusDef) \-\> void:

    definition \= def

    turns\_left \= def.duration

func tick() \-\> bool:

    turns\_left \-= 1

    return turns\_left \<= 0

### 5.3 TileStatusSystem

\# res://systems/tile\_status\_system.gd

static func apply(terrain: TerrainManager, pos: Vector2i,

                  def: TileStatusDef) \-\> void:

    if not Features.tile\_statuses\_enabled: return

    var tile := terrain.get\_tile(pos.x, pos.y)

    if tile \== null: return

    \# Check removed\_by\_tag — if tile has the removing tag, status cannot apply

    if def.removed\_by\_tag \!= "" and tile.has\_flag\_tag(def.removed\_by\_tag): return

    \# Already has this status — just refresh duration

    if tile.tile\_statuses.has(def.id):

        tile.tile\_statuses\[def.id\].turns\_left \= def.duration

        return

    tile.tile\_statuses\[def.id\] \= TileStatusInstance.new(def)

    terrain.mark\_chunk\_dirty(pos.x, pos.y)

    EventBus.tile\_status\_applied.emit(pos.x, pos.y, def.id)

static func tick\_all(terrain: TerrainManager, units: Array) \-\> void:

    \#\# Called once per round at round start, before player turn

    for col in range(MAP\_WIDTH):

        for row in range(MAP\_HEIGHT):

            var tile := terrain.get\_tile(col, row)

            if tile \== null or tile.tile\_statuses.is\_empty(): continue

            \_tick\_tile(terrain, units, Vector2i(col, row), tile)

static func \_tick\_tile(terrain: TerrainManager, units: Array,

                        pos: Vector2i, tile: Tile) \-\> void:

    var to\_remove : Array\[String\] \= \[\]

    for id in tile.tile\_statuses:

        var inst : TileStatusInstance \= tile.tile\_statuses\[id\]

        var def  : TileStatusDef      \= inst.definition

        \# Damage units whose bounding box touches this tile

        for unit in units:

            if AoEResolver.\_voxel\_in\_bbox(pos, unit):

                var dmg := AoEResolver.\_calc\_damage(unit, def.tick\_damage,

                                                    def.tick\_element)

                unit.take\_damage(dmg)

                if def.tick\_element:

                    UnitStatusSystem.apply(unit, def.tick\_element.unit\_status, 1\)

        \# Spread

        if def.spreads\_to\_tag \!= "":

            \_spread(terrain, pos, inst)

        \# Electric chain (instant, not spread)

        if "CHAIN" in def.tags:

            \_chain\_electric(terrain, units, pos, def)

        EventBus.tile\_status\_ticked.emit(pos.x, pos.y, id)

        if inst.tick():

            to\_remove.append(id)

    for id in to\_remove:

        tile.tile\_statuses.erase(id)

        terrain.mark\_chunk\_dirty(pos.x, pos.y)

        EventBus.tile\_status\_removed.emit(pos.x, pos.y, id)

static func \_spread(terrain: TerrainManager, pos: Vector2i,

                    inst: TileStatusInstance) \-\> void:

    var def := inst.definition

    \#\# Check 4 orthogonal neighbours; apply status to FLAMMABLE ones

    for offset in \[Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)\]:

        var npos  := pos \+ offset

        var ntile := terrain.get\_tile(npos.x, npos.y)

        if ntile \== null: continue

        if ntile.has\_flag\_tag(def.spreads\_to\_tag):

            apply(terrain, npos, def)

static func \_chain\_electric(terrain: TerrainManager, units: Array,

                              origin: Vector2i, def: TileStatusDef) \-\> void:

    \#\# Instantly chain electric damage through all CONDUCTIVE tiles

    \#\# touching the origin tile, then to units touching those tiles

    var visited : Array\[Vector2i\] \= \[origin\]

    var queue   : Array\[Vector2i\] \= \[origin\]

    while not queue.is\_empty():

        var current := queue.pop\_front()

        for offset in \[Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)\]:

            var npos  := current \+ offset

            if npos in visited: continue

            var ntile := terrain.get\_tile(npos.x, npos.y)

            if ntile \== null: continue

            if not ntile.has\_flag\_tag("CONDUCTIVE"): continue

            visited.append(npos)

            queue.append(npos)

            \# Damage units touching this conductive tile

            for unit in units:

                if AoEResolver.\_voxel\_in\_bbox(npos, unit):

                    unit.take\_damage(def.tick\_damage)

### 5.4 Tile Data Changes

Add to `Tile`:

\#\# Active tile status instances. Key \= status id, value \= TileStatusInstance.

var tile\_statuses : Dictionary \= {}

\#\# String tags for tile status interaction (FLAMMABLE, CONDUCTIVE, LIQUID, etc.)

\#\# Distinct from the integer flags bitmask — these are semantic tags for status rules.

var status\_tags   : Array\[String\] \= \[\]

func has\_flag\_tag(tag: String) \-\> bool:

    return tag in status\_tags

**M3 default tag assignments:**

| Tile type | `status_tags` |
| :---- | :---- |
| SOLID (standard) | `["FLAMMABLE"]` |
| SOLID (reinforced) | `[]` (does not burn) |
| LIQUID | `["LIQUID"]` |
| RUBBLE | `["FLAMMABLE", "CONDUCTIVE"]` |

⚠ `status_tags` is a separate concept from the integer `flags` bitmask defined in the terrain spec. The bitmask governs gameplay properties (climbable, passable, indestructible). `status_tags` governs status interaction rules. They are different axes and should not be merged.

---

## 6\. Resolution Order

Resolution order is fixed and must not change without a documented reason. Ambiguity in resolution order (does burn kill before regen heals?) makes the game feel random even when it isn't.

── Round start ─────────────────────────────────────────────────────────────

1\. Tile statuses tick

   a. Damage units touching burning/electrified tiles

   b. Burning spreads to FLAMMABLE neighbours

   c. Electric chains through CONDUCTIVE tiles

   d. Decrement durations; remove expired tile statuses

── Player turn ─────────────────────────────────────────────────────────────

2\. Player unit statuses tick (damage before healing within this phase)

   a. Burn stacks deal damage

   b. (Regen heals — M4+)

   c. Decrement durations; remove expired unit statuses

3\. Shock AP reduction applied to shared pool for this turn

4\. Player actions (move, fire, terrain tool)

   → on each action: EventBus signals fire → status/element systems respond

── Enemy turn ──────────────────────────────────────────────────────────────

5\. Enemy unit statuses tick (same order as step 2\)

6\. Shock AP reduction for enemy units (post-M2 when enemies have action pools)

7\. Enemy actions

── Round end ───────────────────────────────────────────────────────────────

8\. (Reserved for end-of-round effects — none in M3)

---

## 7\. Shot Definitions for M3

\# res://data/shots/fire\_shell.tres

id            \= "fire\_shell"

display\_name  \= "Fire Shell"

base\_speed    \= 580.0

gravity\_scale \= 1.0

action\_cost   \= 1          \# costs 1 action point (basic shell costs 0\)

aoe\_pattern   \= preload("res://data/shots/aoe/diamond\_r2\_fire.tres")

trajectory    \= ARC

\# res://data/shots/aoe/diamond\_r2\_fire.tres

\# Same offsets as diamond\_r2 but all groups carry element \= fire

\# group\_0: offsets=\[(0,0)\]                       damage=3  element=fire

\# group\_1: offsets=\[(0,-1),(0,1),(1,0),(-1,0)\]   damage=2  element=fire

\# group\_2: offsets=\[ring 2 offsets\]              damage=1  element=fire

\# res://data/shots/electric\_shell.tres

id            \= "electric\_shell"

display\_name  \= "Electric Shell"

base\_speed    \= 650.0      \# slightly faster; electric \= high velocity feel

gravity\_scale \= 0.85       \# flatter arc

action\_cost   \= 1

aoe\_pattern   \= preload("res://data/shots/aoe/diamond\_r2\_electric.tres")

trajectory    \= ARC

⚠ Elemental shots cost 1 action point; the basic shell costs 0\. This establishes the pattern: free shot is always available, spending actions buys upgraded effects. Units start with only the basic shell equipped; elemental shells are available as a second shot option selected before firing. Shot selection UI is described in section 8\.

---

## 8\. Shot Selection UI (M3 Addition)

Players need to select which shot to fire before clicking to fire. M3 introduces a minimal shot selector — placeholder quality, functional.

**Interaction:**

- Selected unit shows 1–N shot icons in the HUD (one per available shot in `unit.available_shots`)  
- Player clicks a shot icon (or presses `1`, `2`, etc.) to set `unit.selected_shot`  
- Left-click to fire uses `unit.selected_shot`; defaults to `default_shot` if none selected  
- `available_shots` on `UnitDefinition` is an `Array[ShotDefinition]`; M3 player units have `[basic_shell, fire_shell, electric_shell]`

\# Addition to UnitDefinition

@export var available\_shots : Array\[ShotDefinition\] \= \[\]

\# default\_shot remains the always-available free shot

\# Addition to Unit runtime state

var selected\_shot : ShotDefinition \= null

func get\_active\_shot() \-\> ShotDefinition:

    return selected\_shot if selected\_shot \!= null else definition.default\_shot

---

## 9\. Enemy Unit Definitions for M3

Two new enemy definitions to test the affinity system. Both use M2 IK firing behavior unchanged.

\# res://data/units/enemy\_organic.tres

id             \= "enemy\_organic"

display\_name   \= "Brute"

width\_voxels   \= 2         height\_voxels \= 3

max\_hp         \= 8         move\_range    \= 0

tags           \= \["ORGANIC"\]

element\_affinities \= { "fire": 1.5, "electric": 0.75 }

default\_shot   \= preload("res://data/shots/basic\_shell.tres")

\# res://data/units/enemy\_mechanical.tres

id             \= "enemy\_mechanical"

display\_name   \= "Drone"

width\_voxels   \= 2         height\_voxels \= 3

max\_hp         \= 6         move\_range    \= 0

tags           \= \["MECHANICAL"\]

element\_affinities \= { "fire": 0.75, "electric": 1.5 }

default\_shot   \= preload("res://data/shots/basic\_shell.tres")

---

## 10\. M3 Test Scenario

A fixed test scenario to validate all M3 systems together. Hardcoded for reproducibility.

| Entity | Position | Definition |
| :---- | :---- | :---- |
| Player Unit 1 | Column 12, surface | `player_heavy` \+ fire shell \+ electric shell |
| Player Unit 2 | Column 15, surface | `player_light` \+ fire shell \+ electric shell |
| Enemy A | Column 250, surface | `enemy_organic` (weak to fire) |
| Enemy B | Column 260, surface | `enemy_mechanical` (weak to electric) |

**Validation checklist:**

- [ ] Fire shell on Enemy A deals 1.5× damage  
- [ ] Fire shell on Enemy A applies Burn; ticks 1 dmg/stack at turn start  
- [ ] Fire shell landing near terrain tiles sets them Burning (orange tint)  
- [ ] Burning tiles spread to adjacent FLAMMABLE tiles each round  
- [ ] Burning tile damages any unit standing on it  
- [ ] Electric shell on Enemy B deals 1.5× damage  
- [ ] Electric shell applies Shock; reduces shared AP by 1 next turn  
- [ ] Electrified tile chains through CONDUCTIVE neighbours instantly  
- [ ] Basic shell on either enemy deals 1.0× damage (no element bonus)  
- [ ] Shock AP reduction shows correctly on action bar  
- [ ] Stack badge shows on unit when Burn or Shock is active  
- [ ] Features.elements\_enabled \= false makes all shots deal physical damage only

---

## 11\. File Layout Changes

res://

  autoloads/

    event\_bus.gd          NEW

    features.gd           NEW

  data/

    elements/

      element\_def.gd      NEW

      fire.tres            NEW

      electric.tres        NEW

    statuses/

      status\_effect\_def.gd NEW

      burn.tres            NEW

      shock.tres           NEW

    tile\_statuses/

      tile\_status\_def.gd   NEW

      burning.tres         NEW

      electrified.tres     NEW

    shots/

      aoe/

        diamond\_r2.tres            (existing)

        diamond\_r2\_fire.tres       NEW

        diamond\_r2\_electric.tres   NEW

      basic\_shell.tres             (existing)

      fire\_shell.tres              NEW

      electric\_shell.tres          NEW

    units/

      player\_heavy.tres            UPDATED (tags, available\_shots, affinities)

      player\_light.tres            UPDATED

      enemy\_static.tres            (existing, unchanged)

      enemy\_organic.tres           NEW

      enemy\_mechanical.tres        NEW

  systems/

    aoe\_resolver.gd        UPDATED (element resolution)

    unit\_status\_system.gd  NEW

    tile\_status\_system.gd  NEW

    status\_instance.gd     NEW

    tile\_status\_instance.gd NEW

  units/

    unit.gd                UPDATED (active\_statuses, available\_shots, selected\_shot)

  terrain/

    tile.gd                UPDATED (tile\_statuses, status\_tags, has\_flag\_tag)

---

## 12\. Deferred to Post-M3

| System | Why deferred | Architecture note |
| :---- | :---- | :---- |
| Freeze, Corrosive, Resonant elements | Content only; no new architecture needed | Add `ElementDef` `.tres` files; add `StatusEffectDef` for Chill/Frozen/Corrode |
| Chill, Frozen, Corrode, Goo, Shield, Regen statuses | Same architecture as Burn/Shock | Add `.tres` definitions; add cleanse interactions via `cleansed_by_element` field |
| Wind system (tile status displacement) | Requires displacement verb; `SPREADABLE` tag is ready | New `WindSystem` autoload; subscribes to `turn_started`; displaces `SPREADABLE` statuses |
| Keyword system (Piercing, Bouncing, etc.) | Needs stable trigger list first | `KeywordDef` resource; hooks into `EventBus` triggers from section 1.1 |
| RUBBLE tile behavior | Still produces VOID on destruction | Change `_destroy_tile()` in `TerrainManager` to place RUBBLE; add RUBBLE `status_tags` |
| Enemy AI improvements | M2 IK firing still sufficient | No architectural conflict; AI reads `EventBus` same as everything else |
| Card / action deck | Deliberately open | `on_card_played` trigger already accommodated by `EventBus` pattern |
| Faction-specific mechanics | Post-M3 design pass needed | Keywords (Scavenger, Networked, Entrenched) are the implementation vehicle |

