# Milestone 30 — Elemental Prime Cards + Shot Selector Removal

## Problem

Fire and electric shots were always-available options on every unit (keys 1/2/3). This made
elemental choice a per-turn mechanical input rather than a strategic deck decision. M30 converts
them to one-use cards that grant a "next shot" element override, and removes the shot-selection
UI entirely.

## Decisions

| # | Decision |
|---|---|
| 1 | **Elements stack** — playing fire + electric prime gives `primed_elements = [fire, electric]`; each fires a full-strength AoE pass |
| 2 | **One `resolve()` call per primed element** — same shape/strength/pattern each pass, only the element changes |
| 3 | **Prime cleared at `fire()` time** — consumed when shot is launched, not on impact |
| 4 | **Family unit loadouts: basic only** — `_make_family()` still bakes the trio but returns `[0]`; `player_heavy`/`player_light` also set to `[basic_ref]` |
| 5 | **Shot selector fully removed** — `_select_shot()`, `signal shot_selected`, `KEY_1/2/3`, `set_shots()` all deleted |
| 6 | **`unit.selected_shot` field kept** — inert; `get_active_shot()` always returns `default_shot` |
| 7 | **Primed indicator in `UnitInspector` only** — one line per element, color-coded (orange = fire, cyan = electric) |
| 8 | **Fire/electric `ShotDefinition` resources kept on disk** — orphaned but harmless |
| 9 | **Card cost: 2 AP each; 2 copies each in starting deck** |

## Files changed

| File | Change |
|---|---|
| `data/cards/card_definition.gd` | Added `PRIME_FIRE, PRIME_ELECTRIC` to `EffectType` enum |
| `units/unit.gd` | Added `primed_elements: Array[ElementDef] = []` |
| `projectile/projectile_manager.gd` | `Salvo.element_overrides`; `fire()` captures+clears primes; `_resolve_blast()` multi-element pass |
| `terrain/aoe_resolver.gd` | Added `element_override: ElementDef = null` param; overrides element per zone group |
| `systems/combat_manager.gd` | Added `PRIME_FIRE`/`PRIME_ELECTRIC` dispatch; removed KEY_1/2/3, `_select_shot()`, `shot_selected` connect, `set_shots()` calls |
| `ui/hud.gd` | Removed `shot_selected` signal + `_shot_box`/`_shot_buttons` + `set_shots()`; added primed indicator to `UnitInspector._draw()` |
| `scripts/bake_resources.gd` | Trimmed elemental shots from `player_heavy`/`player_light`; `_make_family()` returns `[trio[0]]`; baked `fire_prime.tres` + `electric_prime.tres` |
| `autoloads/run.gd` | Added prime cards to `_DEFAULT_DECK` (×2 each) and `card_pool` |
| `world/combat_scene.gd` | Added `_m30_smoke()` + call |
| `PROGRESS.md` + this file | Updated |

## Explicitly out of scope

- Targeting overlay showing the prime element preview before firing
- Undo reverting the prime state
- Enemy prime cards
