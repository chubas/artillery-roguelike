# Artillery Space — Run State & Progression Foundation
**Technical Specification · v0.1**

> The backbone for everything outside the combat stage: persistent run state, the combat read-from / write-back contract, the stage-as-descriptor model, and the objective evaluator. This is the layer that turns a self-contained combat sandbox into a roguelite run. It is sequenced by dependency, not by milestone — each section is the foundation for the next.
>
> **Current reality (from PROGRESS.md):** combat is mature (M1–M10, headless-verified). `CombatManager` holds a combat-local deck/hand/discard, hardcoded squad, hardcoded reinforcement schedule, hardcoded deployable placements, and a hardcoded artifact loadout. The stage starts fresh and ends with a log message. **Nothing carries forward.** This spec adds the layer that makes things carry forward.

---

## 1. The Core Problem

Everything outside the stage — stage select, objectives, events, squad selection, deck progression — depends on a layer the code does not yet have: **persistent run state.** The combat scene currently has two of the three architectural layers:

| Layer | Status | Holds |
|---|---|---|
| **Definition** (immutable, shared) | ✅ Exists | Unit/shot/card/element/artifact `.tres` resources |
| **Run state** (mutable, persists across stages) | ❌ Missing | The squad, the deck, artifacts, resources, map position, per-unit HP/kills |
| **Combat state** (runtime, per-combat) | ✅ Exists | Shields, effects, positions, hand/discard, AP |

The middle layer is the backbone. Until it exists: squad selection has nowhere to write its result; objectives can't vary because the stage is one hardcoded scene; events can't grant rewards because there's no run state to grant into; stage select can't exist because there's no notion of "between stages."

**The first work is not a feature — it is this layer plus the contract that connects it to combat.**

---

## 2. The Persist/Discard Boundary (decide first)

Before any code, the single most important decision: **what carries across stages and what resets each combat.** Getting this boundary explicit once is what keeps the run-state layer clean rather than a source of subtle "why is this carrying over" bugs.

| Thing | Scope | Rationale |
|---|---|---|
| Unit current HP | **Persist** | HP is the run-deciding resource (card/engine doc §5) |
| Unit kills / scaling counters | **Persist** | Scaling units accumulate across the run |
| Unit permanent upgrades | **Persist** | Baked into the unit for the run |
| Unit equipment loadout | **Persist** | Part of the unit's run identity |
| Disabled state (unit hit 0 HP) | **Persist** | Carries into next stage as disabled (death/repair mechanic) |
| Deck composition (the card list) | **Persist** | The deck is built over the run |
| Artifacts | **Persist** | Run-level rule modifiers |
| Resources (Gold/Scrap/Intel) | **Persist** | Spent between stages |
| Map position | **Persist** | Where the player is in the run |
| Shields | **Reset per combat** | Tactical buffer, regenerates between stages free |
| Armor | **Reset per combat** | Per-combat mitigation |
| Effects (burn, shock, boosted, etc.) | **Reset per combat** | Combat-state conditions |
| Unit position | **Reset per combat** | Set by pre-combat placement |
| AP / action pool | **Reset per combat** | Refills each turn |
| Hand / discard / draw order | **Reset per combat** | See §6 — combat *seeds* from the persistent deck |
| Artifact `reset_per_combat` hooks | **Re-trigger each combat** | Already implemented; fire on combat start |

The rule of thumb: **anything that defines what your run *is* persists; anything that is the *texture of a single fight* resets.**

---

## 3. RunState — The Backbone Object

A single serializable object that is the source of truth for a run in progress. Combat reads from it on entry and writes back to it on exit. Nothing else holds run-level truth.

Conceptual shape (implementation detail to the agent):

```
RunState
  squad          : array of RunUnitState     # the player's units
  deck           : array of card ids          # the persistent card list (see §6)
  artifacts      : array of artifact ids       # active run-level modifiers
  resources      : { gold, scrap, intel }      # economy
  map            : MapState                     # nodes, edges, current position (see §7)
  run_meta       : { seed, act, stage_index }   # run identity + RNG seed for reproducibility
```

```
RunUnitState                          # the per-run mutable layer for one unit
  definition_id  : String             # which UnitDefinition this is
  current_hp     : int                # persists across stages
  max_hp         : int                # base + permanent upgrades
  is_disabled    : bool               # hit 0 HP, awaiting repair/replace/retire
  kills          : int                # scaling counter
  upgrades       : array of upgrade ids
  equipment      : array of equipment ids
  # derived combat stats (attack, etc.) computed from definition + upgrades at instantiation
```

`RunUnitState` is the layer the combat `Unit` is *built from* and *written back to*. The existing `Unit` node stays the combat-state representation; it gains an instantiation path from `RunUnitState` and a write-back path to it.

> A single autoload (e.g. `Run`) holding the active `RunState` is the natural home, mirroring the existing `EventBus` / `Features` autoload pattern. Whether run state is an autoload or passed explicitly is the agent's call — what matters is that there is exactly one source of truth.

---

## 4. The Combat I/O Contract

The combat scene must stop hardcoding its setup and instead implement a read/write contract against `RunState` + a stage descriptor (§5).

### 4.1 Read (combat entry)

`combat_scene` is initialized from two inputs: the `RunState` (what the player brings) and a `StageDescriptor` (what this stage is). On entry it:

- Instantiates a combat `Unit` for each non-disabled `RunUnitState`, reading `current_hp` (not max), applying upgrades/equipment to derive combat stats.
- Seeds the combat deck from `RunState.deck` (shuffle into draw pile — see §6).
- Activates `RunState.artifacts` into the existing artifact loadout path (replacing the hardcoded `_ARTIFACT_LOADOUT`).
- Builds the stage from the `StageDescriptor`: enemy waves, deployable placements, wind profile, terrain seed, objective (replacing the hardcoded schedules).
- Runs pre-combat placement (§8) to position the squad.

### 4.2 Write (combat exit)

On stage resolution (win or loss), before leaving the scene, combat writes back to `RunState`:

- Each surviving unit's `current_hp` → its `RunUnitState`.
- Each unit's accumulated `kills` → its `RunUnitState`.
- Units that reached 0 HP → `is_disabled = true` on their `RunUnitState`.
- The combat outcome (cleared / failed / objective result) → returned to the caller (the map/run controller) so it can advance position, grant rewards, or end the run.

The deck, artifacts, and resources are **not** written back from combat — combat consumed copies (hand/discard) but the persistent deck is unchanged by a fight. Deck changes happen between stages (§6), not inside combat.

### 4.3 The proof harness

Validate the contract before building anything on top: two hardcoded stages back to back, where a unit that lost HP in stage 1 starts stage 2 still damaged. **If HP persists across that boundary and shields/effects reset, the backbone works.** This is the gate for everything downstream.

---

## 5. StageDescriptor — Stage as Data, Not a Scene

Everything the combat scene currently hardcodes becomes a descriptor it reads. This is the "stage as a timeline" model (card/engine doc §9.1): a stage is *initial force + telegraphed reinforcement schedule + per-turn objective*, all from data.

Conceptual shape:

```
StageDescriptor
  terrain_seed     : int                  # reproducible generation
  initial_enemies  : array of { unit_id, column }      # present at turn 0
  reinforcements   : array of { round, unit_id, column }  # telegraphed waves
  deployables      : array of { type, column, params }    # mines, shield gens, etc.
  wind_profile     : { enabled, start_round, ramp_per_round, ... }  # existing _WIND_CONFIG
  objective        : ObjectiveDescriptor   # see §9
  rewards          : array of reward ids    # granted on completion (used by map/events later)
  threat_tags      : array of String        # for map telegraphing ("electric", "swarm", "terrain")
```

The pieces already exist in code (`_WIND_CONFIG`, the reinforcement schedule, deployable placements, terrain seed) — this step **extracts them from the scene into a descriptor the scene consumes.** Once a stage is data, you can have many stages without new code, and the map (§7) becomes a graph of these descriptors.

> Stage descriptors can be authored as resources (`.tres`) for hand-built stages and/or generated procedurally for variety. Start with a couple of hand-authored descriptors; procedural stage generation is later content, not foundation.

---

## 6. Deck: From Combat-Local to Run-Persistent

The snuck-in deck feature is combat-local: `CombatManager` builds and shuffles `_DECK_LIST` (11 cards) in `setup()`, draws `HAND_SIZE = 5` each turn, reshuffles discard when the draw pile empties, AP is the only play limit. This is correct *combat-state* behavior and should stay.

The run-state change: **the persistent deck lives in `RunState.deck`; combat seeds its draw pile from a copy of it.**

- `RunState.deck` is the canonical card list, modified only **between** stages (rewards, shops, events, removal).
- On combat entry, the combat deck/hand/discard is built from a shuffled copy of `RunState.deck`. Hand/discard/draw order are combat state and reset each fight (§2).
- On combat exit, the combat deck state is discarded — the persistent deck is untouched by the fight.

This cleanly separates "the deck you've built" (run state) from "how it shuffled out this fight" (combat state). Deck-building mechanics (add/remove/upgrade cards) operate on `RunState.deck` and are a between-stage concern.

> Deck rotation *within* combat (draw/hand/reshuffle) is already decided and implemented. Deck *progression* between stages (how you acquire/remove cards) is a between-stage system that writes to `RunState.deck` — deferred to the reward/event work, but the persistent deck must exist now so combat can seed from it.

---

## 7. MapState — The Run Graph

Once stages are descriptors and runs persist, the map is a graph of stage descriptors with a player position that advances.

```
MapState
  nodes        : array of MapNode      # each wraps a StageDescriptor + node type
  edges        : adjacency             # which nodes connect to which
  current      : node id               # where the player is
  visited      : set of node ids
```

```
MapNode
  type         : COMBAT | EVENT | SHOP | BOSS | ...
  descriptor   : StageDescriptor or EventDescriptor or ...
  threat_preview : array of String     # threat_tags surfaced to the player (telegraphing)
```

**Start dead simple:** a linear sequence of 3–4 combat nodes, no branching, no events. Prove the loop: play stage → return to map → advance position → play next stage, with run state carrying through. Branching paths, node-type variety, and threat-telegraphing UI come after the linear loop works.

The map is also where threat-telegraphing lives (the enemy-behavior and positioning discussions): a node surfaces its `threat_tags` ("electric chains — dangerous to mechanical units") so the player can prepare. That's a read of descriptor data, not new combat logic.

---

## 8. Pre-Combat Placement

A pre-combat phase where the player positions the squad within a spawn zone. This is the stage-level agency established in the positioning discussion.

- The `StageDescriptor` defines a `spawn_zone` (a region of columns/rows).
- Before the fight begins, the player places each non-disabled squad unit within the zone.
- Information available at placement: enemy positions and types, terrain, telegraphed reinforcements; **not** exact enemy HP (the moderate-information model).
- On confirm, combat begins with units at chosen positions.

This can be a rough UI initially — its job is to write starting positions into combat state. The strategic depth (placing tanks front vs. back based on enemy targeting) emerges from the existing targeting/lock-on systems once placement is a choice rather than hardcoded.

> Disabled units do not deploy. If the whole squad is disabled, the run ends (loss condition).

---

## 9. Objective Evaluator

With stages as descriptors, objectives become data evaluated each turn against run/combat state, rather than a single hardcoded defeat-all check.

```
ObjectiveDescriptor
  type     : DEFEAT_ALL | SURVIVE_N | REACH_ZONE | HOLD_ZONE | ...
  params   : type-specific (N turns, zone region, target id, ...)
```

The evaluator runs each turn and returns ongoing / won / lost. Objective types:

| Type | Win condition | Notes |
|---|---|---|
| **Defeat all** | All enemies + reinforcements destroyed | ✅ Already implemented (gated on `_all_waves_spawned`) |
| **Survive N** | Endure until round N | Cheapest to add — it's the reinforcement clock inverted |
| **Reach zone** | A unit reaches an exit region | Needs zone definition + per-turn check |
| **Hold zone** | Keep a unit in a region for N turns | Combines reach + counter |

**Build the evaluator that makes objectives data, then add types incrementally.** Start with defeat-all (exists) plus survive-N (cheapest). Don't build all types up front — build the seam that makes them content.

Loss conditions are shared across objective types: whole squad disabled/destroyed, or objective-specific failure (e.g. exit overrun). The existing loss check generalizes into the evaluator.

---

## 10. Recommended Build Order

Sequenced by dependency. Each step is independently playable/testable and unblocks the next.

1. **Persist/discard boundary** (§2) — a written decision, not code. Gate for everything.
2. **RunState + RunUnitState objects** (§3) — the backbone container.
3. **Combat I/O contract** (§4) — convert combat from hardcoded setup to read-from/write-back. Validate with the two-stage HP-persistence harness (§4.3).
4. **StageDescriptor extraction** (§5) — move hardcoded schedules/placements/wind/seed into a descriptor the scene reads.
5. **Persistent deck** (§6) — `RunState.deck` seeds combat; combat no longer owns the canonical list.
6. **Objective evaluator** (§9) — make objectives data; add survive-N alongside defeat-all.
7. **MapState + linear map** (§7) — 3–4 node linear run; prove state carries through the full loop.
8. **Pre-combat placement** (§8) — squad positioning within a spawn zone.
9. **Squad selection** — a pre-run screen (rough/debug UI) that populates `RunState.squad`.
10. **Events & rewards** — last; richest, and depends on all of the above (run state to modify, map to sit on, resources to grant).

Steps 1–3 are the critical path; nothing else can be built or tested until the backbone and the combat contract exist. Steps 4–6 make the stage data-driven. Steps 7–10 build the run around it.

---

## 11. Design Decisions Locked

| Decision | Value |
|---|---|
| Three-layer state | definition / run state / combat state; run state is the missing middle |
| Source of truth | A single `RunState` (one owner, autoload or explicit) |
| HP persistence | Persists across stages; the run-deciding resource |
| Shields/armor/effects | Reset per combat |
| Deck | Persistent list in `RunState.deck`; combat seeds a shuffled copy; hand/discard are combat state |
| Stage | A `StageDescriptor` (data), not a bespoke scene |
| Objectives | Data evaluated per turn by a shared evaluator; types added incrementally |
| Map | Graph of descriptor-wrapping nodes; start linear |
| Placement | Pre-combat squad positioning in a spawn zone; moderate-information model |
| Disabled units | Persist as disabled; don't deploy; whole-squad-disabled ends the run |

---

## 12. Open Decisions

| # | Decision | Notes |
|---|---|---|
| 1 | `RunState` as autoload vs. explicitly passed | Agent's call; one source of truth either way |
| 2 | Stage descriptors hand-authored (`.tres`) vs. procedural | Start hand-authored; procedural is later content |
| 3 | Repair/replace/retire flow for disabled units | Design exists (card/engine doc); UI/economy detail deferred |
| 4 | Reward granting mechanism | Deferred to step 10; `StageDescriptor.rewards` reserves the seam |
| 5 | Slow HP regen between stages (if any) vs. only via consumables/faction | Tune later; persist/discard boundary doesn't depend on it |
| 6 | Map branching + node-type variety | After linear loop proven |
