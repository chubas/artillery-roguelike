# Artillery Space

General Design Specification

*Version 0.2 — Design Iteration*

*Items marked ◆ FLEXIBLE are design direction, not final decisions.*

---

# 1. Project Overview

Artillery Space is a single-player roguelite combining the strategic depth of deckbuilder roguelikes (Slay the Spire, Monster Train) with the spatial, physics-driven gameplay of artillery games (Gunbound, Cannon Brawl, Worms). The player commands a squad of units across a branching run structure, building their army through drafting and resource decisions, while engaging in turn-based artillery combat on destructible voxel terrain.

The defining tension: artillery skill is a difficulty layer on top of strategic decision-making, not a replacement for it. A player can engage primarily as a strategist and complete a run; the aiming and physics layer adds mastery depth for players who seek it.

Primary inspiration for the firing feel is Gunbound — unit variety, diverse projectile types, and shots that are tactically and physically distinct from one another, not just stat differences.

## 1.1 Core Design Pillars

* Destructible voxel terrain is a first-class resource, not scenery
* Army composition and upgrade decisions define run identity
* Path visibility enables meaningful preparation decisions
* Artillery skill is an optional difficulty layer, not a gate
* All mechanics are legible: hitboxes, AoE, and enemy intent are always visible
* Failure should always feel like a player mistake, never random cruelty

## 1.2 Target Platform and Engine

| Property | Value |
| :---- | :---- |
| Engine | Godot 4.x |
| Platform | PC (primary) |
| Perspective | 2D side-scrolling |
| Player count | Single player |
| Genre | Roguelite / Turn-based Artillery |

# 2. Milestone 1 — Prototype Scope

The first milestone is a focused technical prototype validating core voxel terrain and ballistic systems before any roguelite or meta-progression systems are built.

## 2.1 Milestone 1 Goals

1. Render a scrollable voxel terrain map with at least two tile types
2. Fire a ballistic projectile from a static unit position using mouse aim
3. Projectile follows arc physics (gravity applied per frame)
4. Projectile detects collision with terrain voxels on face contact (not corner)
5. Impact destroys voxels within a defined AoE radius (diamond pattern)
6. Voxel bounding boxes visible on hover and in targeting mode

## 2.2 Out of Scope for Milestone 1

* Enemy units or AI
* Unit movement or turn structure
* Roguelite meta-progression
* Multiple factions or unit types
* Resource systems
* Audio

# 3. Terrain System

*⚠  Full terrain specification is in the companion document: [Artillery Space — Terrain Specification](artillery-space-terrain-spec-v2.md).*

Terrain is composed of discrete square voxels on a uniform grid. Both terrain and units share the same voxel coordinate system, creating a unified spatial language for all gameplay calculations including AoE, line of sight, cover, and movement.

| Property | Decision |
| :---- | :---- |
| Grid type | Uniform square voxels |
| AoE shape | Diamond (Manhattan distance) as default; circular AoE is a named special property |
| Partial damage | Visual crack states only; HP is always an integer |
| Tile collapse | Tiles fall if unsupported (Terraria rule: no tile below AND no wall connection) |
| Tile identity | Each tile has: type, HP, element flags, bitmask flags (climbable, conductive, explosive, etc.) |
| Terrain as resource | Destroying terrain generates Scrap; terrain state is a strategic asset |

# 4. Firing System

## 4.1 Fire Input Method

*◆  FLEXIBLE: Final input method not decided. Two candidates:*

* Hold-to-charge then release: timing skill, creates drama at the moment of firing, rewards muscle memory
* Manual power setting: calculation skill, more deliberate, rewards spatial reasoning

A third option worth prototyping: oscillating power bar (Gunbound model) — bar fills and empties on a loop, player taps to lock power. Faster than hold-to-charge, adds rhythm, more forgiving on slight mistiming.

## 4.2 Preview Indicators

Preview mode is a difficulty modifier, not a binary game split. The following shows what each mode displays:

| Feature | Preview On | Preview Off |
| :---- | :---- | :---- |
| Firing arc / trajectory | Full arc ghost shown live | Hidden |
| AoE footprint | Shown before firing | Hidden |
| Unit hitbox highlight | Shown in targeting mode | Shown in targeting mode |
| Barrel direction indicator | Shown | Short line only |
| Enemy intent | Always shown | Always shown |

Partial preview variant (Peggle model): show only the first 40% of the arc trajectory. Experienced players extrapolate the rest. Clean difficulty axis without full removal.

## 4.3 Firing Modes

| Mode | Description | Blocked By |
| :---- | :---- | :---- |
| Direct arc | Standard ballistic arc. Needs clearance cone in firing direction. | Terrain in arc, low ceilings |
| High arc / mortar | Steep upward trajectory. Clears local terrain. | Ceiling / overhead terrain |
| Flat / direct | Low angle, high velocity. Long sightline required. | Any terrain in horizontal path |
| Terrain-bypass | Phases through terrain, hits units only. Rare. | Nothing (by design) |
| Bouncing | Ricochets off flat voxel faces. Angle is deterministic. | Absorbed tile types |
| Burrowing | Travels through terrain, damages from inside. | Void / empty space |

## 4.4 Shot Type Framework

Every unit shot type is defined by four axes. This creates a combinatorial design space rather than a list of one-offs:

| Axis | Options (examples) |
| :---- | :---- |
| Trajectory | Standard arc, flat/direct, mortar, guided, burrowing, orbital |
| Payload | Instant AoE, delayed, persistent zone, fragmentation, terrain-only, unit-only, healing, anchoring |
| Charge interaction | Standard, split threshold, vertical amplifier, fixed power, inverse (drop-shot) |
| Environmental | Wind affected, wind immune, bounces, absorbs terrain mass, conductive trigger, incendiary |

## 4.5 On RNG in Execution

Execution RNG (shot deviation, damage variance) is intentionally avoided. It decouples player skill from outcome and generates unfair-feeling moments. RNG in Artillery Space lives in setup (terrain generation, enemy composition, stage hazards) and planning (what units/upgrades appear), never in the execution of a player action.

The one acceptable execution variance: enemy behavior selection from their behavior deck, which creates variety without invalidating player skill.

# 5. Unit System

## 5.1 Unit Proportions and Hitboxes

Units are defined in voxel units. Standard unit is 3 voxels tall. Width varies by class. Hitboxes are axis-aligned bounding boxes in whole voxels — no sub-voxel precision. A hit on any bounding box voxel registers as a hit on the unit. Hitboxes are visualized as highlighted voxel overlays during targeting.

| Class | Width | Height | Notes |
| :---- | :---- | :---- | :---- |
| Light / infantry | 1 voxel | 3 voxels | Smallest hitbox, highest mobility |
| Standard | 2 voxels | 3 voxels | Baseline reference |
| Heavy / vehicle | 3–4 voxels | 3 voxels | Large hitbox, harder to miss |
| Support | 2 voxels | 2 voxels | Shorter profile, easier to hide in cover |

## 5.2 Movement and Climbing

| Action | Cost | Notes |
| :---- | :---- | :---- |
| Move 1 tile (flat) | 1 movement point | Base movement |
| Climb 1 voxel height | 1 movement point | Free; treated as flat |
| Climb 2 voxel height | 2 movement points | Costs extra; some units restricted |
| Climb 3+ voxel height | Blocked | Hard wall for standard units |
| Move through goo / rubble | 2 movement points | Terrain modifier effect |

*⚠  Flying units bypass climbing rules. Cell units move efficiently through Cell-placed terrain. Bio units may have free climbing as a racial trait.*

## 5.3 Unit Capacity System

The roster has a capacity cap rather than a unit count cap. Heavier units consume more capacity. This means the player is always making footprint-vs-power tradeoffs, and race identity is expressed through capacity efficiency as well as stats.

| Class | Capacity Cost | Notes |
| :---- | :---- | :---- |
| Light (Cell standard) | 1 | Cell fields more bodies within the same cap |
| Standard (Army standard) | 2 | Baseline reference cost |
| Heavy | 3 | High power, high cost |
| Commander | 1–4 | Varies by commander type; see Section 6 |

* Capacity upgrades are rare and meaningful — finding +1 cap is a run-shaping event
* Capacity grows predictably: +1 guaranteed on each act boss defeat
* Cell units are lighter on average, fielding more bodies at the same budget
* Some units can grow or shrink in capacity through upgrades or events

# 6. Commander System

Each run begins with one commander unit. Commanders provide early strategic direction but are not required to survive — they compete for capacity like any other unit and can be retired if a better unit fills their role. Some commanders are designed to be retired as part of their identity.

## 6.1 Commander Archetypes

| Archetype | Capacity | Value Curve | Retirement Bonus |
| :---- | :---- | :---- | :---- |
| Front-loaded | 1–2 | Strong early, fades by act 2 | Strong: free shop visit, all units +1 upgrade slot for run |
| Scaling | 2–3 | Weak start, grows with upgrades | Moderate: refunds upgrade investments as Scrap |
| Anchor | 3–4 | Defines run strategy throughout | Run-reshaping: rare tier 4 upgrade or capacity expansion |

*⚠  Losing a commander to enemy fire has no special penalty beyond the capacity slot and unit loss. The retirement bonus only triggers on voluntary retirement between stages.*

## 6.2 Starting Loadout

*◆  FLEXIBLE: Exact starting loadout model not finalized. Leading direction:*

Each run: one fixed commander (race-determined, provides identity anchor) plus player chooses one starting unit and one starting upgrade from a small race-specific selection. Mirrors Monster Train's identity anchor with Into the Breach's investment through choice.

# 7. Races

Three core races at launch. All races can perform all roles (digging, building, movement, combat) but have natural strengths that reward leaning into their identity. More races may be added if a sufficiently distinct core mechanic is found.

## 7.1 Race A — Army

Military / human units. The balanced race. Identity is logistics, preparation, and area control rather than raw power. Strength comes from knowing more and positioning better before the shot lands.

| Property | Detail |
| :---- | :---- |
| Terrain relationship | Best at occupying and fortifying terrain they did not destroy |
| Combat identity | Widest firing mode variety; most reliable shot types |
| Special mechanic | Combined arms: adjacent units of different types grant small passive bonuses to each other |
| Elemental affinity | Neutral to all elements |
| Capacity profile | Standard (2 per unit) |
| Shot identity | Trajectory variety and charge control; conventional payloads, maximum reliability |

* Starting unit passive: once per stage, place one sandbag voxel for free
* Between-stage mechanic: Intelligence Report — spend Intel to preview one enemy position on the next stage

## 7.2 Race B — Bio

Monster / dinosaur-like organisms. Powerhouse race. Identity is aggression, consumption, and momentum. They stall out if they play defensively; they thrive when moving forward and destroying.

| Property | Detail |
| :---- | :---- |
| Terrain relationship | Best at destroying terrain; terrain destruction generates bonus resources and buffs |
| Combat identity | Simple trajectories, varied and organic payloads; messy, spreading effects |
| Special mechanic | Momentum: stacking damage buff per tile destroyed per stage; regen if no damage taken last turn |
| Repair mechanic | Cannot be repaired externally; regenerates HP each turn if no damage taken that turn |
| Elemental affinity | Weak to fire; resistant to electric |
| Capacity profile | Standard (2 per unit); some units grow larger through mutation |
| Shot identity | Standard arc trajectories; payloads spread, persist, or consume (corrosive, fragmentation, leaping) |

* Starting unit passive: regenerates 1 HP if it took no damage last turn
* Between-stage mechanic: Consumption — sacrifice HP from one unit to heal another, or consume a dead enemy unit for a one-stage buff

## 7.3 Race C — Cell (Tech / Robotic)

Robot / ethereal units. Fragile individually, powerful in networks and with investment. Identity is precision engineering, enhancement stacking, and fabrication (mass replication, hive mind). A Cell army at peak is playing a different game than the other races.

| Property | Detail |
| :---- | :---- |
| Terrain relationship | Best at fabricating precise terrain structures; places geometric, intentional terrain |
| Combat identity | Environmental interaction and charge tricks; shots interact with Cell-placed terrain |
| Special mechanic | Network: adjacent Cell units share a buff aura; positioning is a primary skill expression |
| Death mechanic | When a Cell unit dies it drops a resource or upgrade fragment adjacent units can collect |
| Elemental affinity | Weak to electric; resistant to physical damage |
| Capacity profile | Light (1 per unit); fields more bodies at same budget |
| Shot identity | Fixed-power beams, conductive bolts, precision burrowing drills; rewards engineering the conditions before firing |

* Starting unit passive: when retired, generates 1 extra Scrap beyond normal retirement value
* Between-stage mechanic: Fabrication Bench — combine two lower-tier upgrades into one higher-tier, or transfer upgrades between units for free
* Unique acquisition mechanic: Unit Fusion — two identical units merge into one with combined stats, one upgrade from each parent, and a new unique ability

## 7.4 Cross-Race Dynamics

| Topic | Rule |
| :---- | :---- |
| Hybrid compositions | Possible but lose intra-race bonuses (network, combined arms). Flexibility at cost of synergy. |
| Elemental affinities | Army: neutral. Bio: weak fire, resistant electric. Cell: weak electric, resistant physical. |
| Terrain aesthetics | Bio terrain looks chewed and organic. Cell terrain looks structured and precise. Army terrain looks fortified. Map tells a story about who came through. |

# 8. Upgrade System

## 8.1 Upgrade Slot Structure

Upgrades attach to individual units, not to a global pool. Each unit has a fixed number of upgrade slots by class. Slots have types that constrain what can be equipped, creating build constraints that prevent stacking all power on one unit.

| Slot Type | Accepts | Notes |
| :---- | :---- | :---- |
| Offensive | Damage, attack property upgrades | Available on all combat units |
| Defensive | HP, shield, movement upgrades | Available on standard and heavy units |
| Utility | Any upgrade type | Flexible; rarer slot type |

| Unit Class | Upgrade Slots | Notes |
| :---- | :---- | :---- |
| Light | 2 slots | Specialized by nature; limited ceiling |
| Standard | 3 slots | Baseline |
| Heavy | 4–5 slots | High ceiling; high investment required |
| Commander | Varies | Scaling commanders have more slots than their tier suggests |

*⚠  Locked slots: units start with one locked slot that unlocks when a condition is met (survives 3 stages, destroys N tiles, kills a boss). Cell unlocks faster through enhancement mechanics.*

## 8.2 Upgrade Tiers

| Tier | Type | Examples | Frequency |
| :---- | :---- | :---- | :---- |
| 1 | Stat | More HP, damage, AoE radius, movement | Common; exists as padding and gap-fill |
| 2 | Conditional | Bonus damage on gooed enemies, bonus damage if full HP, AoE bonus for long-range shots | Uncommon; situationally strong |
| 3 | Property | Elemental addition (fire/electric/freeze), dual shot, impervious, deep penetration, ricochet, seeking | Uncommon; build-defining |
| 4 | Identity | Unit becomes immovable + gains shield each turn; fires twice but cannot move; shots apply status only; generates Scrap per tile destroyed; death triggers auto-shot; deploys anywhere on map | Rare; run-shaping |

*⚠  Tier 1 upgrades are never interesting decisions on their own. Their value comes from pushing thresholds (e.g. +1 AoE radius changing a 2 to a 3 meaningfully changes which tiles are hit).*

## 8.3 Upgrade Synergy Bonuses

Two upgrades on the same unit belonging to the same element or category trigger a bonus effect. These are not documented in tooltips — players discover them through play and feel clever for it. Examples:

* Fire damage + deep penetration: fire spreads underground through connected tiles
* Dual shot + electric: chain lightning arcs between the two impact points
* Ricochet + terrain-bypass: bounces between units ignoring terrain between them

## 8.4 Upgrade Fate on Unit Retirement

When a unit is retired, upgrades are partially converted to Scrap proportional to their tier. A heavily upgraded unit generates more on retirement than a bare one. This creates a timing decision: retire now for more Scrap, or keep the unit one more stage and risk losing it to damage.

*◆  FLEXIBLE: Alternative: upgrades are recovered as re-equippable items. Makes retirement a redistribution tool rather than a resource event. Not decided.*

# 9. Acquisition Ecosystem

Each acquisition source is distinct in what it offers and when it is available. No single source provides everything. The rhythm across a run is: collect (act 1) → consolidate (act 2) → optimize (act 3).

| Source | What It Offers | When | Notes |
| :---- | :---- | :---- | :---- |
| Combat rewards | Units and upgrades biased toward stage content | After every stage | Primary channel; reward pool reflects what you destroyed and killed |
| Shops | Curated selection of 4–6 items at gold cost | Between acts + some map nodes | Gap-fill and targeted acquisition; items unsold for one act get discounted |
| Events | High-variance items; unit modifications; terrain tools | Event map nodes | Only source of some unusual upgrades; small RNG in outcomes is acceptable here |
| Enemy drops | Thematic upgrades tied to enemy type | On elite / boss kill | Elite always drops something; boss always drops significant reward |
| Scrap crafting | Tier 1–2 upgrades at fixed Scrap cost | Between stages at base | Floor guarantee; tier 3 crafting requires Scrap + component drop from specific enemy |
| Cell fusion | New unit with combined stats and unique ability | Cell race only | Late-run mechanic; costs both parent units |

## 9.1 Event Node Design

Events carry run personality and create memorable moments. Template: situation description, 2–3 choices with visible but not fully detailed consequences, outcome with slight variance. Examples:

* Abandoned armory: one tier 3 upgrade from random list, or take two tier 1 upgrades
* Wounded unit: damaged enemy unit offers to join roster (low HP, unique ability)
* Terrain anomaly: next stage has a specific terrain property (conductive, explosive, reinforced)
* Black market: buy a powerful item at capacity cost rather than gold cost
* Field promotion: one unit permanently gains +1 upgrade slot

# 10. Stage Types

Stage type and hazard tag are visible on the map node before the player commits. Terrain profile (open, cave, flooded, etc.) is also visible as a secondary tag, adding a second dimension to path decisions.

| Stage Type | Win Condition | Key Design Note |
| :---- | :---- | :---- |
| Combat | Deplete all enemy HP | Baseline encounter type |
| Destroy | Hit all weak points on objective structure | Weak points may shift between HP phases; terrain clearance is primary skill |
| Snipe | Eliminate a protected target via a specific approach | Target is invulnerable except through designed angle or method; not just a harder combat |
| Survive | Reach extraction or hold zone for N turns | Large unique hazard defines the stage; player must act, not just wait |
| Race | Reach the stage exit | Player may need to destroy terrain to carve a route; enemy units or PvE depending on path |

# 11. Stage Hazards

Hazards are rated on two axes: agency (can the player counter or exploit it) and predictability (is timing and location knowable). Strong hazards score high on both. Pure random hazards score low on both and are used sparingly.

| Hazard | Agency | Predictability | Key Mechanic |
| :---- | :---- | :---- | :---- |
| High wind | Low–Med | High (HUD value shown) | Persistent arc deflection; shifting wind on Survive stages |
| Lightning (Thor) | Medium | High (strikes highest point) | Incentivises staying low; conductive tiles chain damage |
| Explosive mines | High | High (visible but unmarked) | Reward observation; can be detonated deliberately as a weapon |
| Shield generator | High | High | Sub-objective: destroy generator to remove shield |
| Goo | Medium | High | Movement cost modifier; spreads each turn if uncleared; conducts electricity |
| Tornado / absorber | Medium | Medium | Projectile deflection field; skilled players aim through it intentionally |
| Deflector tiles | High | High | Bounce surfaces; destructible; usable for bank shots |
| Flood | Medium | High (rate shown) | Rising water interacts with climbing rules; unit selection matters pre-stage |
| Meteor fall | High | High (shadow 2 turns ahead) | Can be weaponised by positioning enemy under shadow |

## 11.1 Beneficial Stage Elements

Not all environmental elements are threats. Stages should include elements the player plays toward, not only around:

* Geysers: launch units upward from specific tiles (free vertical mobility)
* Repair stations: physical locations on the map; unit must reach them to benefit
* Amplifier towers: boost damage for units in range; contestable control points
* Salvage caches: buried in terrain; drop resources when those voxels are destroyed

# 12. Enemy Design

## 12.1 Core Principle

All enemies are terrain actors, not just threat emitters. Every enemy archetype has a defined relationship with the voxel terrain as part of its core identity. An enemy that ignores terrain is wasted potential in Artillery Space.

## 12.2 Enemy Behavior System

Enemies use Priority Stacks: an ordered list of behaviors evaluated each turn, executing the first whose conditions are met. This is fully deterministic — same game state always produces the same enemy decision. Because terrain and positions change, the output varies meaningfully without hidden AI decisions.

All enemy intentions are declared at the start of the enemy phase before any enemy acts. The player reads the full board and plans their response.

| Behavior | Trigger Condition | Telegraph |
| :---- | :---- | :---- |
| ATTACK | Player unit in firing range | Crosshair icon + target highlight + projected impact voxel + AoE footprint |
| FORTIFY | Unit has taken damage or is exposed | Brick icon + green overlay on target voxels |
| DEMOLISH | Player cover or footing within range | Shovel icon + orange overlay on target voxels |
| ADVANCE | No attack target; path to spawn zone available | Arrow icon + movement path overlay |
| SUPPRESS | Area denial mode; zone within range | Zone icon + red zone highlight |
| PROTECT | High-value friendly unit is exposed | Shield icon + movement toward protected unit |
| EXCAVATE | Resource or objective underground | Drill icon + dig path shown |

## 12.3 Enemy Archetypes

| Archetype | Terrain Relationship | Primary Threat | Counter |
| :---- | :---- | :---- | :---- |
| Entrencher | Digs down or places cover each turn | Becomes progressively harder to hit | Prioritize early or use terrain-bypass shots |
| Demolisher | Attacks player terrain, not player units | Degrades cover and footing | Interrupt before it fires; repair scrap loop |
| Anchor | Large bounding box embedded in terrain | Wide coverage, high HP | Clear surrounding terrain to expose core |
| Crawler | Burrows through terrain; surfaces to attack | Hard to hit while burrowing | Collapse terrain above path; underground AoE |
| Swarm | Uses existing terrain as paths | Overwhelming volume | AoE efficiency; collapse chokepoints |
| Builder | Constructs reinforced cover each turn | Creates expensive-to-breach fortifications | Destroy materials; scrap reward for destroying builds |
| Conductor | Surrounded by conductive terrain | Chained electrical damage | Hit conductive network for amplified damage vs. direct hit |

*⚠  Every base archetype has an elite variant with one additional terrain behavior that creates a new decision, not just more HP.*

## 12.4 Objective Switching

Enemies do not simultaneously pursue multiple objectives. They have one active objective at a time, switching on a visible trigger (progress bar, turn counter, HP threshold). This creates race dynamics: the player can see 'this builder switches to attack in 3 turns when its wall completes' and decides whether to disrupt, accept, or exploit that.

# 13. Boss Design

## 13.1 Boss Principles

* Bosses are terrain events as much as unit encounters — they change the terrain in ways that force mid-fight adaptation
* Phase transitions reshape terrain significantly; established positions become untenable
* Each boss has a mechanical gimmick solvable differently by different builds
* By fight end the map looks dramatically different from the start
* Boss behavior uses a visible behavior deck (fixed sequence shown to player); phase transitions shuffle or replace it

## 13.2 Boss Concepts

| Boss | Act | Core Mechanic | Phase Structure |
| :---- | :---- | :---- | :---- |
| The Fortress | 1 | Entrenched bunker with multiple weak points; periodically adds voxels to fortification | P1: clear terrain to open sightlines. P2 (60% HP): bunker collapses, new configuration. P3 (30%): abandons bunker, becomes mobile — fight changes character entirely. |
| The Hive | 2 | Central unit spawning crawlers from destructible tunnels; swarm units act as AoE multipliers against boss | P1: destroy tunnels to stop spawns while managing swarm. P2 (50% HP): boss burrows and surfaces randomly; earlier terrain clearance creates advantage. |
| The Conductor | 2 (alt) | Embedded in conductive network; direct damage is shielded; intended solution is electrical chains through network | Calibration puzzle: destroy enough network nodes to weaken attacks, keep enough to chain damage. Each race solves it differently. |
| The Colossus | 3 | 10x10+ voxel bounding box; multiple body sections with separate HP pools; destroys terrain as it moves | Each section destroyed = phase transition. Legs: immobilize. Arms: remove attack types. Core: win condition. Map degrades throughout. |

## 13.3 Miniboss Role

Minibosses at act midpoints are teaching moments. Each introduces the mechanic the act boss will use in a more complex form. Players who understand the miniboss are prepared for the boss; players who brute-forced it will struggle with the full version. This creates a two-beat learning structure per act.

# 14. Game Loop

## 14.1 Macro Loop

A run consists of three acts plus a final boss, following a branching path map. Each act ends with a boss encounter. The inter-act shop and event beat is where the most strategic weight lives.

| Phase | Content |
| :---- | :---- |
| Run start | Select commander + starting unit + starting upgrade (race-specific options) |
| Act 1 (4–5 nodes) | Build-forming; mostly combat rewards and one shop; capacity is tightest |
| Act 1 boss | Teaches terrain-as-mechanic; guarantees +1 capacity on defeat |
| Inter-act (shop + event) | Primary consolidation opportunity; between-stage actions |
| Act 2 (4–5 nodes) | Build-consolidating; terrain becomes adversarial; elite drops appear |
| Act 2 boss | Tests build against a specific mechanic puzzle |
| Inter-act (shop + event) | Final major acquisition opportunity |
| Act 3 (4–5 nodes) | Build-optimizing; capacity less tight; fewer new units, more refinement |
| Act 3 boss | Full test of skill + resource management across multiple HP pools |

## 14.2 In-Stage Loop

Each turn the player has a Command Budget spent on actions:

| Action | Cost | Notes |
| :---- | :---- | :---- |
| Fire a unit | 1 command point | Core action |
| Move a unit | 1 command point | Can combine move + fire on same unit |
| Use terrain tool | 1 command point | Place, destroy, or modify a voxel |
| Use unit ability / special | 1 command point | Triggers special shot or passive ability |
| Reposition entire squad | 2 command points | High cost; significant repositioning |

Each stage has a primary objective and visible secondary objectives (complete in X turns for gold bonus, take less than Y damage for Scrap bonus, destroy marked terrain for Intel). Secondary objectives reward efficient play without gating progress.

## 14.3 Between-Stage Actions

Between stages, players have a turn budget for base camp actions. Actions compete for the same budget, creating a small optimization problem each time:

| Action | Cost | Notes |
| :---- | :---- | :---- |
| Repair a unit | 1 action + Scrap | Decision: repair now or gamble on survival |
| Retire a unit | 1 action | Generates Scrap; timing matters (deploy last stage vs. retire for resources) |
| Attach / move upgrade | 1 action | Transfer upgrades between units; Cell does this for free |
| Craft upgrade (tier 1–2) | 1 action + Scrap | Floor guarantee if acquisition has been unlucky |
| Race-specific action | 1 action | Army: Intel report. Bio: Consumption. Cell: Fabrication bench. |

# 15. Resource System

*◆  FLEXIBLE: Roguelite meta-progression is not finalized. The following is current design direction.*

| Currency | Primary Source | Primary Sink | Design Note |
| :---- | :---- | :---- | :---- |
| Gold | Enemy kills, stage completion | Shop purchases | Common enough that player always has something to spend; never enough to buy everything |
| Scrap | Terrain destruction, unit kills, retirement | Unit repairs, terrain tools, crafting | Ties destruction gameplay to economy; aggressive play literally pays for itself |
| Intel | Event nodes, specific mission types | Reveal boss mechanics, hazards, enemy positions | Information-economy currency; makes event nodes feel materially valuable |

| In-Stage Action | Resource Generated |
| :---- | :---- |
| Kill an enemy unit | Gold |
| Destroy terrain voxels | Scrap |
| Complete secondary objective | Intel or bonus Gold |
| Complete stage with no unit deaths | Scrap bonus |
| Destroy a hazard element | Small Gold + Scrap |

# 16. Run Progression and Path Map

The branching path map follows the choose-your-path model (Slay the Spire / Monster Train). Boss type is visible from run start. Stage type, hazard tag, and terrain profile are visible on each node before the player commits.

## 16.1 Path Decision Dimensions

* Stage type: different win conditions favor different compositions
* Hazard tag: a hazard that suits the player's build converts a threat into an advantage
* Terrain profile: open field vs. cave vs. flooded basin rewards different unit setups
* Reward type: combat reward vs. shop vs. event node vs. elite (harder, better drop)

## 16.2 Boss Preparation

Boss type is visible from run start. Boss stages also have a terrain profile that is a second preparation target — a flood-variant Survive boss rewards climbing units and high-ground weapons; a fortified Snipe boss rewards terrain-destruction tools. Players who've learned the game prepare for both dimensions.

*◆  FLEXIBLE: Meta-progression between runs (unlocks, permanent progression) is not designed yet. Placeholder: each completed run unlocks additional commander options and starting upgrade selections.*

# 17. Difficulty and Ascension

Difficulty is modular through an ascension system (equivalent to Slay the Spire's Ascension or Hades' Pact of Punishment). Modifiers stack and can be combined. No modifier is framed as the 'real' mode vs. an 'easy' mode — each is a personal choice.

| Modifier | Effect |
| :---- | :---- |
| No firing preview | Removes arc and AoE preview; barrel direction indicator remains; core strategic game unchanged |
| Partial preview only | Shows first 40% of arc trajectory only; experienced players extrapolate |
| Reduced capacity | Run starts with −1 total capacity |
| Faster enemy scaling | Enemies gain HP and new behaviors more quickly across acts |
| No death bonus | Removes Scrap bonus for completing a stage without unit deaths |
| Elite encounters | Some standard combat nodes are replaced with elite variants |

# 18. Future Phases (Out of Current Scope)

* Full roguelite run loop with branching path map implementation
* Shop, event, and reward node implementations
* Enemy AI priority stack implementation and balance
* Full elemental system (fire, electricity, freeze, corrosive) with tile interactions
* Race-specific between-stage mechanics
* Commander and starting loadout selection screen
* Meta-progression between runs
* Audio and visual polish
* Multiple biomes and procedural map generation
* Potential: co-op mode (squad split between two players)
