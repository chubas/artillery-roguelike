# Artillery Space — Run Design & Build Philosophy
**Design Document · v0.1**

> This document defines the *shape of a run*: the tensions a build is built around, the multiple valid answers to each challenge, how a build is discovered rather than chosen, and the final boss as a four-leg "final exam." It is design guidance — for content creation (units, cards, artifacts) and for the technical systems that must support this structure. It is intentionally not a technical spec; it is the brief those specs serve.

---

## 1. The Central Fantasy

A run should feel like a **power-level progression discovered under pressure.** Early stages are modest — direct damage to a few enemies. Late stages are spectacular — dozens of deployed turrets chipping away, dome structures shielding your squad, shots that chain across the enemy line or carve cross/wave patterns through it, wind manipulated to wreck enemy fire, napalm spread across enemy territory, bosses with vast HP and few weak spots.

The player does not pick a build from a menu and execute it. The player **reads what the run offers, commits as the pieces appear, and adapts toward a known final challenge.** Build identity resolves around the middle of a run, not at its start — unless the player starts with a specific plan and gets lucky finding the pieces early.

---

## 2. The Four Legs of a Viable Build

Every build must develop a credible answer to four challenges. These are the axes the final exam tests (§7), so they are the axes every run is implicitly building toward. A build missing a leg fails; a build with redundant coverage of a leg is strong.

### 2.1 Scaling — can your engine grow fast enough?
The run escalates: tougher enemies, intensifying reinforcement waves, enemy accuracy locking in over time. A build that cannot ramp gets ground down before it can resolve the fight. Scaling is the "deal enough, fast enough" leg.

### 2.2 Reach — can you hit what matters, where it is?
Because the battlefield is 2D with terrain, "the backline" is not a row — it is a position: behind cover, on high ground, buried in a bunker. Reach is the combined problem of **multi-target** (hitting many) and **spatial access** (hitting the protected). It overlaps heavily with terrain (§2.4) — reaching a buried enemy is both a reach and a terrain problem.

### 2.3 Defense — can you survive long enough to win?
Incoming damage must be answered, and HP is the run-level resource that does not reset between stages — so unanswered damage compounds across the whole run. Defense has a mitigation dimension (armor / HP+regen / decoys) and a **spatial dimension unique to this game**: positioning, terrain cover, and breaking enemy lock-on are themselves defensive tools.

### 2.4 Terrain answer — can you work with the battlefield itself?
The game's signature leg. Terrain poses spatial problems no other roguelite has, and there are **six distinct relationships** a build can have with it (§4). A build needs at least one credible terrain relationship, because the final boss makes the arena itself part of the puzzle.

> **Content rule:** when designing any unit, card, or artifact, identify which leg(s) it answers. Most content should cleanly answer one leg; some should partially answer two; a rare few should be flexible enough to improvise a third. This overlap gradient is what lets a build missing a leg scrape through on creativity (§8).

---

## 3. The Core Tensions

The best builds live on tensions — axes where strengthening one side weakens the other. These are the decisions a build is *made of*. Content should be designed to sit clearly on one side of a tension, so choosing it means committing.

| Tension | One side | Other side |
|---|---|---|
| **Clump vs. spread** | Auras, adjacency buffs, networks want units clustered | AoE, explosives, chain attacks punish clustering |
| **Move vs. plant** | Hit-and-run avoids enemy lock-on | Dig-in / "didn't move" bonuses reward stillness |
| **Spend vs. bank** | All-in tempo, empty the action pool now | Conservative carryover, hold resources |
| **Now vs. later** | Burst, finishers, immediate damage | Poison, sacrifice, Faustian, scaling payoff |
| **Consistency vs. breadth** | Small focused pool ramps fast and reliably | Wide pool ramps slow but answers more legs |

Anti-synergies are healthy and intended. Armor (wants many small hits, shrug them) and HP-regen (wants to take damage and heal it) interfere rather than stack — and that is a *player-discoverable* tension, not a faction-enforced wall (§5). Some combinations are bad; learning which is depth.

---

## 4. The Six Terrain Relationships

Terrain is a recurring problem — "the enemy is behind, under, or above cover you can't directly hit" — with six incompatible solutions. Each is a *relationship*, not a single tool: a whole build can express one (drilling shots + bypass cards + a minor-drilling artifact all express "go through it"). The incompatibility is the point — a build commits to a relationship and the run rewards or punishes that commitment.

| Relationship | What it does | Strong against | Weak against |
|---|---|---|---|
| **Go through it** (drilling/bypass) | Ignore terrain, hit what's behind | Entrenched, buried enemies | Exposed enemies (paid for nothing) |
| **Remove it** (digging/demolition) | Carve terrain to expose targets | Cover, walls; compounds over a fight | Speed (two-step: dig then hit) |
| **Go over it** (arc mastery) | Lob over cover with trajectory skill | Ground cover | Overhead cover (domes, ceilings) |
| **Go around it** (precision) | Reach a point regardless of path | Specific weak spots (boss cores) | Crowds (inefficient, overkill) |
| **Make it irrelevant** (flooding/denial) | Blanket an area; position stops mattering | Spread-out enemies; low ground | Flat terrain; *digging ruins your own basins* |
| **Weaponize it** (collapse/displacement) | Drop terrain on enemies, knock them off | Enemies relying on terrain | Flying / hovering units |

> **Design discipline:** when creating a terrain-interacting thing, ask which of the six relationships it belongs to. If it belongs to none, or to all, it is probably a bad fit. This keeps the space coherent as it grows (the same principle as "effects are verbs on tags").

### 4.1 Terrain durability supports this
Terrain destruction is decoupled from unit damage: most shots do a flat low "dig" value regardless of their damage output; terrain-focused shots carry a high dig value or a DRILLING flag. This means unit power can scale dramatically without dissolving the battlefield, and **terrain destruction becomes its own build axis** (a demolition build invests in dig the way a damage build invests in attack). The strategic skeleton of a stage is built from tough/indestructible tiles (it survives the fight and keeps defining the space); the rest is carveable fill that erodes under sustained fire (craters accumulate, cover wears down — the "chipping away" feel).

---

## 5. Factions as Distributions, Not Partitions

**No mechanic is faction-exclusive.** Every faction can access every mechanic — armor, HP+regen, decoys, drilling, chaining, all of it. Factions differ in **prevalence and default lean**, not access.

- Armor is *prevalent* among Seekers — more Seeker units come armored by default, more Seeker content builds around it — but not every Seeker unit is armored, and a Seeker run need not be an armor build.
- A faction is a **weighted distribution over a shared mechanic space**, not a partition of it. "Shaman" means HP+regen pieces are common and armor pieces are rare in your natural offerings — not that armor is forbidden.

### 5.1 All builds are viable in all factions
Any build can be assembled in any faction — just not all equally easily. You can build armor in a Shaman run; it is simply not the path of least resistance, and you must find the supporting pieces, which may or may not appear. This is what makes **build identity resolve mid-run**: early on you don't know what your build will become; you read the uneven offerings and commit as pieces appear.

### 5.2 Cross-paradigm access comes through artifacts
Artifacts (run-level, acquired) are the **bridges** to paradigms a faction doesn't naturally lean toward — a hybrid power plant, a gear-swap enabler, an "all shots gain minor drilling" relic. The artifact makes an off-lean build *possible, intentional, and committed-to* rather than accidental. This is the right home for cross-paradigm pivots: earned and chosen, not default.

### 5.3 The prevalence knob is the key faction-balance lever
The bias must be **strong enough that faction identity is legible, loose enough that off-lean builds remain reachable.**
- Too weak → factions blur into three flavors of the same thing.
- Too strong → it's a partition model in disguise; off-lean builds become unviable.
- Target: *your faction's lean is clearly the easy path, but the other paths are walkable if you find the bridges.*

This is the most important tuning decision for faction design. Identity emerges from the distribution; flexibility is preserved by open access.

### 5.4 Faction defensive leans (prevalent, not mandated)
- **Seekers (Army):** armor — mitigation through stacked, regenerating armor; synergies that pay you for *having* armor. The fortress that hits back.
- **Shamans (Bio):** HP pool + regen — large health, regeneration, damage rolls off and comes back. The thing you can't kill because it keeps growing.
- **Awakened (Cell):** disposable proxies — decoys, beacons, summons that redirect or absorb damage *before* the mitigation pipeline. Nothing you hit was the real target.

Each faction must **independently solve all four legs** of the final exam (§7). A mono run must be winnable. This constraint forces each faction to be complete and prevents "this faction is just bad."

---

## 6. Build Discovery & The Act Structure

A run has a fixed number of acts (target: 3). Build identity is discovered across them, and faction access opens progressively **without diluting your own pool.**

### 6.1 The maturation arc
- **Act 1 — Form.** Establish your mono engine. Full focus, clean identity, no cross-faction access. The build takes shape from uneven offerings.
- **Act 2 — Patch.** Engine mostly online. One other faction unlocks as *additional* bonus rewards (not mixed into your offered pool). You patch a weak leg, not rebuild.
- **Act 3 — Finish.** Engine largely resolved. Both other factions accessible as bonus rewards. Find the synergistic piece or the gap-filler for the telegraphed exam.

This maps onto the natural acquisition rhythm: **collect → consolidate → optimize.**

### 6.2 Access without dilution
Cross-faction rewards are offered as **extra/additional rewards**, never mixed into your faction's pool. Your mono engine assembles at mono speed and reliability; off-faction pieces are pure upside layered on top. This separates *pool dilution* (the thing that slows a build) from *access* (the thing that helps it).

### 6.3 What cross-faction rewards should be
Bias cross-faction offerings toward the legs that **transfer cleanly** — reach, terrain, some scaling — and away from **defense**, where faction paradigms conflict (armor vs. regen don't stack). A Shaman should rarely be tempted by Seeker armor (an anti-synergy trap); a Shaman being offered a Cell precision strike or a Seeker terrain tool fills a real gap while respecting its identity. **Keeping defense mostly faction-internal is the firewall against seam-exploit builds.**

### 6.4 The test for whether this works
Do act 2–3 cross-faction rewards feel like *patches* or like *temptations to abandon ship*?
- Used to shore up a weak leg → working as designed.
- So good the player pivots their whole build around one → dilution sneaking back through the reward channel; fix is per-card (lower that card's standalone power so it's only good as a supplement).

---

## 7. The Final Exam (Boss Design)

Working backward from the boss defines what every build must be capable of. The final boss is not hard because of stats — it is hard because it **tests all four legs simultaneously**, and a build missing one falls over.

### 7.1 The four-leg test, simultaneous
- **Tests Scaling:** an attrition wall — vast effective HP across weak points/phases, plus escalating pressure. Can't ramp → ground down before the boss runs out of body.
- **Tests Reach:** weak points hidden behind the spatial problem — buried core, elevated/shielded points, exposed-then-recovered. Can't reach → can't damage what matters.
- **Tests Defense:** hits hard and wide — AoE, multiple simultaneous threats. Arrived with chipped HP and no mitigation → the boss finishes the run's attrition.
- **Tests Terrain:** the arena is the puzzle — weak points are a terrain-access problem, and phase transitions reshape terrain (collapse cover, flood low ground, transmute the field), locking out a build with no terrain relationship.

The legs are tested **at the same time, not in sequence.** No "scaling phase" then "defense phase" — every turn you scale *while* surviving *while* reaching *while* managing terrain. Simultaneity is what makes a missing leg fatal.

### 7.2 Two-tier structure
- **Penultimate boss** ("the Seraph"): tests three legs at moderate intensity. A real gate, beatable by most coherent builds — the "did you build a functioning engine" check.
- **Final boss** ("the Divinity"): tests all four at high intensity *and attacks your solution* — caps the dominant scaling vector, denies the easy reach, out-damages pure turtling, breaks your terrain setup on a timer. A broken (over-complete) build steamrolls it; a build missing a leg must get creative.

### 7.3 Telegraphed
The final boss and the broad shape of its exam are **known from run start**, so the player builds toward it deliberately (the game rewards forward planning). Lean: *mostly-telegraphed with one hidden twist* — you know all four legs are tested and the broad shape, but one specific punishment reveals in a late phase, forcing a single adaptation. This rewards preparation while preserving one creative-scramble moment.

Because the exam is telegraphed, **build decisions become informed responses to it.** "The exam punishes single scaling vectors" → maybe pursue breadth this run. "The exam is a pure attrition wall" → maybe mono consistency races it best. The whole run becomes a negotiation between what you're offered and what you know you'll need.

### 7.4 Multiple answers per leg
Because each leg has several valid answers, a telegraphed punishment doesn't force one build — it narrows you to *one of* a set. "This boss is dug in" → you need one of {drilling, precision, collapse}, not specifically drilling. Build freedom is preserved; the problem just can't be ignored. This is the genre's core promise: flexible answers to a non-negotiable question.

---

## 8. The Guiding Principle: Redundancy is the Reward, Scarcity is the Tension

- A **great run** has two answers to each leg and laughs at the boss. The reward for a strong run is overwhelming the exam.
- A **normal run** has one answer to each leg and sweats.
- A **missing-leg run** must improvise — repurpose a tool meant for one leg to barely cover another (a digging shot's collapse becomes a panic defense; a precision strike meant for the boss core snipes a threatening add).

That improvisation under a missing leg is the **skill ceiling**, and it is only possible because the legs *overlap* enough that tools can be repurposed in a pinch. This is why the content overlap gradient (§2's content rule) matters: most tools answer one leg, some answer two, a rare few are flexible enough to improvise a third. That gradient lets a missing-leg build scrape through on creativity instead of hitting a hard wall — the feel of "I shouldn't have won that, but I found a line."

---

## 9. Implications for Content Curation

A checklist for creating units, cards, and artifacts so the above holds:

1. **Tag each piece by which leg(s) it answers** (§2 content rule). Watch the overlap gradient across the whole content set.
2. **Place each piece clearly on one side of a tension** (§3). A piece that's "fine in any build" is filler — give it a synergy hook or cut it.
3. **Assign each terrain-interacting piece to one of the six relationships** (§4). None or all → redesign.
4. **Respect the prevalence knob** (§5.3). A faction's lean should be its common offerings; off-lean pieces exist but are rarer. Tune until identity is legible and off-lean builds stay reachable.
5. **Ensure each faction can solo all four legs** (§5.4) using only its prevalent content. If a faction can't answer a leg mono, that faction is incomplete.
6. **Bias cross-faction rewards toward transferable legs** (§6.3) — reach, terrain, scaling. Keep defense mostly faction-internal.
7. **Make cross-faction pieces supplements, not cores** (§6.4). If one is strong enough to pivot a whole build around, lower its standalone power.
8. **Route artifacts as the cross-paradigm bridges** (§5.2). Off-lean builds (armor in a Shaman run) should be enabled by found, committed artifacts — intentional, not accidental.

---

## 10. Open / To Tune

| # | Item | Notes |
|---|---|---|
| 1 | Exact prevalence strength per faction | The key faction-balance knob (§5.3) |
| 2 | Number of acts | Target 3; confirm by pacing tests |
| 3 | How much of the final exam is hidden vs. telegraphed | Lean: mostly telegraphed + one twist (§7.3) |
| 4 | Which specific legs each faction solves easily vs. awkwardly | Defines each faction's natural gap to patch |
| 5 | Cross-faction reward frequency in acts 2–3 | Enough to patch, not enough to pivot (§6.4) |
| 6 | Terrain dig values and late-game durability scaling | Keep terrain meaningful at all power levels (§4.1) |
