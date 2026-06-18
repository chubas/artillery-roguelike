# Artillery Space — Effects, Keywords and Interaction System

**Design Brainstorm and System Foundation · v0.1**

A catalogue of candidate effects and the architectural rules that let them interact without pairwise design.

---

## 1\. System Design Principles

This document is a catalogue of candidate effects and the rules for how they interact. Most entries will not be implemented soon, and some never will. The purpose is to design the system logic so any of them can be added, tested, and removed cheaply — and so interactions emerge from shared rules rather than hand-written pairs.

**★ Effects are verbs that operate on tags, never on other specific effects.**

Fire does not know about wind. Wind does not know about fire. Fire is a tile status carrying the `SPREADABLE` tag; wind is a system that displaces things carrying `SPREADABLE` (and projectiles, and gas). Their interaction is a consequence of the tags, not a coded pair. Every interaction in this document follows this pattern. If a proposed effect requires knowing about another specific effect by name, redesign it.

**★ Three substrates carry all state: tiles, units, and projectiles.**

Every effect ultimately reads or writes one of these three. Tile statuses (burning, electrified, gooed), unit statuses (burn stacks, shock, shield), projectile properties (element, trajectory flags). Systems operate on substrates; substrates do not operate on each other.

**★ Definitions are immutable and shared; instances are per-target and mutable.**

A `StatusEffect` resource defines what Burn *is* (tags, tick damage, max stacks). A `StatusInstance` on a unit tracks *this unit's* burn (current stacks, remaining turns). Definitions live in `.tres` files; instances are runtime objects. The sandbox tools spawn instances from definitions.

**★ Every effect must be visually expressible on the voxel grid.**

If an effect cannot be shown as a tile overlay, unit badge, or projectile trail, it will be illegible in play. Legibility is a design gate: an effect that cannot be communicated visually is rejected regardless of how interesting it is mechanically.

**★ Feature flags gate systems, not content.**

A `Features` autoload holds booleans per system (`elements_enabled`, `wind_enabled`, `terrain_status_enabled`). Systems check their flag at their entry point and go dormant when disabled. Content (a fire shot definition) can exist while its system (elements) is flagged off — the shot simply behaves as elementless.

---

## 2\. Vocabulary

Shared language used throughout. Locking the vocabulary early prevents the system from sprawling.

| Term | Definition | Example |
| :---- | :---- | :---- |
| **Element** | A damage type carried by shots and AoE groups | Fire, Electric, Freeze, Corrosive |
| **Status effect** | A persistent condition on a unit or tile with per-turn behavior | Burn (unit), Burning (tile), Shock, Goo |
| **Keyword** | A named, reusable rule attached to shots, units, or upgrades | Piercing, Volatile, Anchored |
| **Trigger** | An event that activates an ability | `on_kill`, `on_death`, `on_turn_start` |
| **Tag** | A label on a status/tile/unit that systems use to decide whether they act on it | `SPREADABLE`, `CONDUCTIVE`, `ORGANIC`, `MECHANICAL` |
| **Affinity** | A unit's damage multiplier vs. an element | Bio: fire ×1.5, electric ×0.5 |
| **Tick** | The per-turn resolution moment when statuses act | Burn ticks at turn start |

---

## 3\. Elements

Elements are properties of damage, carried on `AoEGroup`s. A shot can carry different elements on different rings (inner ring fire, outer ring physical). Units have affinity multipliers per element, defined in `UnitDefinition`. Affinities are the racial identity layer: Shamans (Bio) fear fire; Awakened (Cell) fear electric.

| Element | Damage behavior | Applies status | Terrain interaction | Phase |
| :---- | :---- | :---- | :---- | :---- |
| Physical | Baseline; no multipliers beyond armor | None | Destroys tiles normally | M2 ✓ |
| Fire | ×1.5 vs `ORGANIC` tag | Burn (unit), Burning (tile) | Ignites `FLAMMABLE` tiles; spreads via `SPREADABLE` | M3 |
| Electric | ×1.5 vs `MECHANICAL` tag; ×2 vs `SHIELDED` | Shock | Chains through `CONDUCTIVE` tiles to all touching units | M3 |
| Freeze | ×0.75 damage but always applies status | Chill / Frozen | Turns `LIQUID` tiles solid (walkable ice, melts in N turns) | M4+ |
| Corrosive | Ignores armor entirely | Corrode (armor shred) | Converts `SOLID` to weakened (HP halved); eats `RUBBLE` | M4+ |
| Resonant | Wildcard — reserved for Resonance lore tie-in | TBD | TBD — interacts with crystal tiles | Future |

⚠ Implement Fire and Electric first (M3). They exercise the two interaction paths — status application and terrain chaining — and they map directly to the two racial weaknesses already designed. Freeze and Corrosive add no new architecture, only new content.

---

## 4\. Unit Status Effects

Statuses on units tick at the unit owner's turn start. All statuses stack to a cap of 3 unless stated otherwise; stacks are shown as a counter badge on the unit. Re-application at cap refreshes duration.

| Status | Per-stack effect | Duration | Cleansed by | Phase |
| :---- | :---- | :---- | :---- | :---- |
| **Burn** | 1 dmg per stack at turn start | 2 turns | Entering `LIQUID` tile; Cleanse keyword | M3 |
| **Shock** | −1 action point contribution per stack (squad pool) | 1 turn | Grounded keyword; turn end | M3 |
| **Chill** | −1 move range per stack | 2 turns | Fire damage (converts to 1 burn) | M4+ |
| **Frozen** | Cannot act (move or fire); replaces 3 Chill stacks | 1 turn | Any damage breaks it (takes ×1.5) | M4+ |
| **Corrode** | −1 armor per stack (can go negative \= bonus damage taken) | Permanent for stage | Repair action | M4+ |
| **Goo** | Move cost ×2; cannot climb | Until leaves goo or 2 turns | Fire damage (burns off, deals 1 dmg) | M4+ |
| **Shield** | Absorbs N damage before HP; not a stack — a pool | Until depleted | Electric ×2 vs shield pool | M4+ |
| **Regen** | Heal 1 per stack at turn start | 2 turns | Corrosive damage removes all stacks | M4+ |
| **Anchor** | Cannot be displaced (push/pull immune); cannot move | Until removed | Voluntary or dispel | M5+ |
| **Marked** | Next hit vs this unit \+50% damage; consumed on hit | Until consumed | Consumed on hit | M5+ |

⚠ Shock reducing the **shared** action pool (not per-unit actions) is a deliberate choice: it makes crowd-shocking a real strategy and creates a felt cost even when the shocked unit was not going to act. Revisit if it feels unfair in testing.

---

## 5\. Tile Status Effects

Tiles can carry statuses — this is the terrain-as-actor layer. Tile statuses tick at the start of each full round (before player turn). They are rendered as overlays on the tile.

| Tile status | Effect | Spread / decay | Tags | Phase |
| :---- | :---- | :---- | :---- | :---- |
| **Burning** | 1 fire dmg to any unit whose bbox touches tile; ignites `FLAMMABLE` neighbors | Spreads 1 tile/turn to `FLAMMABLE`; dies after 3 turns or on `LIQUID` contact | `SPREADABLE` | M3 |
| **Electrified** | 1 electric dmg to units touching; chains to `CONDUCTIVE` neighbors instantly | Decays after 2 turns | `CHAIN` | M3 |
| **Gooed** | Applies Goo status to units entering/standing | Spreads 1 tile per 2 turns if source remains; cleaned by fire | `SPREADABLE`, `ORGANIC` | M4+ |
| **Frozen surface** | `LIQUID` rendered walkable; slippery (move \+1 in same direction, no stop) | Melts in 3 turns; instantly on fire | `TEMPORARY` | M4+ |
| **Weakened** | Tile HP halved (corrosive aftermath); crumbles if stepped on by `HEAVY` unit | Permanent for stage | `STRUCTURAL` | M4+ |
| **Crystallized** | Resonance lore tie-in — reserved | TBD | `RESONANT` | Future |

---

## 6\. Keywords

Keywords are named, reusable rules. They attach to shots, units, or upgrades and are displayed as labelled chips in tooltips. A keyword is implemented once and reused everywhere. If a behavior will appear on more than one item, it must be a keyword, not bespoke logic.

### 6.1 Shot Keywords

| Keyword | Rule | Phase |
| :---- | :---- | :---- |
| **Piercing** | Projectile passes through first N tiles hit, detonates on N+1 or on unit contact | M4 |
| **Bouncing** | Reflects off terrain faces up to N times; detonates on unit contact or final bounce | M4 |
| **Heavy** | Immune to wind and deflection fields | M4+ |
| **Cluster** | On impact, spawns N sub-projectiles with smaller AoE patterns | M4+ |
| **Delayed** | Lands inert; detonates after N turns; visible countdown on tile | M4+ |
| **Seeking** | Trajectory curves up to X degrees toward nearest enemy in flight | M5+ |
| **Burrowing** | Travels through up to N tiles of terrain before detonating | M5+ |
| **Volatile** | AoE pattern doubled but unit takes 1 self-damage on firing | M5+ |

### 6.2 Unit Keywords

| Keyword | Rule | Phase |
| :---- | :---- | :---- |
| **Grounded** | Immune to Shock; cannot be displaced by push effects | M4+ |
| **Climber** | Climbs 2-voxel heights at no extra cost | M4 |
| **Flying** | Ignores terrain for movement; lands to fire; cannot benefit from cover | M5+ |
| **Sturdy** | First hit each turn deals −1 damage (min 1\) | M4+ |
| **Volatile** | On death, detonates own AoE pattern at own position | M4 |
| **Scavenger** | On kill, restore 1 HP (Bio identity hook) | M4 |
| **Networked** | \+1 damage while adjacent to another `NETWORKED` unit (Cell identity hook) | M5+ |
| **Entrenched** | \+1 armor while unit has not moved this turn (Army identity hook) | M4+ |

---

## 7\. Triggers

Triggers are the event hooks abilities attach to. The trigger list is the contract between the `EventBus` and the ability system — every trigger below corresponds to exactly one `EventBus` signal. Adding a trigger means adding a signal; nothing else changes.

| Trigger | Fired when | Example ability |
| :---- | :---- | :---- |
| `on_turn_start` | Unit's side begins its turn | Regen ticks; Burn ticks |
| `on_turn_end` | Unit's side ends its turn | Entrenched check; status duration decrement |
| `on_fire` | Unit fires any shot | Volatile self-damage |
| `on_hit_dealt` | Unit's projectile damages an enemy | Marked consumption; on-hit riders |
| `on_hit_taken` | Unit receives damage | Sturdy reduction; shield depletion |
| `on_kill` | Unit's damage reduces an enemy to 0 | Scavenger heal; Bio momentum stack |
| `on_death` | Unit reaches 0 HP | Volatile detonation; Cell resource drop |
| `on_move` | Unit completes a move step | Goo application; slippery slide |
| `on_terrain_destroyed` | A tile is destroyed by this unit's shot | Scrap generation; Bio momentum |
| `on_status_applied` | Any status lands on this unit | Grounded immunity check |
| `on_tile_entered` | Unit's bbox newly overlaps a tile | Tile status application (goo, burning) |

---

## 8\. Interaction Rules (The Emergence Layer)

No interaction below is coded as a pair. Each is a consequence of one system acting on one tag. This table is the proof of the architecture — the "Why it emerges" column is the implementation.

| Observed interaction | Why it emerges |
| :---- | :---- |
| Wind spreads fire | Wind system displaces `SPREADABLE` tile statuses; Burning has `SPREADABLE` |
| Rain extinguishes fire | Rain applies `LIQUID` contact; Burning dies on `LIQUID` contact |
| Fire burns off goo | Fire damage removes `ORGANIC` tile statuses; Gooed is `ORGANIC` |
| Electric chains through wet units | `LIQUID` contact adds `CONDUCTIVE` tag to units; Electric chains through `CONDUCTIVE` |
| Freeze \+ fire \= neither | Fire converts Chill stacks to Burn 1:1; Chill removal is a side effect of conversion, not a coded pair |
| Explosion in goo splatters it | AoE displacement moves `SPREADABLE` statuses to adjacent tiles; Gooed is `SPREADABLE` |
| Shock disables conductive armor | Electric ×2 vs `SHIELDED` is an affinity rule, not a shock-specific rule |
| Corrosive rain weakens the whole map | Rain applies its payload per tile; corrosive payload applies Weakened; no rain-corrosion pair exists |

**★ The test for any new effect:** describe its interactions using only tags and existing system verbs. If it needs a named exception, redesign it.

---

## 9\. Architecture Sketch

### 9.1 Core Pieces

\# Autoloads

EventBus      \# all gameplay signals; systems subscribe, never reference each other

Features      \# feature flags: elements\_enabled, wind\_enabled, tile\_status\_enabled...

\# Definition resources (immutable, .tres)

StatusEffectDef   \# id, tags, tick behavior params, max\_stacks, duration

KeywordDef        \# id, hook points, params

ElementDef        \# id, affinity table hooks, status it applies

\# Runtime instances (mutable, per-target)

StatusInstance    \# def reference \+ stacks \+ turns\_left; lives on Unit or Tile

### 9.2 Resolution Order (per round)

1\. Round start    → tile statuses tick (burning spreads, electrified decays)

2\. Player turn    → unit statuses tick for player units (burn, regen)

3\. Player actions → triggers fire as events occur

4\. Enemy turn     → unit statuses tick for enemy units, then enemy actions

5\. Round end      → durations decrement; expired statuses removed

⚠ Fixed resolution order is non-negotiable. Simultaneous resolution creates ambiguity (does burn kill before regen heals?). Damage statuses tick before healing statuses within the same phase — dying to burn before regen saves you is legible; the reverse feels random.

### 9.3 What M3 Implements

- `EventBus` autoload with the trigger signals from section 7  
- `Features` autoload with initial flags  
- `StatusEffectDef` \+ `StatusInstance` for units (Burn, Shock)  
- `ElementDef` for Fire and Electric; affinity table on `UnitDefinition`  
- Tile status framework with Burning and Electrified  
- Stack badges and tile overlays (placeholder visuals)

### 9.4 Deliberately Deferred

- Wind system (the displacement verb) — M4+; tags are ready for it  
- Freeze / Corrosive elements — content, not architecture  
- Keyword system — M4; triggers must be stable first  
- Resonant element and Crystallized tiles — awaits Resonance design

