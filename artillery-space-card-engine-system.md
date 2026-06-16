# Artillery Space — Card and Engine System
**Design Document · v0.1**

> This document defines the card system, the permanent-vs-drawn progression split, the mitigation model (HP / armor / shield), the per-faction defensive identities, the scaling-race combat model with reinforcements, and the build archetype and synergy framework. It is a design specification: it names the systems that must exist and how they should behave, and leaves implementation detail to the coding agent.

---

## 1. Core Philosophy

Artillery Space is a strategy game first, with artillery skill and spatial positioning as expression layers. The card and engine system adds a third layer: **a run-long engine you progressively refine, played out under a single shared resource in combat.**

The intended feel, in one sentence: *every turn you are choosing between firing, moving, defending, and playing cards from one pool of actions, while racing to spin up your engine before escalating reinforcements overwhelm you.*

Three principles govern every decision in this document:

1. **One resource, many demands.** Movement, firing, special shots, and card play all draw from the same shared action pool. Tension comes from the pool being insufficient to do everything. (See §4.)
2. **Permanents enable, cards intervene.** Permanent upgrades and per-turn passives form the engine and mostly cost no actions to "run." Drawn cards are tactical interventions that cost actions. The engine scales passively; cards are the active choices that compete with artillery. (See §3, §4.)
3. **Synergy has direction.** Cards and upgrades are designed to be exceptional in one build archetype and weak outside it. Players must actively reject off-archetype cards. A card that is "fine in any deck" is filler and should be cut or given a synergy hook. (See §6, §7.)

---

## 2. The Economy Stack

Four distinct economic layers, each acquired and limited differently. Keeping them separate is what makes builds legible.

| Layer | What it is | Persistence | How acquired | How limited |
|---|---|---|---|---|
| **Roster capacity** | How many units you can field | Whole run | Capacity grows on act-boss defeats | Hard capacity cap (units cost capacity) |
| **Permanent upgrades** | Stat/behavior changes baked into a unit | Whole run | Shops, rewards, crafting | Limited upgrade slots per unit |
| **Equipment / cards** | Drawn, played in combat for an effect | Whole run (in deck); single-use in combat | Combat rewards, shops, events | Deck composition; action cost to play |
| **HP** | Run-level health resource | Persistent across stages (does not reset) | Slow regen, rare consumables, faction mechanics | The run-ending resource (see §5) |

The reader should treat these as four taps that each fill a different reservoir. A run's identity is the *shape* of these four together: a small high-upgrade roster plays nothing like a wide low-upgrade swarm.

> The in-between-stages interface for spending in these economies is **out of scope for now** — a rough debug UI is acceptable. What matters is that the systems cleanly separate permanent changes (written to persistent unit state) from deck changes (adding/removing cards), so both can be designed and tested. (See §10.)

---

## 3. Permanent Upgrades vs. Drawn Cards

This is the Monster Train model: a unit can have a permanent ability *and* a card that magnifies it. Both must exist and they must interact.

### 3.1 Permanent upgrades

- Baked into a unit for the rest of the run; always active, no action cost to "have."
- Limited by upgrade slots per unit (light units fewer, heavy/commander more).
- **Should mostly change how a unit or its cards behave, not merely inflate numbers.** "This unit's shots gain an element" or "this unit grows on kill" over "+10 attack." Pure stat upgrades exist but are the *floor* — common, low-excitement, connective tissue.
- Enable build-defining single-unit strategies: a scaling unit whose permanent upgrade grows it on every kill, such that the whole run is built around feeding it kills to carry the late game. Overpowered single units are acceptable **if the build pays a tradeoff** (capacity, fragility, setup dependence).

### 3.2 Drawn cards / equipment

- Live in a run-long deck; played during combat for a one-time effect; cost actions from the shared pool.
- The active, tactical layer. This is where in-combat decisions and combos happen.
- Designed around archetypes (see §6) so they synergize with specific permanents, shot types, and elements.

### 3.3 The interaction is the point

A permanent "dual shot" on a unit, plus a drawn "next shot fires twice" card, plus a "+damage while at full shield" upgrade — stacked in one turn — is the kind of multiplicative payoff the engine is built to produce. The stat-resolution pipeline (flat bonuses first, then multipliers) must make these stacks predictable so players can plan combos rather than discover them by accident.

---

## 4. The Shared Action Pool (the single resource)

**Decision locked:** movement, firing, special shots, and card play all draw from one shared per-turn action pool.

- Firing a basic shot remains free and ends that unit's activation (established in prior milestones); everything else costs actions.
- Cards have an action cost. Expensive cards are a build-defining constraint: some builds are action-hungry and the challenge is *finding additional energy sources*; other builds run lean and the challenge is *finding the right synergy* with few actions.
- Defending against weak reinforcement waves may force you to spend actions you wanted for your engine — that is the intended tension.

### 4.1 Engine runs passively, cards cost actions

To make the scaling-engine fantasy survive a shared pool, **the engine must scale without taxing the pool.** Per-turn passives and permanent upgrades (a unit that buffs allies each turn, a unit that grows on kill, armor that regenerates) fire automatically and cost no actions. Drawn cards — the active interventions — cost actions. This keeps two things simultaneously true: the engine can snowball, and every *card* is a real choice against firing or moving.

### 4.2 Energy as a design space

Because there is one pool, **action economy is itself a build axis.** Cards/upgrades that generate extra actions, reduce card costs, or grant free single-use plays become powerful enablers for expensive builds. This is a deliberate synergy surface, not an afterthought.

### 4.3 Deferred: deck rotation mechanics

How cards cycle — a draw pile, a hand, a refreshing market, fixed loadout — is **deliberately left open.** For now, assume cards are available to play from the deck and cost actions. Draw/hand mechanics, deck-thinning, and consumed/one-time cards are a later decision. The systems below must not assume a specific rotation model.

---

## 5. Mitigation Model: HP / Armor / Shield

Three distinct mitigation layers, mechanically different, resolved in order. They are **not interchangeable** — that distinctness is what lets factions build around different ones.

| Layer | Scope | Regenerates | Mitigation style | Role |
|---|---|---|---|---|
| **Armor** | Per-combat | Yes (per-combat, some per-turn) | Reduces damage per hit | Strong vs. many small hits; weak vs. few big hits |
| **Shield** | Per-combat | Yes (between stages free; some per-turn) | Flat absorb pool | The liberally-spent tactical buffer |
| **HP** | Run-level | Barely (slow / rare / faction) | The floor | The precious, run-deciding resource |

Damage resolves armor → shield → HP. Each layer can have its own hooks (e.g. electric is ×2 vs. shielded targets; armor-scaling reads the armor value; HP regen touches only the bottom layer).

### 5.1 Why HP-as-resource is the run

HP does not reset between stages, so tanks wear down over a run and every point of HP damage is a strategic cost. This is the backbone established earlier (death/repair mechanic). The mitigation stack exists so that *skilled play keeps damage in the armor/shield layers and never reaches HP* — and the run tightens as that becomes impossible.

### 5.2 The exception is a faction identity

The Shamans (Bio) break the HP-attrition rule on purpose: their units regenerate HP, so for them HP is a renewable buffer rather than a finite floor. This is the seed of the per-faction defensive identities below — the universal rule (HP is precious) becomes a faction lever (one faction ignores it).

---

## 6. Per-Faction Defensive Identities

Defense is an **identity axis**, not universal filler. The same incoming damage should feel completely different across three runs, and defensive cards/upgrades should be build-defining for one faction and near-useless for another.

### 6.1 Seekers (Army) — Armor

Mitigation through stacked, regenerating armor. Synergies pay you *for having armor*: attack that scales off current armor, armor that doesn't fully decay, effects that trigger when armor is high. The "fortress that hits back." Armor-scaling cards are build-defining here and dead weight for Shamans.

### 6.2 Shamans (Bio) — HP pool + regen

No armor; instead, large HP pools and regeneration. Damage rolls off because there is always more HP and it comes back. The run-level HP-attrition pressure is softened for them specifically. The "you can't kill what keeps growing." Regen and HP-pool cards are theirs.

### 6.3 Awakened (Cell) — disposable proxies

Don't tank damage — redirect it. Decoy units, beacons that pull aggro, summons whose purpose is to die or absorb. Mitigation happens *before* the damage pipeline by intercepting it elsewhere. The "nothing you hit was the real target." Proxy/decoy cards are theirs.

> Armor is a universal mechanic any unit can interact with, but only some builds are *about* armor. The same holds for HP-stacking and for proxies. Universality at the floor, identity at the ceiling.

---

## 7. Build Archetypes and Synergy

Archetypes anchor to the shot identities already established. Each archetype *wants* certain things and *rejects* others. The design rule: **every card and upgrade should make at least one archetype say "yes!" and at least one say "useless to me."**

| Archetype | Wants | Payoff | Anti-synergy |
|---|---|---|---|
| **Chain / Electric** | Enemies clustered; terrain conductive; multi-target shots | One shot chains through the enemy line | Single-target burst |
| **Burn / Spread** | Terrain on fire; enemies standing in zones; status stacking | Damage-over-time across a controlled area | One-shot assassination |
| **Precision / Burst** | Raw stat increases; guaranteed hits; multi-shot | Delete a priority target in one turn | Slow attrition / spread |
| **Terrain Control** | Reshape battlefield; walls, kill zones, denial | Win through position, not damage | Builds needing open terrain |
| **Momentum / Sacrifice** | Trade HP/shield for power; reward low resources; escalation | Overwhelm before you die | Defensive turtle builds |
| **Scaling Carry** | Feed kills/triggers to one growing unit | One unit carries the late game | Even-power, go-wide builds |

These extend rather than replace earlier archetype sketches. Factions lean toward some archetypes but do not own them — a Seeker terrain-control build and a Shaman terrain-control build should feel different.

### 7.1 Synergy lives at intersections

The most interesting cards do little alone and a lot in context. "Convert terrain to conductive" is mediocre by itself and build-defining in a Chain build. Treat **setup → payoff across turns, mediated by terrain and board state** as a first-class card category (see §8), distinct from immediate-effect cards. This is the differentiator from non-spatial deckbuilders: card value depends on the battlefield, not just on the card.

### 7.2 Basics are the floor, not the ceiling

Basic cards (restore shields, small direct damage) are common, always-okay, and never exciting. Their job is reliable connective tissue. If basics are too strong, players never commit to an archetype and synergy direction collapses. Excitement lives in the rarer, riskier, archetype-pulling cards.

---

## 8. Card Categories

Organized by which substrate they touch — the same three substrates as the effects system (units, tiles, projectiles) — so the card system stays consistent with existing architecture. A fourth category covers engine/economy effects.

### 8.1 Unit-targeting (familiar deckbuilder layer)
Heal HP (rare, precious); restore shields/armor (common); direct damage (guaranteed, bypasses artillery skill, limited); stat buffs; instant position swap; grant a status to ally or enemy.

### 8.2 Terrain-targeting (signature layer)
Raise cover voxels; collapse a column; terraform ramps for mobility; place hazards (goo, mine, electrified tile); convert terrain tags (FLAMMABLE, CONDUCTIVE) as setup for elemental payoffs.

### 8.3 Projectile / shot-modifying (synergy engine)
Next shot gains an element; next shot gains a keyword (piercing, bouncing, cluster); next shot fires twice; next shot doubled AoE. These magnify permanents — the "2× a permanent dual-shot" combo lives here.

### 8.4 Engine / economy (the scaling layer)
Per-turn passives (mostly permanents, no action cost); action-generation and cost-reduction effects (the energy synergy surface from §4.2); single-use setup pieces with outsized one-time impact.

---

## 9. Combat Pacing: The Scaling Race with Reinforcements

**Decision locked:** combats use **reinforcement waves with telegraphed arrival**, not a fixed enemy snapshot.

- A combat starts with a small initial enemy force and escalates as reinforcements arrive over turns.
- Reinforcements are **telegraphed in advance**: a countdown ("reinforcements arrive in 2 turns") and a predictable landing indicator showing where they will appear.
- This creates the engine race: the player must scale their engine faster than the reinforcements escalate the threat.
- Enemy escalation combines arriving units with the **progressive accuracy lock-on** mechanic established earlier — standing still gets you dialed in, so escalation is partly positional pressure, not just stat inflation.

### 9.1 Stage as a timeline, not a snapshot

A stage is defined as a **timeline of spawns plus an objective evaluated each turn**, not a static board. This single abstraction yields all the level types as data variations rather than separate systems:

- **Defeat all** — clear the initial force and all reinforcements.
- **Survive / hold** — endure until the reinforcement clock runs out (hold N turns).
- **Escape** — reach an exit zone before being overwhelmed.
- **Capture / objective** — reach or hold a location.

Different objectives and spawn timings produce different pacing and tension. Some level types may be left out at first, but the timeline abstraction should be built to **accommodate the full design space** so new level types are content, not new code.

### 9.2 Turn counts are unresolved

Exact combat length and per-level-type pacing are **open and will be tuned through testing.** The systems must not hardcode assumptions about combat length; pacing parameters (initial force size, reinforcement schedule, objective thresholds) belong in stage data.

---

## 10. Persistent State Separation (the backbone)

The single most important structural requirement for everything above: a clean separation between **what a unit type is**, **what a specific unit has become this run**, and **what a unit is doing in this combat.** Three layers:

- **Definition** — immutable, shared: the unit/card/element type.
- **Run state** — mutable, persists across stages: a specific unit's current HP, accumulated permanent upgrades, kill/scaling counters, repair history, equipment; and the run's deck composition.
- **Combat state** — runtime, per-combat: shields, armor, statuses, position, exhausted/done.

A combat instantiates combat state *from* run state (reading current HP, applying permanent upgrades and equipment) and writes results *back* to run state at combat end (new HP, new kills, scaling progress).

This separation is what makes the roguelite layer possible:
- **Permanent upgrades** are written to run state and reapplied each combat.
- **Scaling units** are a run-state counter incremented on the relevant trigger and folded into derived stats.
- **HP-as-resource** works because HP lives in run state and is not reset by combat.
- **Deck building** is editing the run-state deck; **card play** is consuming from it in combat.

Designing and testing cards requires only that this separation exists and that the deck can be edited (even via debug UI) and consumed in combat. Polishing the between-stages interface is explicitly later work.

---

## 11. Open Questions

| # | Question | Status |
|---|---|---|
| 1 | Deck rotation: draw pile, hand, refreshing market, or fixed loadout? | Open (§4.3) |
| 2 | Exact combat turn counts and per-level-type pacing | Open, tune by testing (§9.2) |
| 3 | Deck-thinning and consumed/one-time card mechanics | Open (§4.3) |
| 4 | Action-generation balance — how much extra energy expensive builds can find | Open, balance later (§4.2) |
| 5 | Between-stages interface | Deferred — debug UI acceptable for now (§2, §10) |
| 6 | Exact armor/shield regen rates and per-turn values | Open, tune by testing (§5) |

---

## 12. What This Document Commits To

For the coding agent, the systems that must exist (detail left to implementation):

1. **Three-layer state separation** — definition / run state / combat state, with instantiation and write-back. (§10)
2. **Layered stat-resolution pipeline** — base + flat (permanents, equipment) then × multiplicative (cards, statuses), single central resolver. (§3.3)
3. **Ordered mitigation pipeline** — armor → shield → HP, each a distinct layer with its own rules and hooks. (§5)
4. **Shared action pool** covering movement, firing, special shots, and card play; passives/permanents run free, cards cost actions. (§4)
5. **Card system** — cards as run-state deck entries, played in combat, organized by substrate (unit / terrain / projectile / engine), action-costed. (§8)
6. **Permanent upgrade system** — slot-limited, written to run state, behavior-changing over stat-inflating. (§3.1)
7. **Stage-as-timeline** — initial force + telegraphed reinforcement schedule + per-turn objective evaluation, all from stage data. (§9)
8. **Per-faction defensive hooks** — armor-scaling (Seekers), HP regen (Shamans), damage-redirect proxies (Awakened). (§6)

Explicitly **not** committed yet: deck rotation/draw mechanics, combat length tuning, the between-stages interface beyond debug functionality.
