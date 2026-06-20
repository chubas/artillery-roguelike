# Artillery Space — Debug Content Sandbox
**Technical Specification · v0.1**

> A debug overlay for rapid content authoring and synergy testing: spawn any unit/enemy, inject any card/artifact, regenerate terrain, and fast-forward combat state — all routed through the **same production entry points** a real run uses, never a parallel path. Includes scenario save/load for both interactive iteration and headless regression testing.

---

## 1. The One Constraint That Matters

**The sandbox must construct a `RunState` and a `StageDescriptor` and hand them to `CombatBridge` exactly as a real run does. It must never mutate combat state through a separate code path.**

Rationale: a debug tool that pokes at internals directly risks two failure modes — "fixing" something that only breaks in the debug tool's own path, and content that tests fine in the sandbox but behaves differently in a real run because the sandbox skipped part of real setup. Routing everything through `CombatBridge` makes every sandbox test automatically faithful to production, because it *is* production, fed by hand-authored inputs instead of map/placement-derived ones.

Concretely: every sandbox action that would normally come from gameplay (spawning a unit, drawing a card, deploying an artifact, regenerating terrain) must call the same public methods `combat_scene` / `CombatBridge` already expose or would expose for normal play — not new debug-only mutators. If an action the sandbox needs doesn't have a clean existing entry point, add that entry point to the production API rather than bypassing it. The sandbox should add zero new ways to change combat state — only new *triggers* for existing ones.

---

## 2. Where It Lives

A toggleable overlay on top of the existing `combat_scene` (hotkey-activated, e.g. backtick or F1), not a separate scene. It manipulates the live `CombatManager`/`CombatBridge` instance already running in the scene. This avoids building and maintaining a second combat bootstrap path.

Two usage modes, both built on the same underlying scenario format (§4):

- **Interactive** — the overlay UI, for "does this feel right" testing during content authoring.
- **Headless** — load a saved scenario, run scripted actions, assert on results. Extends the existing `ARTILLERY_SMOKE=1` checklist pattern from engine verification to content/synergy regression testing.

---

## 3. Overlay Features

### 3.1 Spawn panel
- Browse/search all `UnitDefinition` resources (player-side and enemy-side), grouped by faction lean.
- Click a unit, then click a voxel to place it.
- Override fields at spawn time (optional, defaults to the definition's base values): starting HP, shield, armor, and a multi-select of active statuses with stack counts (e.g. spawn an enemy pre-set to 30% HP with 2 Burn stacks).
- This is the single highest-value feature: it lets a synergy test start from the *interesting* state directly, rather than playing toward it.

### 3.2 Card / artifact injection panel
- Browse/search all `CardDefinition` and `ArtifactDefinition` resources.
- Per card: buttons for "add to deck," "add to hand directly," and (if applicable) "play immediately" (auto-resolve targeting onto a clicked tile/unit, or self/none-target cards resolve instantly).
- Per artifact: a single "activate" button that runs the same activation path a real acquisition would (so `reset_per_combat` hooks, etc., fire correctly).
- No drawing, no shop flow — the point is getting an exact combination on the field in as few clicks as possible.

### 3.3 Terrain controls
- Seed field + "regenerate" button, calling the existing terrain generator.
- Should preserve current unit positions where possible (re-snap to nearest valid voxel if a unit's position becomes invalid) rather than requiring re-placement after every regeneration.

### 3.4 Turn / tempo cheats
Each of these calls an existing function via a button rather than introducing new logic:
- Refill the shared action pool.
- Force-advance to the next phase (player turn → enemy turn → resolution, etc.).
- Force-trigger the next reinforcement wave immediately, bypassing its countdown.
- Force-advance N rounds (for testing status durations, decay, escalating effects).

### 3.5 Isolation toggles
For testing one side of an interaction without interference from the other:
- **Player invulnerable** — player units take no damage (test an enemy-side mechanic, e.g. a new boss phase, without your squad dying mid-test).
- **Enemy passive** — enemies take no actions / deal no damage (test a player burst combo without being interrupted by unrelated enemy fire).
- Both are flags checked in the existing damage/turn pipeline, not new pipelines.

### 3.6 Inspector
- Click any unit/tile to see its full detailed-tier state (per the UI design doc's hover tier) directly in the overlay — exact HP/armor/shield, every active status with stacks and remaining duration, equipped shots, upgrades. Reuses the detailed-view data already defined; the overlay just guarantees it's always available, not gated behind a real hover interaction.

---

## 4. Scenario Format

A scenario is a small resource capturing everything needed to reconstruct a test setup: unit placements (definition + position + HP/shield/armor/status overrides), deck/hand contents, active artifacts, terrain seed, and an optional `StageDescriptor` override (objective type, reinforcement schedule) if the test needs more than a static skirmish.

```
DebugScenario  (Resource, .tres)
  terrain_seed     : int
  player_units     : array of { definition_id, position, hp_override, shield_override,
                                 armor_override, status_overrides }
  enemy_units      : array of { same shape as player_units }
  deck_overrides   : array of card ids        # replaces/extends the default deck for this test
  hand_overrides   : array of card ids        # cards placed directly in hand at start
  artifacts        : array of artifact ids
  stage_descriptor : StageDescriptor or null  # null = use a minimal default (no objective pressure)
  notes            : String                   # what this scenario is testing, for future-you
```

A `DebugScenario` is converted into a `RunState` + `StageDescriptor` pair and handed to `CombatBridge` through the normal entry point (§1) — it is an alternate *source* for those two objects, not an alternate *consumer*.

### 4.1 Save / load
- "Save scenario" in the overlay captures the current live state into a `DebugScenario` and writes it to a `.tres` under a dedicated debug-content folder (e.g. `res://debug/scenarios/`).
- "Load scenario" lists saved scenarios and reconstructs the state via §1's entry point.
- Saved scenarios double as regression fixtures: once a synergy test is set up and interesting, save it once and reload it instead of re-authoring it by hand each session.

---

## 5. Headless Regression Use

Extending the existing `ARTILLERY_SMOKE=1` pattern: a headless runner that loads a `DebugScenario`, optionally executes a short scripted action list (e.g. "unit A fires shot X at angle Y," "play card Z on tile (col,row)," "advance N rounds"), and asserts on the resulting state (HP values, statuses present, tile states). This is the natural place to put synergy regression tests as content grows — "Fire Shell + Burning terrain still stacks Burn correctly" becomes a one-scenario, one-assert test rather than a manual replay.

This is optional for the first pass — the interactive overlay (§3) is the priority — but the scenario format (§4) should be designed with this consumer in mind from the start, since it costs nothing extra and unlocks it later for free.

---

## 6. Explicitly Out of Scope

- Any new combat-state mutation path that isn't also reachable from normal gameplay (§1).
- Polished UI — this is a developer tool; raw functional panels (buttons, list views, text fields) are sufficient.
- Multiplayer/shared-state concerns — none apply here.
- Persisting sandbox state into a real `RunState` for an actual run — scenarios are throwaway test rigs, not a way to cheat in production runs (though nothing technically prevents that; it's just not a design goal).

---

## 7. Build Order

1. Overlay scaffold + hotkey toggle, wired to the live `CombatManager`/`CombatBridge` instance.
2. Spawn panel (§3.1) — highest value, build first.
3. Card/artifact injection panel (§3.2).
4. Turn/tempo cheats (§3.4) and isolation toggles (§3.5) — small, high-leverage, mostly button-to-existing-function wiring.
5. Terrain controls (§3.3).
6. Inspector (§3.6).
7. Scenario save/load (§4) — once the above exist, this is mostly serialization of state the overlay already manipulates.
8. Headless scenario runner (§5) — deferred until enough scenarios exist to make regression testing worthwhile.
