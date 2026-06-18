# Milestone 10 — Unit Attack, Effects System & Boosted

## What was built

1. **Unit attack value** as the source of projectile strength (× per-shot multiplier × power),
   scaled per-zone by the AoE multiplier — for players and enemies alike.
2. A generalized **Effects** layer: the existing status system (burn/shock) reframed to also
   carry buffs and persistent/triggered effects, with the first new one being **Boosted**.
3. Unit HUD: **attack + shield icons** above the body (shield bar removed), **effect icons**
   below it.
4. A new artifact, **Battle Drills**, granting Boosted(3) at stage start.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | Strength **keeps a per-shot multiplier**: `max(0, round(unit.attack × shot.strength_mult × power) + attack_modifier)`. Shells can still vary within a unit. |
| 2 | Effects **extend the existing status system** — no parallel system. Burn/shock are effects; Boosted joins them in `Unit.active_statuses`. |
| 3 | Boosted is consumed only by **voluntary AP-costing moves** (`try_move`), not by knockback/gravity/fall. It is prioritized over the AP pool (the move is free). |
| 4 | Boosted **persists across turns** (`decays_per_turn=false`) and is **not** refreshed each turn — it's a finite stored resource. |
| 5 | No new `Features` flag — Boosted/effects reuse the existing `unit_statuses_enabled` gate. |

---

## Strength model

`projectile/projectile_manager.gd` `fire()`:
```gdscript
var atk : int = firing_unit.attack if firing_unit != null else 3
var pow : float = firing_unit.power if firing_unit != null else 1.0
var modifier : int = firing_unit.attack_modifier if firing_unit != null else 0
salvo.strength = maxi(0, roundi(atk * shot.strength_mult * pow) + modifier)
```
- `data/units/unit_definition.gd`: `@export var attack : int = 3`.
- `units/unit.gd`: `var attack : int`, set from `definition.attack` in `_ready()`.
- `data/shots/shot_definition.gd`: `@export var strength_mult : float = 1.0`; the int
  `strength` is left dormant (still loads; mines use their own `Mine.strength`).
- Baked attack values (`scripts/bake_resources.gd`): drill/bypass = 10, cluster/pull/spiral = 3,
  enemy organic/mechanical = 3; all shots `strength_mult = 1.0` (default) → balance unchanged.

---

## Effects system

`data/statuses/status_effect_def.gd` — new fields:
```gdscript
@export var is_buff          : bool = false   # green display vs debuff-by-tag
@export var decays_per_turn  : bool = true    # false = persists (no turns_left countdown)
@export var consumed_by_move : bool = false   # a voluntary move spends a stack
```
`systems/unit_status_system.gd` `tick_all()`: `if def.decays_per_turn and inst.tick():` — a
persistent effect never expires by time (its tick_damage/ap_reduction still apply if nonzero).

`data/statuses/boosted.tres`: id `boosted`, "Boosted", `max_stacks=9`, `duration=-1`,
`is_buff=true`, `decays_per_turn=false`, `consumed_by_move=true`, no tick damage / AP.

---

## Boosted consumption + undo (`systems/combat_manager.gd`)

- `_unit_move_token(unit)` → first `active_statuses` instance whose def is `consumed_by_move`
  with stacks left (gated by `unit_statuses_enabled`), else null.
- `try_move()`: a token bypasses the `actions_left < 1` gate; on a successful move, a token is
  spent via `_spend_move_token()` (decrement, erase at 0, emit `status_removed`) **instead of**
  decrementing AP. `moved_this_turn` / `actions_spent_moving` still update either way.
- **Undo:** `_save_checkpoint()` snapshots each unfired unit's consumed-by-move stacks into
  `_checkpoint_move_tokens` (Unit → {id: {def, stacks}}); `try_undo()` restores them via
  `_restore_move_tokens()`. `can_undo()` now returns on a new `_dirty_since_checkpoint` flag
  (set on any move, cleared at checkpoint/undo) because a free move leaves AP unchanged and the
  old `actions_left < checkpoint` test would never fire.

---

## Unit HUD (`units/unit.gd` `_draw`)

- Above the HP bar: `_draw_stat_icons()` draws attack (reddish circle) always and shield (blue
  circle) when `shield > 0`, each via the shared `_draw_icon_value(x, cy, fill, value)` helper
  (filled circle + outline + value, returns the next x). The old `_draw_shield_bar()` is gone.
- Below the body: `_draw_effect_badges(h)` draws one circle + stack value per active effect via
  the same helper. `_effect_color()` → green for buffs, else the FIRE/ELECTRIC tag palette.
  This replaces the old top-of-unit `_draw_status_badges()`.
- `ui/hud.gd` `UnitInspector`: the status line now reads "Effects:".

---

## New artifact — Battle Drills

`data/artifacts/artifact_start_boosted.gd` (`on_combat_start`): apply Boosted(3) to each player
unit. Baked to `data/artifacts/resources/start_boosted.tres`; added to
`CombatManager._ARTIFACT_LOADOUT`.

---

## Files changed

| File | Change |
|---|---|
| `data/units/unit_definition.gd` | `attack: int` |
| `data/shots/shot_definition.gd` | `strength_mult: float` (int `strength` dormant) |
| `units/unit.gd` | `attack` mirror; `_draw` rework (stat icons above, effect badges below; shield bar removed) |
| `data/statuses/status_effect_def.gd` | `is_buff`, `decays_per_turn`, `consumed_by_move` |
| `systems/unit_status_system.gd` | `tick_all` respects `decays_per_turn` |
| `systems/combat_manager.gd` | move-token consumption in `try_move`; checkpoint/undo + `_dirty_since_checkpoint`; loadout entry |
| `projectile/projectile_manager.gd` | new strength formula |
| `data/artifacts/artifact_start_boosted.gd` | NEW |
| `data/statuses/boosted.tres`, `data/artifacts/resources/start_boosted.tres` | baked |
| `scripts/bake_resources.gd` | unit attack values, `boosted.tres`, `start_boosted.tres` |
| `ui/hud.gd` | inspector "Effects:" label |
| `world/combat_scene.gd` | `_m10_smoke()` + `_find_unit()`; M7 smoke updated to the new formula |

---

## Smoke checklist (all pass)

- Drill attack=10, Cluster attack=3 (baked + mirrored).
- Strength formula: `atk3×1×1+0 = 3`; with `+(-5)` modifier, clamped to 0.
- Boosted survives `tick_all` (stacks unchanged, not removed).
- 3 `_spend_move_token` calls drain Boosted to 0 and the token goes null.
- A real move with `actions_left = 0` succeeds, leaves AP at 0, decrements Boosted; `try_undo()`
  refunds the stack.
- Battle Drills `on_combat_start` grants Boosted(3) to a player unit.
- `ARTILLERY_SMOKE=1 godot --headless` — all M4–M10 checklists pass, no ERROR lines.

## Note on bake-time errors

The bake step prints transient `Identifier not found: EventBus/Features` errors (deep-dependency
autoload resolution in the `-s` script context) — same benign noise as M9. All `.tres` files are
written and the real smoke run (which has autoloads) is clean.
