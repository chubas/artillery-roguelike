# Milestone 26 — Tooltip Templating + Formula-Driven Leveling

## Problem

Description strings in def resources were literal text, so they could drift from real gameplay
values. A shot dealing `atk × 1.5` damage might say "deals 4 damage" even after the formula
changed. This milestone couples display to calculation.

## Deliverables

1. **`description_template` + `resolve_description()`** on all def types — `{token}` placeholders
   resolved via `String.format()`.
2. **`effective_magnitude(level)` on `CardDefinition`** — `magnitude + magnitude_per_level * level`.
3. **`effective_value(level)` on `EssenceDef`** — `base_value + value_per_level * level`.
4. **State seams:** `level: int = 0` on `RunUnitState`, `card_upgrades: Dictionary = {}` on
   `RunState`.

## Locked decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Shot resolver passes live `Unit` to `resolve_params()` | Damage = `atk × strength_mult`, same formula as `ProjectileManager`. Tooltip and gameplay can never diverge. |
| 2 | AoE shape NOT tokenized | Shape geometry varies too much per shot for a single "radius" token. Use `[[shape]]` literal placeholder in templates; the existing zone glyph is the canonical display. |
| 3 | Card level = upgrade tier | `Run.active.card_upgrades.get(card.id, 0)` at card-play time — not unit level. Seam added; no card upgrades are awarded yet. |
| 4 | Artifact description is a passthrough | Artifact hooks still have hardcoded values in GDScript; only the field is renamed to `description_template`. Externalization deferred. |
| 5 | StatusEffectDef has no level | Status intensity doesn't scale with level yet. `resolve_description()` formats from static def fields only. |

## Files changed

| File | Change |
|---|---|
| `state/run_unit_state.gd` | Add `level: int = 0` + serialization |
| `state/run_state.gd` | Add `card_upgrades: Dictionary = {}` |
| `data/shots/shot_definition.gd` | `description` → `description_template`; add `resolve_params(unit)` + `resolve_description(unit)` |
| `data/cards/card_definition.gd` | Add `description_template`, `magnitude_per_level`; add `effective_magnitude()`, `resolve_params()`, `resolve_description()` |
| `data/artifact_def.gd` | `description` → `description_template`; add `resolve_description()` passthrough |
| `data/essence_def.gd` | `description` → `description_template`; add `base_value`, `value_per_level`, `effective_value()`, `resolve_description()` |
| `data/statuses/status_effect_def.gd` | Add `description_template`; add `resolve_description()` |
| `data/essences/essence_armor_primer.gd` | Replace `ctx.unit.armor += 10` with `add_armor(effective_value(level))` |
| `systems/combat_manager.gd` | `_apply_card()`: resolve `card_level` from `Run.active.card_upgrades`, use `card.effective_magnitude(card_level)` everywhere. Type annotation fix: `var card_level : int =` (not `:=`) — `Dictionary.get()` returns Variant and the project treats inferred-Variant as an error. |
| `ui/hud.gd` | Shot description: `shot.resolve_description(unit)`; artifact tooltip: `artifact.resolve_description()` |
| `ui/reward_screen.gd` | Artifact card: `def.resolve_description()` |
| `scripts/bake_resources.gd` | All `description` → `description_template`; `{token}` templates for armor primer; `base_value = 10` on `armor_primer.tres` |

## Smoke test fix

`godot --headless -s combat_scene.gd` compiles scripts before autoloads are registered, causing
`Identifier not found: Run` after any cache invalidation. Correct invocation:

```
ARTILLERY_SMOKE=1 godot --headless --path . res://world/combat_scene.tscn
```

The `.tscn` path triggers the full scene-tree initialization (autoloads first, then scripts).

## Out of scope

- Non-linear Curve scaling (seam exists; add later)
- Artifact numeric stat externalization
- Card description display on reward screen
- Actual level-up mechanic (field exists; increment logic is future)
- StatusEffectDef template authoring (field added; `.tres` files left empty)
