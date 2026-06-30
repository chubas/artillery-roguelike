# Milestone 40 — Source-Attributed Power Modifier System

## Why

M39 collapsed attack into three scalar fields: `Unit.attack` (int flat), `Unit.combat_flat`
(in-combat additive) and `Unit.combat_mult` (in-combat multiplier, seeded from
`RunUnitState.permanent_mult`, itself seeded from `definition.base_power`). One multiplier and one
flat term cannot express the real design: a unit's attack is the **compounded result of many
modifiers from many sources** — artifacts granting permanent +power, equipment granting
×multipliers, in-combat buffs/debuffs (additive *or* multiplicative, possibly negative), and
conditional effects like "×1.5 while last unit standing". A scalar field has nowhere to record
*where* a bonus came from, so modifiers couldn't be removed when their source ended, shown in a
breakdown, stacked, or evaluated conditionally.

M40 replaces the scalars with **`base_power` + a list of source-attributed `PowerMod`s**, folded on
demand by `PowerCalculator`. This is the single source of truth for the attack number on the card
and in combat.

## Locked decisions

1. **Two-tier fold.**
   `permanent = max(0, (base_power + Σ perm_add) × Π perm_mult)` — the card / round-start value.
   `combat    = max(0, (permanent  + Σ comb_add) × Π comb_mult)` — the live in-combat value.
   Clamped ≥0 at **both** tier boundaries so a net-negative permanent can't flip sign when a combat
   multiplier is applied. Example: base 3, perm +1 ×2 → 8 (card); combat +1 ×1.5 → 13.5 → floor 13.
2. **Compute-time predicates.** Each `PowerMod` carries an optional `condition: Callable`; empty =
   always active, else `condition.call(unit)` decides per-evaluation. Not serialized — conditional
   mods are re-attached live by their source on combat start (the source owns the closure and the
   context it captures).
3. **Remove & unify.** `Unit.attack`, `Unit.combat_flat`, `Unit.combat_mult`,
   `RunUnitState.permanent_mult`, `RunUnitState.bonus_attack`, and `UnitDefinition.attack` are gone.
   `definition.base_power` + the mod list is the only representation; effective attack is computed.

## Pieces

- **`systems/power_mod.gd`** — value object: `source`, `label`, `op` (ADD|MULT), `value`, `tier`
  (PERMANENT|COMBAT), `condition`. `active_for(unit)`, `to_dict`/`from_dict` (predicate dropped).
- **`systems/power_calculator.gd`** — `effective_attack(unit, include_combat=true) -> int`,
  `effective_attack_f` (float, preserves precision for downstream zone × affinity),
  `card_attack(run_state, definition) -> int` (permanent tier only, no live unit),
  `breakdown(unit) -> Array` (base row + active mods, for the inspector tooltip).
- **`units/unit.gd`** — `power_mods: Array[PowerMod]`; `add_power_mod` (replace-by-source),
  `adjust_power_mod` (accumulate ADD value by source — for stacking debuffs), `remove_power_mod`,
  `attack_value`. `_ready()` deserializes `run_state.power_mods` into permanent `PowerMod`s.
- **`state/run_unit_state.gd`** — `power_mods: Array` of dicts, serialized; `add_permanent_mod`
  (update-or-insert by source); `from_dict` migrates legacy `bonus_attack` → permanent ADD mod and
  drops `permanent_mult`.
- **`systems/damage_resolver.gd`** — `compute_base` returns `PowerCalculator.effective_attack_f`
  plus the shot's flat `conditional_bonus`; the single `floor()` still happens in `AoEResolver`.
- **Artifacts** — `enemy_debuff` migrated to an accumulating −3 COMBAT ADD mod; new
  `ArtifactLastStand` adds a ×1.5 COMBAT MULT mod whose predicate counts living player units
  (validates the compute-time conditional path end to end).
- **UI** — HUD inspector shows `★ N` + a per-mod breakdown; `upgrade_screen`/`reward_screen`/
  `sandbox_overlay` use `card_attack` / `add_permanent_mod` / `base_power`.

## Rounding / migration notes

- A unit with no mods: `effective_attack = base_power` — identical to M39's observed values, so no
  gameplay change for un-modified units.
- Float precision is preserved through `effective_attack_f`; UI shows `floor()` for display only;
  the single `floor()` per hit remains in `AoEResolver` (zone × affinity).
- Pre-M40 saves: `bonus_attack` becomes a permanent ADD mod; `permanent_mult` is dropped
  (base_power reasserts as the base).

## Verification

1. Bake: `godot --headless --import` → `godot --headless --path . res://scripts/bake_runner.tscn`
   → `godot --headless --import`.
2. Smoke: `ARTILLERY_SMOKE=1 godot --headless --path . res://world/combat_scene.tscn`. `_m40_smoke`
   passes: card=8, combat=13.50/13, clamp=0, predicate 3→6, card_attack=5, Last Stand present.
   (Pre-existing, unrelated: `_m6_smoke:457` needs a 3rd player unit; `_m19` MapState illegal pick.)
3. Manual: inspect a unit (`★ 3`, breakdown "Base 3") → core-zone hit = 3 → let `enemy_debuff` tick
   two player turns (★ drops, `[dmg]`/`[hit]` console agree) → with Last Stand, reduce to one
   surviving unit and confirm its ★ jumps ×1.5 only while it is the sole survivor.
