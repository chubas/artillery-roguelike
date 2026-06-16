# Artillery Space — Mechanics Compatibility Analysis
**Design Document · v0.1**

> A triage of candidate mechanics against the systems already specified. Each idea is tagged **Free** (data/config only), **One New System** (named, with its reuse surface), or **New System + Sharp Edge** (with the specific edge and the resolution rule to decide). Two consolidations at the end fold most ideas into general, reusable systems so nothing ships as a one-off.
>
> **The compatibility test for everything here: it must be deterministic.** Flow, displacement, teleport resolution, and artifact auras that introduce hidden randomness collide with the predictability the combat design depends on. Determinism is non-negotiable.

---

## 1. The Element × Mitigation-Layer Matrix (connective tissue)

This is decided first because several mechanics below depend on it (armor layer, poison, corrosion). It extends the existing `ElementDef` affinity model — instead of keying multipliers only to *unit tags*, elements also key multipliers to the *mitigation layer* they are currently hitting.

| Element | vs Shield | vs Armor | vs HP | Notes |
|---|---|---|---|---|
| Physical | normal | normal | normal | Baseline |
| Electric | **strong** | weak | weak | Shreds shields; useless once exposed |
| Corrosive | weak | **strong** | normal | Armor-eater |
| Explosive | normal | **strong** | normal | Structural / armor breaker |
| Fire | weak | normal | **strong** | Burns flesh, not plating |
| Poison | — (bypasses) | — (bypasses) | **strong** | Bypasses mitigation entirely (see §4) |

The design payoff: element choice now matters against **defensive composition**, not just unit type. An all-shield enemy line wants electric; an armored boss wants corrosive/explosive; an exposed HP-pool Shaman wants fire/poison. This also means the three faction defenses (Seeker armor / Shaman HP / Awakened proxies) inherit elemental weaknesses **for free**, without per-faction design — the weakness emerges from which layer the faction relies on.

> Architecture note: this is a multiplier lookup keyed on `(element, layer)`, applied inside the existing damage-resolution pipeline as damage passes through each layer. No new system — an extension of affinity resolution and the ordered mitigation stack already specified.

---

## 2. Free — Data and Small Extensions Only

These need only resources plus minor extensions to systems that already exist.

### 2.1 Armor as a third mitigation layer
Already specified (card/engine doc §5: armor → shield → HP). The new content is the §1 matrix. Armor reduces per-hit (strong vs. many small hits, weak vs. few big ones); shield is a flat pool; HP is the persistent floor. **No new system.**

### 2.2 Explosive objects
A tile or tile-status carrying the `EXPLOSIVE` flag (already in the M1 terrain schema) plus an AoE pattern fired on destruction. Barrels, crystals, mushrooms, and mine-launcher payloads are the same object varied by trigger and art. Chain-explosion logic already exists in the M1 destruction pipeline. **No new system.**

### 2.3 Poison
A status effect in the existing system with one new property: damage applies **directly to the HP layer**, bypassing armor and shield, and resolves at round end. Does not cause fainting — it is persistent attrition the player must answer. "Counters" and "affects some units more" are the §1 matrix and standard affinities. The only new concept — *damage that bypasses mitigation layers* — is a single flag on the element (`bypasses_mitigation`), reusable by corrosive or future effects. **Effect system + one reusable flag.**

---

## 3. One New System (clean, reusable)

### 3.1 Gravity-flow for projectiles and substances — "balls" + "liquid"
Both ideas are one mechanic: a thing that, after landing, continues downhill and accumulates in low points.

- **Balls:** projectiles that, on landing, roll toward the lowest adjacent open neighbor until they settle, then detonate. Strong into pits and clumped enemies; weak against high ground.
- **Liquid:** a substance that flows by the same rule and pools, carrying a payload (flammable, slowing, etc.) as a tile status.

**The one new system:** a deterministic **settling/flow pass** over the voxel grid. Rule: *each tick, the thing settles one voxel toward the lowest adjacent open neighbor; if none is lower, it rests.* Resolved in a fixed order. This is **not** fluid simulation (explicitly out of scope) — it is cheap, predictable, and deterministic.

**Reuse surface:** rolling bombs, pooling goo, flammable liquid, and future sand/lava all use it. Composes with terraforming cards (dig a pit → everything funnels in). 

**Constraint to lock now:** flow must be deterministic and fixed-order, or it breaks the no-execution-RNG stance and enemy predictability.

### 3.2 Structures / deployable artifacts
The one genuinely new *entity type*, worth it for the design space: shield-aura, action-battery (extra actions if used within radius), ally-amplifier, enemy-debuff aura — all one system varied by data.

- Occupy a **placement layer that does not collide with unit movement** but **shares the "1 per tile" rule with explosive objects.**
- Targetable and destructible. Clumping artifacts with units means AoE hits **both** — the built-in downside that balances them (the risk that offsets the radius benefit).
- **Auras emit effects into the same pipeline statuses use** — not a parallel resolution path. Fold artifact ticks into the existing fixed resolution order (effects doc §9.2) rather than inventing a new one. This is what keeps the system from getting complex.

**Reuse surface:** artificial shields (a structure that blocks projectiles), placeable deflectors, beacons, and most of the "Gunbound-like" grab bag (§4.3) reduce to this plus a keyword.

---

## 4. New System + Sharp Edge (resolve the edge before building)

### 4.1 Levitating units (threshold hover)
Not free-flying — a *max-voxels-above-terrain* constraint; some natural, some conditional (hover only over electrified terrain). A new movement **mode** layered on existing voxel movement.

**The sharp edge:** it interacts with many systems at once — collapse (does terrain destroyed beneath a hovering unit drop it?), gravity-flow (does liquid beneath matter?), targeting/cover (does hovering expose the unit?), and climb rules. None are blockers, but it is the idea most likely to create rule-interaction bugs.

**Resolution:** build hover **after** flow and artifacts exist, so its interactions are tested against stable mechanics rather than moving targets. Define base hover fully (including the four interactions above) before any conditional-hover variant. The "hover only over electric terrain" variants are a good build-around hook — but only once base hover is stable.

### 4.2 Teleport beams (and all relocation effects)
**The sharp edge you already identified:** what happens when the destination is blocked or would overlap another unit?

This is a placement-validity problem shared by *every* relocation effect — teleport beams, position-swap cards, future blink abilities. It needs **one consistent rule applied to all of them**, or it becomes a one-off. Options, cleanest first:

- **Fizzle** — no valid spot, effect is wasted (most predictable, harshest).
- **Nearest-valid-voxel** — snap to the closest legal position (forgiving, needs a deterministic "closest" tiebreak).
- **Swap** — if occupied, exchange positions (elegant for two-unit cases, ambiguous for terrain overlap).

**Resolution:** pick one rule here, before any teleport content exists, and route all relocation through a single "relocate unit safely" function. See consolidation §5.2.

### 4.3 Gunbound-likes — tornadoes, bouncing lines, artificial shields
A grab bag that mostly reduces to existing or already-planned systems:

- **Bouncing lines** → the `BOUNCING` shot keyword (already planned, M4) + optionally a placeable deflector (an artifact, §3.2).
- **Artificial shields** → a structure with a "blocks projectiles" property (artifact, §3.2).
- **Tornadoes** → a deflection field: a *projectile-affecting zone* that alters trajectories mid-flight. This is the one new concept, and it is an instance of the **positional-forces** consolidation (§5.1) — a localized, placeable wind source. Wind is already a deferred system (effects doc).

**Net:** keyword + artifact + the deferred wind/forces system. Little genuinely new work.

---

## 5. Consolidations — Turning Many Ideas Into Few Systems

The build-around-it principle in action: rather than implement each idea separately, define the two general systems they plug into.

### 5.1 Positional Forces (flow + wind + deflection + push/pull)
Balls, pooling liquid, tornadoes, and wind hazards all want the same underlying thing: **forces that act on things by position** — whether in motion or at rest.

- **Gravity-flow** (downhill settling) and **wind/deflection** (lateral push) are two instances of one idea.
- Build them as a shared concept — *a force field that displaces tagged things by a rule* — and you get balls, pooling liquid, tornadoes, wind, and future push/pull from one system.
- This mirrors the effects-doc emergence principle exactly: **forces are verbs that act on tags, not on specific objects.** A tornado displaces anything `DISPLACEABLE`; gravity-flow settles anything `SETTLES`; a shot tagged `HEAVY` ignores both.

Nine-ish ideas collapse toward roughly three real systems through this lens.

### 5.2 Safe Relocation (teleport + swap + blink + knockback-into-wall)
Every effect that moves a unit to a new position — teleport beams, position-swap cards, blink, even forced displacement that might end inside terrain — shares the placement-validity problem from §4.2.

- Define **one** "relocate unit safely" resolution rule (fizzle / nearest-valid / swap) and route all relocation through it.
- Teleport beams, swap cards, and displacement forces all become consumers of this one function rather than each re-solving overlap.
- Decide the rule once (§4.2) before any relocation content exists.

---

## 6. Build Order Recommendation

Sequenced so each system is built against stable dependencies:

1. **Element × layer matrix** (§1) — pure data/extension; unblocks poison, corrosion, armor identity.
2. **Armor layer content + poison** (§2) — free, immediate design payoff.
3. **Explosive objects** (§2.2) — free, reuses M1 chain logic.
4. **Positional Forces system** (§5.1) — enables balls, liquid, and later tornadoes/wind.
5. **Structures / artifacts** (§3.2) — enables auras, artificial shields, deflectors, beacons.
6. **Safe Relocation rule** (§5.2) — decide rule; unblocks teleport and swap content.
7. **Levitating units** (§4.1) — built last, against now-stable flow/artifact/collapse systems.

---

## 7. Summary Table

| Idea | Verdict | Plugs into |
|---|---|---|
| Armor layer | Free | Mitigation stack + §1 matrix |
| Element-vs-layer matrix | Free (extension) | Affinity resolution |
| Explosive objects | Free | M1 destruction + EXPLOSIVE flag |
| Poison | Free (+1 flag) | Effect system + `bypasses_mitigation` |
| Balls | One new system | Positional Forces (§5.1) |
| Liquid | One new system | Positional Forces (§5.1) |
| Structures / artifacts | One new system | New entity type (§3.2) |
| Artificial shields | Free | Artifact (§3.2) |
| Bouncing lines | Free | `BOUNCING` keyword + artifact |
| Tornadoes | New system | Positional Forces (§5.1) |
| Levitating units | New system + sharp edge | Movement mode (§4.1) |
| Teleport beams | New system + sharp edge | Safe Relocation (§5.2) |

---

## 8. Open Decisions

| # | Decision | Where |
|---|---|---|
| 1 | Exact multipliers in the element × layer matrix | §1 (values to tune) |
| 2 | Flow tick rule and resolution order | §3.1 |
| 3 | Artifact aura resolution timing within the fixed order | §3.2 |
| 4 | The single Safe Relocation rule (fizzle / nearest / swap) | §4.2, §5.2 |
| 5 | Whether positional forces and the deferred wind system are built as one | §5.1 |
| 6 | Hover's four interaction rules (collapse, flow, cover, climb) | §4.1 |
