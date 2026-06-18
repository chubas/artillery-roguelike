# Artillery Space — UI and Visual Indicators
**Design Document · v0.1**

> Defines the three-tier information hierarchy, the AoE zone/preview model, and the defensive-layer readability approach. This is a design spec — it states what must be communicated and how, leaving rendering detail to implementation. The guiding goal throughout: **a player should be able to look at the board and make a correct tactical decision without doing arithmetic or hovering.**

---

## 1. Core Principle: Three Tiers of Visibility

The world is large and zoomable; units are small. Information cannot all live on the sprite (too small) and cannot all require hover (too slow). It is split across three deliberate tiers by *when the player needs it*.

| Tier | Where | When read | Contains |
|---|---|---|---|
| **On-map** | Rendered into the world at the point of action | While aiming / planning | Shot previews, AoE footprint, aim arc, enemy wave drop zones, reinforcement countdowns, hazard telegraphs |
| **Unit icon** | Attached to the unit sprite, always visible at any zoom | At a glance, every turn | Defensive bars (HP/armor/shield), status effect icons, acted/not-acted state, selection highlight |
| **Detailed view** | Panel shown on hover or click | When the player wants exact values | Full stats, exact numbers, status durations, affinities, equipped shots, upgrades |

The trap to avoid: forcing the sprite to carry everything, or forcing everything behind hover. The split above is the design — glanceable on the sprite, actionable on the world, exhaustive on hover.

---

## 2. AoE Zones — The Two-Tier Strength Model

### 2.1 Decision: two strength tiers, shown as zones, never as numbers

AoE strength is communicated as **two visually distinct zones**, not numeric damage:

- **Core zone** — full strength, `1.0×` multiplier
- **Edge zone** — partial strength, `0.5×` multiplier

Two tiers is deliberate. Three would require a legend; two is learnable at a glance (solid = core, faded = edge). A third tier may be added later only if a pattern genuinely needs it, but two is the default and the target.

### 2.2 Damage = unit strength × zone multiplier

The zone multiplier is **separate from unit strength.** Final damage = the firing unit's current strength × the zone's multiplier.

- The AoE pattern defines the *shape and the tiers* (which voxels are core, which are edge).
- The unit defines the *magnitude*.
- Upgrading a unit's strength scales every shot's whole footprint proportionally; the **shape the player learned stays constant.**

This is the key readability win: **patterns become a vocabulary the player learns once.** Only magnitude changes with upgrades, never the learned shape. This maps directly onto the existing `AoEGroup` system — core and edge are simply groups with different multipliers.

### 2.3 Visual encoding of tiers

Tiers are distinguished by **visual weight**, so the player reads them without reading math:

- Core zone: high intensity — solid fill, strong color, thick border.
- Edge zone: low intensity — faded fill, lighter color, thin or dashed border.

The player internalizes "solid = direct/full, faded = splash/partial" and never needs a number. Numbers live in the detailed view only.

### 2.4 Patterns are not always diamonds

The zone model must support arbitrary patterns — diamond, circular, **linear, cross, or irregular** shapes. Because tiers are defined per-voxel in the pattern data, any shape is expressible. The visual system must render whatever set of core/edge voxels the pattern specifies, not assume a radial shape.

---

## 3. AoE Preview (On-Map Tier)

### 3.1 Preview renders against actual terrain, not the abstract shape

**Critical:** the AoE preview must show the pattern **as it will actually resolve against the current terrain and unit positions** — not the clean abstract shape.

A diamond hitting a slope does not affect a clean diamond of space: some voxels are solid, some hold units, some are already destroyed. A preview that shows a clean diamond when the real result is "half buried in a hill" is **worse than no preview**, because it lies to the player.

This is more work than a flat-grid tactics game but it is essential and non-negotiable. It also doubles as a teaching tool: the player watches the pattern conform to terrain and learns that **terrain shape changes outcomes** — which is core to the game's identity.

### 3.2 What the on-map preview shows while aiming

- The aim arc / trajectory ghost.
- The predicted impact point.
- The AoE footprint at the impact point, in core/edge tier colors, conformed to terrain.
- Highlight of any unit (ally or enemy) whose hitbox falls in the footprint, indicating it will be hit and in which tier.

### 3.3 Shot pattern signature icon (shot-selection UI)

Separately from the world preview, the **shot itself carries a small pattern glyph** shown in the shot-selection UI — a tiny silhouette of the pattern shape (diamond, line, cross, etc.).

- The **world preview shows *where*** the shot lands.
- The **pattern icon shows *what kind*** of shape it is, before aiming.

Both are needed: shots are both selectable (like cards) and spatial events (aimed). Linear, cross, and diamond shots become recognizable silhouettes at selection time.

---

## 4. Unit Icon Tier (Always Visible)

A minimal, always-on glyph set on each unit sprite — enough to make a basic tactical decision **without hovering.**

### 4.1 Defensive bars — layered and color-coded

The three mitigation layers (armor / shield / HP) are shown as a **segmented, color-coded bar** above the unit, following the proven Borderlands convention:

- **Shield** — one color (e.g. blue)
- **Armor** — a second color (e.g. yellow)
- **HP** — a third color (e.g. red/green)

Stacked and depleting in resolution order (armor/shield deplete before HP, matching the damage pipeline).

**Why this matters:** the entire element-vs-layer system is only as good as the player's ability to *see* which layer they're hitting. The bar's **color composition tells the defensive makeup at a glance** — a mostly-blue enemy is a shield wall (bring electric); a mostly-yellow enemy is armored (bring corrosive). The element-matchup decision becomes a **color-matching decision.** If defensive composition isn't glanceable here, the matrix becomes invisible depth — present in the math, absent from the decision.

### 4.2 Status effect icons — with overflow cap

Active status effects show as small icons on/near the sprite, with a stack count where relevant (Monster Train convention).

**Decision: cap the number of visible status icons.** The design is status-heavy (burn, shock, poison, chill, marked, corrode, and more, all potentially stacking). On a small sprite, uncapped icons become unreadable soup. Show up to a fixed number (e.g. 3–4) and roll the rest into a **"+N" overflow indicator** that the detailed view expands.

- Good vs. bad statuses should be visually distinguishable (e.g. color-coded border or tint) so the player reads "this unit is buffed / debuffed" at a glance.

### 4.3 Acted / not-acted state

A clear visual for whether a unit has acted this turn (e.g. desaturated when done, as established in earlier milestones). The player must see at a glance which units still have actions available.

### 4.4 Selection highlight

The currently selected unit is clearly highlighted (border/outline). Established in prior milestones; unchanged.

---

## 5. Detailed View Tier (Hover / Click)

The exhaustive layer — the Monster Train mouseover. Shown on hover or click of a unit. Contains:

- Exact HP / armor / shield values (numbers).
- Full status list with exact stack counts and remaining durations (including overflow from §4.2).
- Element affinities and which mitigation layers the unit relies on.
- Equipped shots and their patterns.
- Permanent upgrades on the unit.
- Strength value (so the player can compute exact AoE damage if they want: strength × tier multiplier).

This tier is where numbers live. The other two tiers stay number-free.

---

## 6. Other On-Map Indicators

Beyond shot previews, the on-map tier also carries the spatial information established in other systems:

- **Enemy wave drop zones** — where reinforcements will land (telegraphed in advance).
- **Reinforcement countdown** — turns until the next wave arrives.
- **Enemy intent / targeting** — which unit an enemy will fire at, with the lock-on calibration indicator (🔓 / 🔒) established in the enemy-behavior discussion.
- **Hazard telegraphs** — meteor shadows, rising flood levels, mine locations, etc., shown at their world position.

All of these render into the world at the relevant location, consistent with the on-map tier principle.

---

## 7. Prototype Scope

The minimum to validate readability (polish is separate, later work):

1. **Two-tier AoE preview on the world** — core voxels bright, edge voxels faded, rendered against actual terrain at aim time (§3.1).
2. **Layered defensive bar** — even as flat colored rectangles — so element-matchup decisions are visible (§4.1).
3. **Minimal sprite glyph set** — defensive bar + status icons (with overflow cap) + acted/not-acted indicator (§4).
4. **Hover for exact numbers** (§5).

The question this scope answers: *can a player look at the board and make a correct tactical decision without doing math?* If yes, the system works and the rest is polish. If the player still hovers constantly to decide, the glanceable layer isn't carrying enough — tune from there.

---

## 8. Design Decisions Locked

| Decision | Value |
|---|---|
| AoE strength tiers | Two (core `1.0×`, edge `0.5×`); third only if a pattern needs it |
| AoE strength communication | Visual zones, never numbers (numbers in detail view only) |
| Damage model | unit strength × zone multiplier; pattern defines shape, unit defines magnitude |
| Preview fidelity | Must conform to actual terrain and unit positions, never abstract shape |
| Pattern signature | Small shape glyph in shot-selection UI, separate from world preview |
| Defensive layers | Layered color-coded bar (Borderlands convention); composition readable at a glance |
| Status icons | Capped visible count + "+N" overflow; good/bad visually distinguished |
| Information tiers | On-map (action) / unit icon (glance) / detailed (hover-click) — numbers only in the last |

---

## 9. Open Decisions

| # | Decision | Notes |
|---|---|---|
| 1 | Exact colors for each mitigation layer | Suggest Borderlands-like (shield blue / armor yellow / HP red-green); confirm in art pass |
| 2 | Visible status icon cap (3 vs. 4) | Tune against worst-case crowded unit |
| 3 | Whether edge-zone uses dashed vs. faded border | Visual test; pick the more legible at gameplay zoom |
| 4 | Exact tier multipliers (0.5× edge) | Tunable; could vary per pattern later if needed |
| 5 | How the pattern signature icon scales for irregular shapes | Ensure linear/cross/weird shapes stay recognizable at small size |
