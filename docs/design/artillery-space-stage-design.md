# Artillery Space — Stage Design Specification

**Design Document · v0.1 (living document — expected to iterate)**

Defines the vocabulary and structure for stage design: how terrain, protection, enemy placement, and win conditions combine into distinct stage types. This is deliberately left open — stage types are a taxonomy to extend, not a fixed list. It establishes the shared structural language (layers, protection tiers, anchors, asymmetric threat) so new stage types and boss designs can be described consistently. Read alongside the terrain-generation doc (feature generation, profiles) and the run-design doc (four-leg framework).

---

## 1\. Core Principle: Every Stage Is a Terrain Thesis

Each stage poses one spatial question the player answers with their build and their play. The terrain is the problem, not the backdrop. Before authoring any stage, state its thesis in one sentence — if you can't, the stage has no identity.

Examples:

- "There is a protected core; the defenders can hit you while sheltered." (Fortress Assault)  
- "You must become the sheltered one and survive an escalating assault." (Siege)  
- "The targets won't hold still; terrain breaks your line of fire." (Gauntlet)  
- "The reward is buried; dig for it while the clock ticks." (Extraction)  
- "The battlefield itself is trying to kill you." (Collapse)

This principle is the filter for all stage design and the anchor for evaluating whether terrain is load-bearing rather than decorative.

---

## 2\. Structural Vocabulary

All stage types are built from this shared vocabulary. New stage types should reuse these concepts rather than inventing parallel ones.

### 2.1 Layers

Terrain is authored in bands from the outside in:

- **Shell** — the outermost terrain a shot encounters. Usually the protective barrier (bunker wall, ridge face, cave ceiling).  
- **Cavity** — interior space, where protected units or objectives sit.  
- **Core** — the deepest point: the objective, the boss weak point, or the most protected defenders.

Not every stage uses all three. An open Gauntlet has no shell; a Fortress has all three; a Collapse stage might have a shifting shell (the safe zone) with the hazard as an inverted core.

### 2.2 Protection tiers

Terrain durability roles (from the terrain-generation doc), used to express difficulty:

| Tier | Durability (hits) | Role |
| :---- | :---- | :---- |
| Indestructible skeleton | — | Permanent geometry; forces non-demolition answers |
| Reinforced shell | 8–12 | The barrier; requires sustained fire or a bypass |
| Normal fill | 3–4 | Erodes naturally; standard terrain |
| Weak / collapsible | 1–3 | Trigger terrain for collapse and hazard play |

A stage's difficulty is largely how much reinforced shell sits between the player and the core, and whether an indestructible skeleton forces a specific terrain relationship (you *cannot* demolish your way to this core — you must go over, around, or through).

### 2.3 The four terrain relationships as stage answers

Every combat stage should be solvable by at least two of the six terrain relationships, never only one (that would make it a build check rather than a puzzle). The relationships: Go Through (drill), Remove (demolish), Go Over (arc), Go Around (precision), Make Irrelevant (flood/deny), Weaponize (collapse). A well-designed stage's protection structure implicitly invites some relationships and resists others.

### 2.4 Asymmetric threat (the central pattern)

The design pattern that makes terrain matter: **units that can attack out from safety while being hard to attack back.** If defenders were fully exposed, the player would simply out-damage them and terrain would be irrelevant. The tension is that they're protected and the player is not, or vice versa.

Expressions of asymmetry:

- Sheltered gunners firing through apertures (protected out, hard to hit back)  
- Artillery firing over cover the player is hiding behind (turtling fails)  
- Burrowers surfacing behind the player's position (static play fails)  
- Hazard-immune enemies comfortable where the player is in danger (inverted terrain safety)

Every combat stage should have at least one asymmetric threat. Stages with only symmetric threats (both sides equally exposed) degenerate into damage races.

### 2.5 Static hazards and fixtures

Non-unit threats placed in terrain: turrets (fire on a telegraph, destructible fixture), traps (trigger on unit proximity), hazard tiles (lava, spreading fire), reinforcement beacons (spawn units, must be destroyed). These are faction-neutral and add texture without adding units to track. They are placed via the anchor system (§4) like units.

---

## 3\. Win Conditions

Win conditions are a first-class stage design lever, not an afterthought. The condition shapes which builds the stage rewards.

| Win condition | Rewards | Notes |
| :---- | :---- | :---- |
| Eliminate all enemies | Damage, board clear | The default; least terrain-specific |
| Destroy the objective | Bypass, precision, reach | Player can ignore defenders — rewards reaching, not killing |
| Survive N rounds | Defense, terrain-building, sustain | The siege thesis |
| Reach the exit | Mobility, terrain traversal | Movement-focused; enemies are obstacles |
| Extract/hold for N rounds | Economy, risk management | Greed vs. safety tension |
| Eliminate a specific target | Precision, reach | Priority-target puzzle (kill the beacon, the spotter) |

Mixing win conditions across a run's stages is what keeps builds from being one-dimensional — a run that's all "eliminate all enemies" only ever tests damage.

---

## 4\. The Anchor Manifest Handshake (build this first)

**This is the architectural keystone. Build and validate it before any specific stage type.**

The terrain generator and the StageDescriptor are decoupled: the generator produces terrain, the descriptor places enemies and fixtures. They connect through **named anchor points** that the generator exports when it builds a feature.

### 4.1 How it works

When the generator places a feature, it exports a manifest of named positions relative to that feature:

Bunker feature exports:

  "interior\_center"   \-\> Vector2i

  "aperture\_left"     \-\> Vector2i   (the firing slot position)

  "aperture\_right"    \-\> Vector2i

  "core"              \-\> Vector2i   (deepest interior point)

  "roof\_center"       \-\> Vector2i

Cave feature exports:

  "chamber\_center"    \-\> Vector2i

  "shaft\_mouth"       \-\> Vector2i

Ridge feature exports:

  "summit\_center"     \-\> Vector2i

  "reverse\_slope"     \-\> Vector2i   (the hidden side)

The StageDescriptor references anchors by name, never by coordinate:

FortressAssault descriptor:

  enemies:

    \- { type: "aperture\_gunner", anchor: "aperture\_left" }

    \- { type: "aperture\_gunner", anchor: "aperture\_right" }

    \- { type: "wall\_engineer",   anchor: "interior\_center" }

  objective:

    \- { type: "reinforcement\_beacon", anchor: "core" }

  player\_spawn: "default\_left\_platform"

This means the same descriptor produces a coherent stage across every seed — the bunker varies in size and position, but the gunners are always at its apertures and the objective is always at its core.

### 4.2 Open questions for the anchor system

- **What happens when a feature doesn't have a requested anchor?** (e.g. a descriptor asks for "aperture\_left" but the generated bunker only has one aperture.) Fallback rules needed: nearest valid anchor, skip the enemy, or regenerate the feature.  
- **How are multiple features on one map disambiguated?** If a stage has two bunkers, anchors need feature-scoping ("bunker\_1.core" vs "bunker\_2.core"). Recommend feature instances get IDs and anchors are namespaced.  
- **Should anchors be exact voxels or zones?** A zone ("anywhere in the interior cavity") gives the generator freedom; an exact voxel is predictable. Possibly both — some anchors precise (aperture), some zonal (interior).  
- **Validation:** the generator should verify every anchor a descriptor requires actually exists before combat starts, failing loudly in the sandbox rather than silently misplacing enemies.

Build the anchor handshake with the Fortress Assault first (clearest case), validate placement follows terrain across seeds, then extend to other stage types.

---

## 5\. Stage Type Catalogue (extensible)

Each entry is a starting point, not a locked design. Add types and variations freely.

### 5.1 Fortress Assault — destroy-the-objective

**Thesis:** a protected core you must destroy; defenders shoot out from shelter.

**Layers:** reinforced shell (2–3 thick, 1–2 apertures) → cavity (defenders) → core (objective).

**Roster:**

- Aperture Gunners (2–3): static, fire through apertures on telegraph, high armor / low HP. Reaching them is the challenge.  
- The Objective (1): reinforcement beacon (spawns waves, creates urgency) or inert structure (pure terrain race).  
- Optional Wall Engineer (1): rebuilds 1–2 shell tiles per round; punishes slow demolition.

**Shooting:** fixed-angle IK through apertures, telegraphed one turn ahead. Gunners only hit positions their aperture sees — blind spots are safe. Moving is a valid response.

**Randomness:** aperture facing (L/C/R), gunner count, Wall Engineer presence, objective type. Thesis constant, layout varies.

**Waves:** if beacon objective, 1 mobile reinforcement per 2 rounds. If inert, no waves.

**Win:** destroy the objective (not kill-all — rewards reaching over killing).

**Terrain answers invited:** Go Around (thread apertures), Go Over (arc in), Go Through (drill shell), Remove (demolish). Resists: Make Irrelevant (flooding doesn't reach a sheltered core).

### 5.2 Siege — defend/survive

**Thesis:** become the sheltered one; survive escalating assault.

**Layers:** player near a defensible position → open ground → enemy spawn edges.

**Roster:**

- Advancing Infantry (waves of 2–3): move toward player, fire flat trajectories (blocked by cover).  
- Siege Breakers (1–2, later waves): target terrain/deployables (Demolisher archetype); stop "build one wall and win."  
- Artillery Support (1, far back): high arcs over cover; punishes pure turtling.

**Shooting:** dual threat — flat fire (cover stops it) \+ arc fire (cover doesn't). Can't just hide.

**Randomness:** spawn edge(s), wave composition, artillery presence, starting defensibility of terrain.

**Waves:** escalating. W1 infantry (learn), W2 adds Breaker (cover threatened), W3 adds artillery (turtling fails).

**Win:** survive N rounds or clear all waves.

**Terrain answers invited:** Remove/Weaponize (proactive), terrain-building (cover), Make Irrelevant (deny approach lanes). Resists: pure precision (too many targets).

### 5.3 Gauntlet — mobile-target hunt

**Thesis:** targets won't hold still; terrain breaks your line of fire.

**Layers:** complex terrain (ridges, pillars, broken ground); enemies distributed using it as cover.

**Roster:**

- Skirmishers (3–4): reposition behind cover after each player shot; fire when they have LOS.  
- Burrowers (1–2): tunnel and resurface elsewhere; punish static positioning.  
- Spotter (1): doesn't fire; reveals player positions (removes cover bonus). Kill-priority.

**Shooting:** opportunistic — fire when clear, reposition when not. Terrain state after each shot changes who sees whom.

**Randomness:** terrain profile, enemy starts, burrower presence. High variance — most different each run.

**Win:** eliminate all enemies.

**Terrain answers invited:** Go Around (precision on movers), Remove (deny their cover), Weaponize (collapse on repositioned clusters). Resists: slow setup builds (targets move before payoff).

### 5.4 Extraction — resource under pressure

**Thesis:** the reward is buried; dig while the clock ticks.

**Layers:** heavy crystal deposits deep in terrain; few/no initial enemies.

**Roster:** minimal initially; escalating reinforcements if the player lingers (arrive from a fixed edge, scale with rounds).

**Win:** reach the exit or survive N rounds, having extracted as much as chosen to risk. The clean test-bed for the crystal economy and anti-stalling pressure.

**Terrain answers invited:** Remove/Go Through (dig to deposits), mobility (reach and exit). The greed-vs-safety slider is the whole stage.

### 5.5 Collapse — terrain hazard as antagonist

**Thesis:** the battlefield itself is trying to kill you.

**Layers:** shifting safe zone (shrinking shell) with the hazard as an inverted core (rising lava, progressive collapse, spreading hazard).

**Roster:** few enemies, secondary to the hazard; some benefit from it (fire-immune in lava, flying in collapse) — inverting the usual asymmetry.

**Win:** reach the exit / survive until hazard peaks / destroy the hazard source.

**Terrain answers invited:** mobility (stay ahead of hazard), Make Irrelevant (counter the hazard), Go Over (elevation). Rewards the terrain-answer legs directly.

---

## 6\. Boss Stages (open design space)

Bosses are deliberately under-specified here — they should feel like a *combination* of the stage theses above plus something singular. Two directions worth developing, both open:

### 6.1 Composite bosses

A boss stage that layers multiple theses: a Fortress core (destroy the objective) that also spawns Siege waves (survive) on terrain that Collapses (hazard) as the fight progresses. The four-leg final exam expressed spatially — the boss tests scaling, reach, defense, and terrain simultaneously by combining the stage types that each isolate one.

Design approach: rather than a bespoke boss, compose a boss from stage-type modules with a phase schedule. Phase 1 is a Fortress (reach the core). Phase 2, triggered at a core HP threshold, becomes a Siege (the core is exposed but defended by waves). Phase 3 becomes a Collapse (the arena degrades as the boss is cornered). Each phase reuses existing stage-type machinery.

### 6.2 Terrain-like bosses (Shadow of the Colossus direction)

A boss that *is* terrain — a massive structure or creature that occupies the map as destructible/climbable geometry, with weak points that are themselves terrain features (an exposed core reached by destroying armor plating, a joint that collapses when its support is removed).

This is the most distinctive possible boss design for Artillery Space specifically, because it makes the terrain systems (destruction, collapse, layers, anchors) *be* the boss rather than the arena. The boss's "HP" is distributed across terrain-like sections; defeating it is a terrain-solving puzzle at scale.

Open questions for terrain-bosses:

- Is the boss a special MapData region with unit-like HP pools per section, or a unit with a terrain-shaped bounding box?  
- How do weak points telegraph? (Exposed core after plating destroyed; a joint that collapses on support removal.)  
- Does the boss move / reconfigure, and if so, how does the anchor system handle a moving feature?  
- How does the four-leg exam map onto a single terrain-creature (different legs attack different sections)?

Both boss directions are intentionally open. The composite approach is lower-risk and reuses existing machinery; the terrain-boss is higher-risk and higher-reward as a signature moment.

---

## 7\. Randomness Strategy (open question — resolve through iteration)

The central open question for the whole system: **how much of a stage is hand-crafted versus generated?** Options, not mutually exclusive:

- **Fully generated:** stage type \+ profile \+ seed produce everything. Maximum variety, hardest to guarantee quality and thesis clarity.  
- **Hand-crafted templates with seed variation:** a designer authors the structural skeleton (this stage is a Fortress with the objective here, apertures roughly there), and the seed varies dimensions, fill, and minor placement. Balances quality and variety. **Recommended starting point.**  
- **Fully hand-crafted set pieces:** specific stages (bosses, key act moments) authored entirely by hand, no generation. Best for signature moments, no variety.

Likely the right answer is a mix by stage role: standard combat stages use templates-plus-seed; extraction and collapse stages use templates-plus-seed with tuned hazard schedules; bosses and key act moments are hand-crafted set pieces. This is a decision to converge on through playtesting, not to lock now.

Sub-questions:

- Does the generator guarantee solvability (at least two terrain relationships viable), or is that a designer's responsibility on the template?  
- How is difficulty scaled within a stage type — by protection tier density, enemy count, wave escalation rate, or all three?  
- Should the player see the stage's thesis/type before committing to the node (telegraphing), or discover it on entry?

---

## 8\. Open Questions Summary (the iteration backlog)

| \# | Question | Where it matters |
| :---- | :---- | :---- |
| 1 | Anchor fallback when a requested anchor doesn't exist | §4.2 — blocks all stage types |
| 2 | Anchor namespacing for multi-feature maps | §4.2 |
| 3 | Anchors as exact voxels vs. zones (or both) | §4.2 |
| 4 | Generator anchor validation / loud failure in sandbox | §4.2 |
| 5 | Hand-crafted vs. generated balance per stage role | §7 — governs the whole approach |
| 6 | Generator solvability guarantee vs. designer responsibility | §7 |
| 7 | Difficulty scaling levers within a stage type | §7 |
| 8 | Stage thesis telegraphed on the map or discovered on entry | §7 |
| 9 | Boss as composite modules vs. bespoke | §6.1 |
| 10 | Terrain-boss representation (MapData region vs. big-bbox unit) | §6.2 |
| 11 | Moving/reconfiguring features and the anchor system | §6.2 |
| 12 | Win-condition mix targets across a run (how many of each type) | §3 |

---

## 9\. Recommended First Implementation Path

1. Build the anchor manifest handshake (§4) against the existing bunker feature. Validate placement follows terrain across seeds in the sandbox.  
2. Implement the Fortress Assault (§5.1) as the first full stage type — it exercises apertures, asymmetric threat, objective win condition, and optional waves.  
3. Add the Siege (§5.2) — exercises wave escalation, the dual flat/arc threat, and terrain-building payoff.  
4. Add the Gauntlet (§5.3) — exercises mobile enemy repositioning and the terrain-breaks-line-of-fire thesis.  
5. Add Extraction (§5.4) and Collapse (§5.5) — exercise the economy and hazard systems respectively.  
6. Prototype one composite boss (§6.1) by chaining Fortress → Siege → Collapse phases.  
7. Only then explore the terrain-boss (§6.2) as a signature set piece.

Each step is independently testable in the sandbox and adds one clear capability. Resolve the relevant open questions as each step surfaces them, rather than trying to answer all of Section 8 up front.  
