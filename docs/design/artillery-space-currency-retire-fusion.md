# Artillery Space — Currency, Retire, Fusion & Upgrade Slots
**Design Document · v0.1**

> Defines the single run currency (Shards) and its uses, the retire mechanic, the fusion mechanic, and the shared upgrade-slot pool. Conversion values (retire payout, essence strength) are **flat for now** — deliberately not scaled by unit history/level. A discrete per-unit prestige/leveling system was considered and explicitly deferred; see §6. This is a design spec for the remaining implementation pieces; it assumes the run-state backbone (`RunState`/`RunUnitState`) and the death/disabled mechanic already in place.

---

## 1. Shards — The Single Currency

**One currency, multiple competing uses.** No second spendable currency is introduced. The competition between uses *is* the intended tension — every Shard earned is a choice between expanding the engine (buy/upgrade) and stabilizing what exists (repair), and that choice should stay real throughout a run.

### 1.1 Naming and theme
Shards (full name: **Resonant Shards**) — fragments broken loose from Resonance-touched terrain and material. Faction-neutral mechanically; flavor text may describe them differently per faction (Seekers: extracted ore: Shamans: channeled residue: Awakened: reclaimed fragments) without any mechanical difference.

> Deliberately distinct from "Resonance" as a future escalation/difficulty mechanic — the name is chosen so the two systems never collide terminologically later.

### 1.2 Sources
- Terrain destruction (ties currency generation to combat moment-to-moment; a demolition-leaning build naturally generates more).
- Enemy kills.
- Stage completion.
- Optional sub-objectives (risk/reward — see the run-design discussion on tension; a sub-objective's reward is denominated in Shards so the payoff is legible against a legible cost).

### 1.3 Uses
| Use | Description |
|---|---|
| **Shop purchases** | Buying units, cards, artifacts, equipment offered between stages. |
| **Permanent upgrades** | Buying a stat/behavior upgrade onto a specific unit (consumes an upgrade slot — §5). |
| **Repair** | Restoring a disabled unit (cost scales with missing HP and repair history — established in the death/repair design). |
| **Deck thinning** | Removing a basic card from the deck permanently. |
| **Shop rerolls / scouting** | Rerolling shop offers, or revealing more about an upcoming node before committing. Absorbs the old "Intel" currency's role without a separate pool. |
| **Fusion / crafting cost** | If fusing a unit (§4) or any future crafting action carries a Shard cost, it draws from the same pool. |

### 1.4 Why one pool
Three separate currencies (shop / upgrade / repair) would let each be spent in its own lane with no friction between them — not a real choice. One pool forces a constant, legible allocation decision every time Shards are earned. Escalating repair cost (existing design) compounds this: as repair gets pricier over a run, the *relative* value of every other use shifts dynamically without retuning anything else.

---

## 2. The Three Paths for a Unit

A unit in the roster (active or disabled) can be resolved three ways. Each trades something different — this is the core design contrast and must remain legible to the player as three distinct buttons/choices, not variations of one.

| Path | Unit fate | Player gains | Cost |
|---|---|---|---|
| **Repair** | Stays in roster, restored | Nothing new — the unit returns to usable | Shards (scales with damage + repair history) |
| **Retire** | Removed from roster permanently | Flat Shards (fungible — spendable on anything in §1.3) | The unit itself; squad shrinks |
| **Fuse** | Removed from roster permanently | A specific essence (non-fungible — see §4) transplanted onto a chosen surviving unit | The unit itself; squad shrinks |

Repair is available to disabled units. Retire and Fuse are available to **any** unit, disabled or active — sacrificing a healthy unit is a valid, sometimes correct, choice (e.g. freeing a roster slot or capacity for a better-fitting unit).

### 2.1 Squad resilience is a separate, ever-present risk
Removing a unit via *either* Retire or Fuse shrinks the squad's aggregate effective HP and spreads incoming threats over fewer bodies. This risk is identical regardless of which path is chosen — it is not part of the retire-vs-fuse decision, it is the standing cost of *removing a unit at all*. A player consolidating aggressively into fewer, stronger units is knowingly trading redundancy for concentrated power; this should be felt, not hidden.

---

## 3. Retire

Removing a unit from the roster in exchange for a **flat** amount of fungible Shards.

- Flat value for now (not scaled by kills, history, or any per-unit investment — see §6 on why this is deliberate).
- The Shards gained are unrestricted — usable on any of the uses in §1.3.
- Retire is the "general resource" arm of the fork in §2: useful when the player wants flexibility rather than a specific power.

---

## 4. Fusion

Removing a unit from the roster in exchange for transplanting its **essence** — a specific, non-fungible ability — onto a chosen surviving unit.

### 4.1 Essence
- Each unit type carries a signature ability that fusion can transplant (e.g. the digger donates a minor drilling property onto the recipient's shots; the shield-builder donates a small aura).
- The transplanted essence is **always strictly weaker** than the donor unit's full battlefield presence. This is a hard rule: if a transplanted essence matched or exceeded having the donor unit on the field, fusion would dominate keeping units, collapsing the roster-building game.
- Essence strength is **flat per unit type for now** (not scaled by the donor's level, kills, or investment — see §6).

### 4.2 Why fusion's payout must stay non-fungible
Fusion must not also pay out significant Shards. If it did, fusion would simply be a strictly-better Retire (specific power *plus* currency), and the fork in §2 would collapse into one obviously-correct choice. Fusion's entire value proposition is the essence itself.

### 4.3 Relationship to the Awakened-specific fusion concept
Per the standing rule that no mechanic is faction-exclusive (factions are prevalence distributions, not partitions — see the run-design document §5), the previously-scoped "Awakened: two identical units fuse" mechanic is **a special case of this universal system**, not a separate one:
- Any unit can be fused into any other unit via this system.
- Fusing two units of the **same type** is a special case that should be cheaper or yield a stronger essence than a cross-type fusion.
- Awakened's fabrication/fragment-drop thematic content should lean toward this special case — e.g. Awakened-aligned artifacts that reduce fusion cost or improve essence retention — consistent with prevalence-bias rather than exclusivity.

### 4.4 Two use cases worth designing content for
- **Consolidation / scaling-carry:** sacrifice the rest of the roster to concentrate essences onto one growing carry unit. This is the concrete mechanism for the "Scaling Carry" build archetype named in the run-design document, which previously had no specific tool.
- **Cheap leg coverage:** bring a single-purpose unit (e.g. a pure digger) only long enough to use it, then fuse its essence onto a unit you're already running — answering a weak leg (per the four-leg framework) without permanently paying a roster slot for a narrow-purpose unit.

---

## 5. Upgrade Slots (Shared Pool)

Each unit has a limited number of slots, **shared between bought permanent upgrades and fused essences.** There is exactly one pool per unit, not separate pools per content type.

- Slot count is small and bounded (Monster Train precedent: 2 base, expandable via artifacts/content). Exact base count and expansion sources are tunable — not locked here.
- A slot holds either: a purchased permanent upgrade, **or** a fused essence. Both compete for the same limited space.
- This is what makes the retire/fuse choice and the upgrade-shopping choice interact: choosing to fuse a powerful essence onto a unit may mean that unit has no room left for a basic shield/armor upgrade. The tension is structural, not flavor — a shared pool is required for it to be real (an unshared pool would let a player have both, eventually, removing the choice).

> Slot expansion (more slots per unit via artifacts or rare upgrades) is an explicit lever for later balancing/content — not specified further here.

---

## 6. Deferred: Per-Unit Prestige / Leveling

A discrete per-unit leveling system (prestige points or level, gained from kills/survival/objectives, used to scale retire/fuse payout and/or grant additional slots) was discussed and **deliberately deferred, not rejected.**

- For now: **retire payout and essence strength are flat values per unit type**, with no per-unit scaling.
- The decision to defer is intentional: whether per-unit value-scaling is *needed* should be answered by playtesting the flat-value version first. If testing shows a clear gap — e.g. a long-lived, heavily-fielded unit feeling no different from a freshly-acquired one when retired or fused — leveling is the documented next step, not a redesign.
- If implemented later, the design direction already scoped (for reference, not built now):
  - Discrete levels (not a continuous XP bar), capped at a small number (e.g. 3), mirroring the existing slot-cap precedent.
  - Sourced from a passive channel (kills, turns survived) and a deliberate channel (sub-objectives that reward prestige to a chosen unit instead of/alongside Shards).
  - Retire/fuse payout scales with the unit's level at time of conversion.
  - Slot count tied to level (a unit's available slots grow as it levels), rather than introducing a separate slot type.
  - Open question for that future pass: whether leveling is uniform across factions or itself prevalence-weighted (e.g. Shamans lean toward faster leveling, Seekers toward slower-but-stronger slot payoffs).

This section exists so the framework already accommodates leveling without redesign if/when it's added — `RunUnitState` already tracks `kills`, which is the natural seed field.

---

## 7. Open Decisions

| # | Decision | Notes |
|---|---|---|
| 1 | Base upgrade slot count per unit (or per unit class) | Tune via playtesting |
| 2 | Slot expansion sources (artifacts, rare upgrades, other) | Content design, not locked here |
| 3 | Same-type fusion bonus magnitude (cheaper cost vs. stronger essence vs. both) | §4.3 |
| 4 | Whether fusion has a Shard cost in addition to the sacrificed unit | Currently unspecified; if added, draws from the single pool (§1.3) |
| 5 | Flat retire/fuse values per unit type | Content to author once unit roster is large enough |
| 6 | Whether/when to implement deferred prestige (§6) | Gate: playtesting signal that flat values feel insufficient |
