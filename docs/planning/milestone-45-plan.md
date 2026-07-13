# Milestone 45 — Deterministic Enemy Targeting + Taunt

## Why

Random accuracy makes the turn's outcome illegible before the player commits — bad for a
deck-builder, where decisions must be made against a known board. This milestone removes the enemy
accuracy RNG and replaces it with **deterministic, telegraphed** targeting: at round start each
enemy locks a target and a committed firing solution (both visible on hover during the player turn),
then executes that exact solution on its turn.

Targeting is two independent layers that **compose** (kept separate deliberately):
1. **Reachable set** — who the enemy *can* hit: straight-line LOS (`terrain/los.gd`) from the enemy
   to each living player; a `bypass_terrain` shot ignores cover (all living players reachable).
2. **Targeting rule** — who the enemy *wants* to hit among the reachable set.

## Decisions (locked with the user)

- **Wind:** enemies stay wind-affected but **solve for the forecast wind** at telegraph time and fire
  that committed solution. Changing wind afterward (Halve Wind) deflects the committed shot → wind
  manipulation is a defensive counter. Requires a wind-aware ballistic solver + a stored solution.
- **Dead target at fire time:** rule-based enemies **recompute** via their rule among living units;
  **SPECIFIC** (Taunt/forced) enemies keep firing at the **dead target's corpse**. Cover is not
  re-checked at fire time — reachability is committed at selection.
- **No reachable target:** fallback = **skip the shot** (enemies don't reposition yet).
- **Taunt** ships in the default deck (1 copy) and the reward/shop pool.

## What shipped

- **Vocabulary** — `UnitDefinition.TargetingRule { NEAREST, FARTHEST, WEAKEST, STRONGEST,
  FIXED_LANE, SPECIFIC }` + `targeting_rule` export. Runtime state on `Unit`: `targeting_rule`
  (overridable copy), `forced_target`, `intended_target`, `intended_solution`, and
  `targeting_summary()` for the tooltip.
- **`systems/enemy_targeting.gd`** (NEW) — `reachable_players` (LOS + bypass), `pick_target`
  (rule switch; NEAREST/FARTHEST by distance, WEAKEST by hp, STRONGEST by max_hp, FIXED_LANE by
  smallest |Δx|, SPECIFIC returns the forced unit ignoring the reachable filter), `assign_all`
  (round-start telegraph; `reset_rules` flag preserves a mid-round Taunt override),
  `reassign_for_dead` (rule-based retarget on a player's death; SPECIFIC keeps the corpse).
- **Wind-aware solver** — `EnemySystem.firing_solution(enemy, target, wind_force_x)` +
  `solution_to_point`. Closed form under constant accel `(ax=wind, g)`; reduces to the old ballistic
  solve when `ax=0`. The ±5% `ENEMY_ERROR_PCT` speed variance and the const are **deleted** (no
  leftover randomness). `fire_enemy` is the flag-off fallback (nearest, no RNG).
- **Turn flow** (`combat_manager.gd`) — telegraph in `_begin_round` (after reinforcements + wind,
  before the player turn); `_fire_committed` in `_run_enemy_turn` (alive → stored solution so wind
  changes deflect it; dead+rule → recompute; dead+SPECIFIC → corpse); `reassign_for_dead` hook in
  `_on_unit_died`; `_apply_taunt` sets every enemy SPECIFIC→ally and re-runs assignment.
- **Taunt card** — `CardDefinition.EffectType.TAUNT`, `data/cards/taunt.tres` (ALLY, 1 AP), added to
  the default deck + card pool; `_apply_card` TAUNT case. Enemy rules baked: organic→WEAKEST,
  mechanical→STRONGEST (tunable).
- **Telegraph UI** — `UnitInspector._get_tooltip` (hover) and the inspector `_draw` panel show
  `Targeting: <RULE> → <unit>` for enemies. `Features.enemy_targeting_enabled` kill switch.

## Deviations / notes

- FIXED_LANE is defined as "reachable unit with the smallest horizontal offset from the enemy's
  column" (most useful on vertical/tower maps); tune later if a different lane model is wanted.
- The design docs (`run-design.md`, `card-engine-system.md`) still describe a *progressive accuracy
  lock-on* escalation concept. That is superseded by deterministic targeting; left untouched here so
  the vision docs can be revised holistically rather than piecemeal.
- Straight-line LOS is used as the arc-shot reachability proxy (cover protects, drilling defeats it),
  matching the stage-design cover theses; the arc itself isn't path-traced for reachability.

## Verification

1. `godot --headless --import`, re-bake (`bake_runner.tscn`), `--import` again — cards + unit defs
   changed.
2. `_m45_smoke()` (all pass): baked rules; each rule picks the expected unit; LOS excludes a
   walled-off player and bypass restores it; SPECIFIC forces from an empty reachable set; a dead
   WEAKEST target retargets to the next-lowest HP; the solver is deterministic, valid with/without
   wind, and wind-sensitive; Taunt loads as TAUNT/ALLY and sits in the deck. Pre-existing unrelated
   failures remain (`_m6` third unit, `_m19` MapState).
3. Manual: hover an enemy on your turn → `Targeting: <rule> → <unit>`; the shot lands on that unit;
   wall a unit off → non-bypass enemies drop it; play Taunt → all enemies retarget the ally; play
   Halve Wind after seeing intent → committed shots drift; kill a WEAKEST target → it retargets.
