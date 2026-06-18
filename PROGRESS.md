# Artillery Space — Progress Log

Chronological record of what's been built and changed. Newest first.

## How the docs fit together

| Doc | Purpose |
| :-- | :-- |
| **PROGRESS.md** (this file) | Chronological log of what shipped + small fixes. Start here to see *what changed and when*. |
| `milestone-N-plan.md` | Per-milestone design decisions, locked choices, and spec deviations with rationale. The *why*. |
| `artillery-space-*-spec.md` / `.md` | Source design specs (the brief we implement against). |

**Working agreement for picking up later:** read the top of this file for current state, then the
relevant `milestone-N-plan.md` for design context before touching a system. When you finish a
chunk of work, add an entry here (and update the milestone plan if a decision changed).

## Current state (2026-06-18)

- **Milestones complete:** M1 (terrain), M2 (combat loop), M3 (elements/status engine),
  M4 (shot varieties & 4-unit squad), M5 (card system: shield + direct damage, reinforcements),
  M6 (turn-phase logging, deployables: mines + shield generators), M7 (AoE zone model & pattern
  indicator), M8 (wind mechanic: physics, fire spread, HUD indicator),
  M9 (artifact system: engine + initial artifacts),
  M10 (unit attack value, Effects system + Boosted, attack/shield/effect HUD icons),
  M11 (card deck: draw/hand/discard, 3 new card effects, deck indicator),
  M12 (run-state backbone: `RunState`/`RunUnitState`, `Run` autoload, `CombatBridge`, combat I/O contract),
  M13 (stage as data: `StageDescriptor`, objective evaluator, per-stage terrain seed),
  M14 (linear run loop: `MapState`, `RunController` main scene, map↔combat flow),
  M15 (pre-combat placement: per-stage spawn zone, PLACEMENT state, deploy UI),
  **M16 (battle rewards + dig vs unit damage separation)**,
  **M17 (collapsible terrain: column collapse, crush damage, resolve API)**.
- **Main scene:** `world/run_controller.tscn` (swaps map ↔ reward screens ↔ `combat_scene.tscn`).
  `combat_scene.tscn` is still standalone-runnable. Map is 120×100 voxels.
- **Verify:** `ARTILLERY_SMOKE=1 godot --headless` runs M3–M17 checklists headless (all pass).
- **Re-bake resources** after changing any generator in `scripts/bake_resources.gd`:
  `godot --headless --import` → `godot --headless -s scripts/bake_resources.gd` → `godot --headless --import`.
- **Known orphan:** `world/world.tscn` references a deleted `world/world.gd` and logs a harmless
  load error on import. Left in place intentionally.

---

## 2026-06-18 — Milestone 17: Collapsible terrain & crush collapse

Carveable terrain falls when unsupported; crush damage on units/deployables in the landing
path. Full design in [milestone-17-plan.md](milestone-17-plan.md).

- **`Tile.collapsible`** — mutable bool (transmutation-ready). Default **off** on all generated
  terrain; specific instances opt in via content later. Indestructible spawn platform stays off.
- **`TerrainManager.resolve_collapses(units, deployables)`** — processes queued columns (post-
  `damage_tile` destroy) until stable; **`resolve_all_collapses()`** scans every column for hooks
  (end-of-turn, transmute, etc.). One tick, no animation.
- **Crush:** falling tile deals **`max_hp`** damage to every unit/deployable in the impact voxel;
  the tile is consumed. `EventBus.terrain_crushed`.
- **`AoEResolver`** passes unit/deployable lists into collapse after each blast.
- **`Features.collapse_enabled`** kill switch.

---

## 2026-06-18 — Milestone 16: Battle rewards + dig vs unit damage

Two run-layer / combat-system pieces in one milestone. Full design in
[milestone-16-plan.md](milestone-16-plan.md).

### Battle rewards

- **`RunController`** now swaps **MapScreen ↔ RewardScreen ↔ combat_scene**. Pre-first-combat and
  post-clear reward sequences (unit → artifact → card) sample from `RunState` pools; applying a
  pick mutates squad / artifacts / deck. Artifacts are without-replacement (`artifact_pool` shrinks).
- **`Run.start_default_run()`** starts lean: 2 units, 1 artifact, 11-card deck; remaining roster
  content enters via reward pools. Smoke mode backfills to the historical 4-unit / 8-artifact
  loadout for regression.
- **`RewardScreen`** (`ui/reward_screen.gd`): code-drawn pick-one-of-three UI.
- **`RunState`**: `unit_pool`, `card_pool`, `artifact_pool` serialized in `to_dict`/`from_dict`.

### Dig vs unit damage

- **Two channels, one salvo:** `Salvo.strength` (unit damage, zoned) + `Salvo.dig_strength` (flat
  terrain only). `AoEResolver` no longer damages terrain from the unit-damage loop.
- **`UnitDefinition.dig`**, **`ShotDefinition.dig_mult` / `dig_pattern`**, **`Mine.dig`**. Default
  shots bake `dig_pattern` = same footprint as `aoe_pattern`; bypass/drill opts out (`dig_strength=0`,
  trail still 1 HP/voxel).
- **Targeting preview:** warm overlay + gold outline on dig footprint voxels (`targeting_overlay.gd`).

---

## 2026-06-18 — Milestone 15: Pre-combat placement

Before each fight the player now deploys the squad within a stage spawn zone (spec §8). Full
design in [milestone-15-plan.md](milestone-15-plan.md).

- **Spawn zone** is a per-stage `StageDescriptor.spawn_min_col` / `spawn_max_col`, baked as the
  left half (`0 .. MAP_WIDTH/2-1`) on all three stages. Refines later with terrain variability.
- **`GameState.PLACEMENT`**: `CombatManager.setup()` now ends in `_start_placement()` (squad spread
  across the zone via `_place_player_squad`) instead of `_begin_round()`. `_confirm_placement()`
  (Start Battle button / Enter) begins the turn loop. Placement input: click a unit to select,
  click a spot to move it (`_placement_place` clamps into the zone, snaps to surface, rejects
  blocked/overlapping spots), Tab to cycle.
- **UI:** HUD gains a "Start Battle" button + instruction (`set_placement_mode`, `start_battle_pressed`);
  the targeting overlay draws the translucent spawn-zone band (`set_placement_state`).
- **Bug fix (carded earlier):** selecting a card highlighted *all* copies of that type — duplicate
  hand cards share one cached `CardDefinition`, so the HUD now keys selection off the hand **index**
  (`_pending_index`) instead of the card object.
- **Smoke compat:** combat now starts in PLACEMENT, so `combat_scene` calls `_confirm_placement()`
  in smoke mode before the M4–M15 chain (reproducing the pre-M15 start). The M14 run controller is
  unaffected — each instanced stage simply opens in placement.

---

## 2026-06-17 — Milestone 14: Linear run loop (MapState + run controller)

The loop that turns stages into a *run* (spec §7, step 7). Full design in
[milestone-14-plan.md](milestone-14-plan.md).

- **`MapState` / `MapNode`** (`state/`, RefCounted + to/from_dict): a linear sequence of
  stage-wrapping COMBAT nodes with `current` / `visited`; `build_linear(paths)`, `current_node`,
  `mark_visited`, `advance`, `is_last`, `is_complete`. Lives in `RunState.map` (now serialized).
- **`RunController`** (`world/run_controller.gd` + `.tscn`) is the **new main scene**. It persists
  for the run and swaps its single child between `MapScreen` and a freshly-instanced
  `combat_scene`. Flow: show map → Enter Stage → play → `combat_exited` → if cleared & squad
  alive: `mark_visited` then advance (or "RUN COMPLETE" on the last node); else "RUN OVER".
  Re-instancing `combat_scene` per stage *is* the per-stage reset (M12's fresh-Unit principle);
  HP/kills/disabled carry only through `RunState`.
- **`MapScreen`** (`ui/map_screen.gd`, code-drawn like the HUD): the linear node strip
  (cleared/current/upcoming), current stage detail + threat tags, "Enter Stage", and an end
  banner with "New Run".
- **`combat_scene`** gains a `combat_exited(outcome)` signal (emitted after its existing
  write-back) so the controller can advance. It stays standalone-runnable (self-bootstraps a
  default run + `stage_01`). Third stage `stage_03.tres` baked so the default map has 3 fights.
- `project.godot` `run/main_scene` → `run_controller.tscn`.

---

## 2026-06-17 — Milestone 13: Stage as data & objective evaluator

Second run-layer piece (spec §5 + §9): the stage stops being hardcoded in `CombatManager`. Full
design in [milestone-13-plan.md](milestone-13-plan.md).

- **`StageDescriptor`** (`data/stages/`, baked `.tres`) holds what combat used to hardcode:
  `terrain_seed`, `initial_enemies`, `reinforcements`, `deployables`, the wind profile, the
  `objective`, plus reserved `rewards`/`threat_tags` seams. `CombatManager.setup()` takes a
  `stage` and its spawn/reinforcement/wind/deployable readers consume it; the old
  `_REINFORCEMENT_SCHEDULE` / `_WIND_CONFIG` / `_DEPLOYABLE_PLACEMENTS` consts are gone.
- **Objective evaluator** (`systems/objective_evaluator.gd`, static): `evaluate(obj, enemies_alive,
  players_alive, round_index, all_waves_spawned) → ONGOING/WON/LOST`. `ObjectiveDescriptor` has
  DEFEAT_ALL (the existing gate) and SURVIVE_N (win at round N). The inline win/loss in
  `_on_unit_died` is replaced by `_check_objective()`, also called at round start for survive-N.
- **Per-stage terrain seed:** `TerrainManager.generate(seed)` (derived cave/HP/variant seeds
  offset from it); `_ready` no longer auto-generates — `combat_scene` generates with
  `stage.terrain_seed` before `renderer.setup()`.
- **Two baked stages:** `stage_01` reproduces today's content exactly (defeat-all, seed 12345);
  `stage_02` is a survive-N stage (seed 777, `survive_rounds 4`) for the smoke test + M14's map.
  `combat_scene` defaults to `stage_01`; M14's controller will set the stage from the map node.
- **Bake-time noise:** the bake step prints the usual benign `Identifier not found:
  EventBus/Features` lines (deep-dependency autoload resolution in the `-s` context); both stages
  write and the live run is clean.

---

## 2026-06-17 — Milestone 12: Run-state backbone & combat I/O contract

First piece of the roguelite run layer (run-state spec steps 1–3). Full design in
[milestone-12-plan.md](milestone-12-plan.md).

- **Three-layer state.** Added the missing middle layer: `RunState` (squad/deck/artifacts/
  resources/map/run_meta) + `RunUnitState` (definition_id, current_hp, max_hp, kills, is_disabled,
  upgrades/equipment) in `state/`. Plain `RefCounted` with `to_dict`/`from_dict` — serialization-
  ready, no disk I/O yet (schema will churn). `Run` autoload holds the active run (3rd autoload
  after EventBus/Features); `start_default_run()` reproduces the historical 4-unit squad / 11-card
  deck / 8 artifacts so the live game is unchanged.
- **Combat I/O contract.** `CombatBridge` (static, in `systems/`) owns RunState↔combat translation
  both ways: `build_squad()` turns non-disabled `RunUnitState`s into combat `Unit`s;
  `write_back()` copies each unit's hp/kills/disabled back. `CombatManager.setup()` is now
  **parameterized** — squad, deck source, and artifact paths are inputs (the `_DECK_LIST` /
  `_ARTIFACT_LOADOUT` consts moved to `Run`); `_spawn_all_units` split into `_place_player_squad`
  (run squad) + `_spawn_enemies` (still hardcoded — M13 makes it descriptor-driven). A new
  `combat_finished(outcome)` signal drives write-back from `combat_scene`.
- **Persist/discard boundary is structural.** Persistent truth lives in `RunUnitState`; each
  combat builds fresh `Unit` nodes, so shields/effects/positions reset automatically. `Unit`
  gained `run_state` + `kills`; `_ready()` initializes hp/kills/attack from `run_state` when set
  (so a unit can spawn *damaged*).
- **Proof gate (`_m12_smoke`).** A unit damaged in stage 1 rebuilds for stage 2 still damaged,
  with a fresh (reset) shield; a unit that hit 0 HP is disabled and excluded from redeploy; the
  RunState round-trips through `to_dict`/`from_dict`.
- **Deferred (next milestones):** stage-as-descriptor (M13), deck *progression* between stages,
  map/run controller (M14), disk serialization.

---

## 2026-06-17 — Milestone 11: Card deck (draw / hand / discard)

The fixed two-card hand becomes a real deck. Full design in
[milestone-11-plan.md](milestone-11-plan.md).

- **Deck lifecycle.** `CombatManager` now holds `_deck` / `_hand` / `_discard`. The starting deck
  (`_DECK_LIST`) is 11 cards — Direct Strike ×3, Shield ×3, Mine ×2, Boosted ×2, Halve Wind ×1 —
  built and shuffled in `setup()`. Each player turn `_draw_hand()` discards the old hand and draws
  `HAND_SIZE = 5`; if the draw pile empties mid-draw, `_reshuffle_discard()` shuffles the discard
  back in and drawing continues. The once-per-turn-per-card rule (`_used_cards`) is gone — **AP is
  the only play limit**.
- **Three new card effects** (`CardDefinition` gained TargetType.TILE/NONE and EffectType
  ADD_BOOSTED / DEPLOY_MINE / HALVE_WIND): Overdrive (Boosted +2 to an ally), Drop Mine (deploy a
  mine on a clicked column via `_deploy_mine_at`), Calm Winds (instant, no target — halves this
  round's `wind_strength`).
- **Targeting.** `_try_click_target_card` now branches on target type; TILE cards convert the click
  to a column and the overlay (`_draw_tile_target`) shows a column guide + surface marker. NONE
  cards apply immediately on select (no targeting step).
- **HUD.** `set_cards` takes draw/discard counts; a `Deck N · Discard M` label sits under the hand.
  CardChip lost its spent/slash visuals (no per-turn deactivation anymore).
- Card play remains non-undoable (re-checkpoints), so deck state needs no undo snapshot.

---

## 2026-06-17 — Milestone 10: Unit attack, Effects system & Boosted

Per-unit attack stat as the source of projectile strength, plus a generalized "Effects" layer
(the status system reframed) with the first new effect, Boosted. Full design in
[milestone-10-plan.md](milestone-10-plan.md).

- **Strength model.** Projectile strength now derives from the firing unit:
  `max(0, round(unit.attack × shot.strength_mult × power) + attack_modifier)`, then scaled
  per-zone by the AoE multiplier. `UnitDefinition.attack` (mirrored to `Unit.attack`) and
  `ShotDefinition.strength_mult` are new; the old `ShotDefinition.strength` int is dormant.
  Baked attack values preserve prior balance (drill 10, others 3).
- **Effects = the status system, generalized.** `StatusEffectDef` gained `is_buff`,
  `decays_per_turn`, and `consumed_by_move`. `UnitStatusSystem.tick_all()` skips the
  turns-left decrement for persistent effects (`decays_per_turn=false`). Burn/shock are now
  framed as effects; the inspector label reads "Effects:".
- **Boosted (X).** A persistent buff (`boosted.tres`): the first X voluntary moves cost no AP —
  each spends a stack instead (`CombatManager._unit_move_token` / `_spend_move_token` in
  `try_move`). Stacks persist across turns. Undo refunds spent stacks via a new
  `_checkpoint_move_tokens` snapshot, and `can_undo()` now keys off a `_dirty_since_checkpoint`
  flag (a free move spends no AP, so the old AP-delta check missed it).
- **Unit HUD.** `unit.gd` `_draw` reworked: attack + shield placeholder circles with values sit
  above the HP bar (shield bar removed); effect placeholder circles with stack values sit below
  the body (relocated from the old top-of-unit status squares). Buffs draw green.
- **Artifact "Battle Drills"** (`artifact_start_boosted.gd`): grants every player unit
  Boosted(3) on combat start. Baked to `start_boosted.tres`, added to `_ARTIFACT_LOADOUT`.

---

## 2026-06-16 — Milestone 9: Artifact system

Passive squad-wide effects driven by a hook engine. Full design in
[milestone-9-plan.md](milestone-9-plan.md).

- **Engine.** `ArtifactDef` (Resource subclass) declares virtual hooks: `on_round_start`,
  `on_player_turn_end`, `on_unit_died`, `on_unit_killed`, `modify_card_cost`,
  `modify_projectile_strength`, `bonus_actions_on_round_start`, `reset_per_combat`.
  `ArtifactSystem` is a static dispatcher (same pattern as `TileStatusSystem`). `ArtifactContext`
  is a `RefCounted` bag holding terrain, units, and a CombatManager ref passed to every hook.
- **Integration.** `CombatManager._ARTIFACT_LOADOUT` (empty by default; populate to activate).
  Hooks fire at: combat start (+ `reset_per_combat`), round start (+ idle-action bonus + move
  reset), player turn end, unit died/killed. `ArtifactSystem.apply_card_cost` wraps every card
  play; `apply_projectile_strength` wraps impact resolution in `ProjectileManager._resolve_impact`.
- **New Unit fields.** `attack_modifier: int` (applied at fire time in ProjectileManager,
  effective strength = `max(0, base + modifier)`). `moved_this_turn: bool` (set in `try_move`,
  reset each `_begin_round`).
- **New Projectile field.** `flight_time: float` — accumulated in `_physics_process`, stored in
  the impact pending-dict so `modify_projectile_strength` can read it at resolution.
- **7 initial artifacts** in `data/artifacts/`:
  1. Squad Regen — +1 HP all player units on round start
  2. Lifesteal — killer heals `(max-hp)/2` on enemy kill
  3. Enemy Debuff — enemies lose 3 attack per player turn end (stacks, floor 0 effective)
  4. Free First Card — first card each combat costs 0 actions (per-combat reset)
  5. Idle Actions — +1 action per ally that didn't move last round
  6. Death Explosion — first enemy death explodes (diamond 5×5, strength 5), once per combat
  7. Long Flight — projectiles >10s airborne deal 20% more damage (floor)
- **Baked resources.** `data/artifacts/resources/*.tres` — 7 files. `Features.artifacts_enabled = true`.
- **Gotcha.** GDScript's `Resource` has a native `reset_state()` method — overriding it is an
  error. Named the hook `reset_per_combat()` instead.

---

## 2026-06-16 — Milestone 8: Wind mechanic

Wind as the first stage environmental force. Full design in
[milestone-8-plan.md](milestone-8-plan.md).

- **Physics.** `wind_strength: float` in `[-1.0, 1.0]` on `CombatManager`; multiplied by
  `MAX_WIND_FORCE = 300.0` px/s² to get actual horizontal acceleration. Applied each frame in
  `Projectile._physics_process()` and mirrored in `Trajectory.simulate_arc()` so the charge preview
  matches the actual shot. `SpiralSatellite` requires no change — it derives position from the main
  projectile. Files: `projectile/projectile.gd`, `projectile/projectile_manager.gd`,
  `projectile/trajectory.gd`, `ui/targeting_overlay.gd`.
- **Round ramp.** Wind is absent until round 3 then ramps ±5% per round (configurable per-stage
  via `_WIND_CONFIG` dict on `CombatManager`). Updated in `_begin_round()` after
  `_check_reinforcements()`, before tile-status tick. `EventBus.wind_changed` signal keeps HUD +
  targeting overlay in sync. Files: `systems/combat_manager.gd`, `autoloads/event_bus.gd`.
- **Fire spread.** When `abs(wind_strength) >= 0.2`, burning tiles spread one column in the wind
  direction each round, blocked by walls taller than 1 voxel (vehicle movement rule). Bug found and
  fixed during testing: `signi(float)` truncates the float to int before sign, so `signi(0.25) = 0`
  — changed to `1 if wind_strength > 0.0 else -1`.
- **HUD indicator.** `WindIndicator` inner class in `hud.gd` (same `_draw()` pattern as
  `UnitInspector`). White 0–20%, orange 20–50%, red >50%. Hidden when calm.
- **Feature flag.** `Features.wind_enabled = true` (was stubbed false).
- **Bug fix (unrelated).** Stage-clear now gates on `_all_waves_spawned()` so killing all enemies
  before the last wave spawns no longer prematurely clears the stage.

---

## 2026-06-16 — Milestone 7: AoE zone model & pattern indicator

Decoupled AoE shape from magnitude. Full design + deviations in
[milestone-7-plan.md](milestone-7-plan.md).

- **Zone model.** `AoEGroup.damage: int` → `AoEGroup.multiplier: float` (core = 1.0, edge = 0.5;
  a third zone is just another group, no schema change). `AoEPattern.make_diamond(core_radius,
  edge_radius)` replaces the old `(radius, base_dmg, falloff)` signature — it's shape-only now.
  `AoEPattern.zone_color(multiplier)` is the single shared palette (orange ≥1.0, yellow ≥0.5,
  gray→yellow lerp below that) used by both the in-world targeting preview and the new card glyph.
- **Strength sourcing.** `ShotDefinition.strength: int` (shot's baseline) × `Unit.power: float`
  (mutable per-unit multiplier, from `UnitDefinition.base_power`) for normal shots; `Mine.strength`
  is a fixed value with no unit-power factor. Computed once at fire/detonate time and passed as a
  plain `int` into `AoEResolver.resolve(..., strength, ...)`, which does
  `maxi(1, round(strength * group.multiplier))` per zone.
  Files: `data/shots/aoe_group.gd`, `data/shots/aoe_pattern.gd`, `data/shots/shot_definition.gd`,
  `data/units/unit_definition.gd`, `units/unit.gd`, `world/mine.gd`, `terrain/aoe_resolver.gd`,
  `projectile/projectile_manager.gd` (`Salvo.strength`).
- **World preview.** `targeting_overlay.gd` now fills each footprint voxel with a flat, discrete
  zone color via `AoEPattern.zone_color()` instead of a continuous damage-gradient opacity.
- **Unit-card glyph.** `UnitInspector._draw_pattern_glyph()` (in `ui/hud.gd`) draws a small
  fixed-size grid of the active shot's pattern in the inspector card's top-right corner, colored
  per zone with a white outline on the impact cell — same visual language as the world preview.
- **Re-baked** all AoE patterns + shots with the new two-arg `make_diamond` and explicit
  `strength` values (basic/fire/electric/cluster/pull/spiral = 3, bypass = 10, mine = 4).
- Extended the headless smoke harness with `_m7_smoke()` (zone-strength split, `Unit.power`
  scaling, mine strength independence, `zone_color()` distinctness).

## 2026-06-16 — Milestone 6: Turn-phase clarity & deployable objects

Made the 5-phase turn structure explicit via console banners, and introduced the first non-unit
on-map entities (mines, shield generators). Full design + deviations in
[milestone-6-plan.md](milestone-6-plan.md).

- **Turn-phase logging.** `CombatManager._log_phase()` prints a banner at round start, player-turn
  start/end, and enemy-turn start/end — no new signals, just loud console markers next to the
  existing `round_started`/`turn_started`/`turn_ended` emits. Future phase-triggered card/artifact
  effects hook in at the same points (shield generators are the first example).
- **`Deployable`** (`world/deployable.gd`): a sibling type to `Unit` — HP, voxel position/bbox,
  damage, and falling, but none of `Unit`'s action economy or shot loadout. Falling physics is
  shared via the new `UnitMovement.settle_at(pos, w, h, terrain)`, extracted from `settle()`.
- **Mines** (`world/mine.gd`): 1 HP, explode in a radius (`diamond_mine.tres`) on either being hit
  by a projectile's AoE or a player unit stepping within `trigger_radius` — both paths funnel
  through the same `_die()`, which only signals `EventBus.mine_detonated`; `CombatManager` runs
  the actual blast (no direct cross-system calls, per house rule). Enemies don't trigger mines.
- **Shield generators** (`world/shield_generator.gd`): 5 HP, destructible like a unit; grant
  `shield_amount` to every living ally within `aura_radius` at player-turn start
  (`_pulse_shield_generators()`), reusing `Unit.add_shield()`.
- **Generalized `unit_moved`.** The signal now fires from the single `Unit.set_vox_position()`
  chokepoint (gained `from`/`to` params) instead of only `try_move()`, so mine proximity triggers
  react uniformly to player movement, knockback, gravity pull, and falling alike.
- **`AoEResolver.resolve()`** gained an optional `deployables` param and a parallel
  dominant-hit-per-blast pass for them (no element/affinity logic — deployables are inert).
- **Hardcoded test placements** (2 mines, 1 shield generator at fixed columns), mirroring the M5
  reinforcement-schedule pattern. New `Features.deployables_enabled` kill switch.

---

## 2026-06-15 — Milestone 5: Card system & reinforcement waves

First slice of the card-engine vision, scoped entirely inside the combat stage (no map/shops/
deck progression yet). Full design + deviations in [milestone-5-plan.md](milestone-5-plan.md).

- **Shield mitigation layer.** `Unit.shield`/`max_shield`; `take_damage()` now drains shield
  before HP (armor would slot in above shield later — seam comment marks the spot). Gated by
  new `Features.shields_enabled` kill switch. A thin shield bar draws above the HP bar.
- **Two cards**, baked as `CardDefinition` resources: `shield_buff` (ally, +4 shield, 2 AP) and
  `direct_strike` (enemy, 3 dmg routed through shield like any other hit, 3 AP). Both spend from
  the shared `actions_left` pool and are captured by the existing turn-wide checkpoint/undo —
  same as firing, a card's own spend isn't itself undone, only moves made after it are.
- **Targeting flow.** `Q`/`E` or HUD chips arm a card; click a valid ally/enemy to apply it
  (green/red highlight on valid targets), `Esc` cancels without spending AP. Doesn't require an
  active unit or end any unit's turn.
- **Reinforcements.** A hardcoded round → unit schedule (round 2 → EnemyC, round 5 → EnemyD)
  spawns directly on the surface row with no collision-avoidance (enemies don't move, so the
  landing space is assumed clear). A world-space guide line + countdown number telegraphs each
  incoming drop before it lands.
- **Feature flag:** `Features.card_deck_enabled` (previously an unused M3-era stub) now gates
  the whole card UI/input path and is flipped on.

---

## 2026-06-14 — Milestone 4: Shot varieties & unit roster

Four distinct shot behaviors, each its own player unit. Full design + deviations in
[milestone-4-plan.md](milestone-4-plan.md).

- **Salvo system.** `ProjectileManager` rebuilt around a `Salvo` (one logical shot = many
  bodies). Bodies that hit terrain **pause** (not freed) and report an impact; the manager
  drains impacts in collision order — `(physics_frame, salvo index)` — re-checking each voxel
  first, so a pellet whose blocker an earlier impact already destroyed **resumes** and flies on.
  One settle beat per salvo, then `shot_resolved`. `is_busy()` = "any salvo alive."
- **Cluster** (`Cluster` unit): 5 pellets fanned 1° apart, R3 diamond each.
- **Bypass / drill** (`Drill` unit): ignores terrain, deals 1 dmg per unique trail voxel,
  stops on an opposing unit for a heavy R4 blast. Unit overlap checked in the manager.
- **Gravity pull** (`Magnet` unit): post-impact `GravityPullResolver` drags units toward the
  blast — inner band (≤4 vox) 2 steps, outer (≤8) 1 step, closest-first, blocked-stays-put.
- **Spiral** (`Spiral` unit): main projectile + 2 `SpiralSatellite` arms oscillating
  perpendicular to the heading; arms share the salvo/impact queue.
- **UnitMovement** static module extracted from `CombatManager` so the pull shot shoves units
  with **identical** climb/fall/collision rules as walking.
- **Power memory.** Each unit remembers its last charge fraction; HUD draws a triangle marker
  on the charge bar (angle already persisted). Action budget raised to **10 AP**; fire = 2 AP,
  electric = 3 AP (unaffordable shots already grey out from M3).
- **Content (baked):** R3/R4 diamonds (+ elemental variants); 12 shots (4 families × phys/fire/
  electric); 4 player unit `.tres`.
- **Key deviations:** spiral arms don't outlive the main projectile (despawn if it resolves
  first); pull direction is fixed at the unit's initial side (pull *by* N voxels, may overshoot
  the blast rather than stop at column alignment). See plan §10.

## 2026-06-14 — Shot resolution routine

- **Shot resolution pipeline.** `ProjectileManager._on_impact` is now an ordered, async
  *resolution routine*: (1) AoE damage, (2) explosion FX, (3) [pluggable seam for future
  consequences — death animations, terrain collapse, knockback], (4) a settle beat
  (`Const.SHOT_RESOLVE_DELAY`, 0.45s). It emits `shot_resolved(is_enemy)` only when the whole
  routine finishes, and `is_busy()` stays true throughout.
- **Next-unit focus is deferred to resolution.** `_fire_active` no longer auto-advances; the
  camera follows the projectile, lingers on the impact through the settle beat, then
  `CombatManager._on_shot_resolved` focuses the next available unit. Enemy sequencing now waits on
  `is_busy()` (full resolution), not just `has_active()` (flight only).
  Files: `projectile/projectile_manager.gd`, `systems/combat_manager.gd`, `constants.gd`.

## 2026-06-14 — Post-M3 usability & terrain tweaks

- **Camera focus on selection.** Selecting an ally (Tab cycle, click, turn-start first-available,
  or post-fire auto-advance) now eases the camera to that unit. Implemented as a one-shot pan that
  releases once centered, so WASD free-panning isn't fought. Only allied units are selectable/
  focusable (enemies were never click-selectable). `CombatManager.unit_focused` signal →
  `CombatScene._on_unit_focused`. After a unit fires, the camera follows the projectile and only
  pans to the next unit once the shot has **resolved** (the projectile-follow branch owns the
  camera while a shot is live, so the deferred focus lands afterward).
  Files: `systems/combat_manager.gd`, `world/combat_scene.gd`.
- **Terrain is fixed (no collapse).** Added `Tile.collapsible` (default **false**). The column-fall
  pass in `TerrainManager._collapse_column` now skips non-collapsible tiles, so nothing falls when
  the tile beneath it is destroyed. Collapse *rules* will opt specific tiles in later. Units still
  settle into craters (separate from terrain collapse).
  Files: `terrain/tile.gd`, `terrain/terrain_manager.gd`.
- Added this `PROGRESS.md`.

## (earlier 2026-06-14) — Milestone 3: Elements, Status Effects & Combat Engine

Engine for emergent combat. Full design + deviations in [milestone-3-plan.md](milestone-3-plan.md).

- **Architecture:** `EventBus` + `Features` autoloads. Gameplay events routed through EventBus;
  high-frequency per-tile render signal kept local.
- **Elements:** `ElementDef` (Fire, Electric); `element` field on `AoEGroup`; affinity table +
  structural `tags` on `UnitDefinition`. `AoEResolver` applies affinity damage + statuses, gated
  by `Features.elements_enabled`.
- **Unit statuses:** `StatusEffectDef`/`StatusInstance`/`UnitStatusSystem` — Burn, Shock; cap-3
  refresh; Shock cuts the shared action pool. Stack badges on units.
- **Tile statuses:** `TileStatusDef`/`TileStatusInstance`/`TileStatusSystem` — Burning (spreads to
  exposed FLAMMABLE), Electrified (chains through CONDUCTIVE). Tints on chunks.
- **Turn loop** restructured to spec §6 resolution order (round → tile tick → player statuses →
  actions → enemy statuses → fire).
- **Shot selection:** `available_shots`/`selected_shot`, keys `1/2/3` + HUD chips, action-cost
  spend (elemental = 1 AP, basic = 0). **Player full-charge power ×2.5** (`Const.PLAYER_POWER_MULT`).
- **Content (baked):** fire/electric shells + patterns; organic (weak fire) / mechanical (weak
  electric) enemies; updated player loadouts.
- **Key deviation:** dropped the spec's fire↔burning circular resource reference (Godot's `.tres`
  loader can't resolve it) — `TileStatusDef` stores `applied_status` instead; tile tick damage is
  physical. See plan for full list.

## (earlier 2026-06-14) — Post-M2 bug fixes

Six fixes from manual playtest (`systems/combat_manager.gd`, `ui/hud.gd`, bake/resources):

1. End-turn alert only reddens when all living units have **fired**, not at 0 actions.
2. Enemies fire one at a time, each shot fully resolving before the next (drain moved inside loop).
3. HUD buttons `focus_mode = NONE` — Tab no longer cycles button focus (it cycles units).
4. Same fix stops Space from triggering a focused button while firing.
5. Removed the per-unit move cap (units now move as far as action points allow; `move_range = 99`).
6. Undo is a **turn-wide checkpoint** — restores all unfired units to their positions since the
   last fire, refunding all actions, rather than only the last unit's last move.

## Milestone 2: Combat loop prototype

Full design in [milestone-2-plan.md](milestone-2-plan.md). 2 players vs 2 enemies, HP, shared
5-action turn bar, ←/→ movement with climb/fall/collision, undo, Gunbound ↑/↓ angle + Space charge,
enemy parabolic IK firing, win/loss, `AoEPattern` resource system, surface-snap spawning.

## Milestone 1: Destructible voxel terrain

Full design in [milestone-1-plan.md](milestone-1-plan.md). 300→120-wide voxel grid, chunked dirty
`_draw` rendering, ballistic projectiles with shared `Trajectory` (preview = reality), six-pass
procedural generation (fixed seed, reproducible), AoE destruction + (then-)column collapse, camera
pan/zoom.
