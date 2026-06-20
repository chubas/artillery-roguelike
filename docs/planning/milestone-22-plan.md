# Milestone 22 — Essence System

## What was built

Per-unit upgrades that occupy upgrade slots (M21). Structurally parallel to the artifact system
but scoped to one unit — each essence receives an `EssenceContext` carrying the owning unit plus
the usual world references. Essences are not sourced from a donor unit; they can come from events,
rewards, shop, or future fusion mechanics.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **`EssenceDef / EssenceContext / EssenceSystem`** triple — mirrors `ArtifactDef / ArtifactContext / ArtifactSystem` exactly; same static-dispatcher and feature-flag pattern. |
| 2 | **Per-unit scope.** `EssenceContext.unit` is the owning unit, set by the combat manager before each hook call. Squad-wide effects require iterating all player units (see `_on_unit_died`). |
| 3 | **Essences are not tied to a specific donor.** No "source unit" field on `EssenceDef`. Origin is determined by how the essence enters the run (reward, event, fusion), not stored in the essence. |
| 4 | **`RunUnitState.equipped_essences: Array[String]`** — paths serialized alongside `upgrades`. The slot math (`upgrade_slots` vs. sum of `slot_cost`) is enforced at equip time (not yet implemented — seam). |
| 5 | **No refire essence loop.** `schedule_refire()` in `CombatManager` does NOT call `EssenceSystem.call_unit_fired()` on the second shot, preventing infinite recursion. |
| 6 | **Feature flag:** `Features.essences_enabled` gates all `EssenceSystem` dispatchers. |
| 7 | **Test fixture:** `run.gd` pre-equips Armor Primer on Cluster and Double Shot on Bypass. Essences are not unit-specific by design; this wiring moves to reward/event flow later. |

---

## Essence 1: Armor Primer

**File:** `data/essences/essence_armor_primer.gd`  
**Resource:** `data/essences/resources/armor_primer.tres`  
**Hook:** `on_combat_start` → `ctx.unit.armor += 10`  
**Slot cost:** 1  
**Effect:** At the start of each combat, the equipped unit gains 10 armor on top of their
`UnitDefinition.base_armor`. Stacks with the armor layer from M20.

---

## Essence 2: Double Shot

**File:** `data/essences/essence_double_shot.gd`  
**Resource:** `data/essences/resources/double_shot.tres`  
**Hook:** `on_unit_fired` → `ctx.combat.schedule_refire(ctx.unit, ctx.last_shot, ctx.last_speed, 2.0)`  
**Slot cost:** 1  
**Effect:** After the unit fires, `CombatManager.schedule_refire()` fires a second shot 2 seconds
later with the same angle and speed. No additional AP cost. If the unit is destroyed before the
timer fires, the refire is silently skipped.

---

## Integration points in CombatManager

| Existing method | Essence hook added |
|---|---|
| `_init_artifacts()` | Calls `_init_essences()` — loads paths, populates `unit.essences`, calls `on_combat_start` |
| `_fire_active()` | After `EventBus.unit_fired.emit()`, sets `ctx.last_shot/speed` and calls `call_unit_fired` |
| `_begin_round()` | After artifact round-start, iterates player units + calls `call_round_start` |
| `end_player_turn()` | After artifact turn-end, iterates player units + calls `call_player_turn_end` |
| `_on_unit_died()` | After artifact death hooks, iterates player units + calls `call_unit_died` |

`schedule_refire()` is a new method: awaits a timer, validates unit still alive, fires via
`_projectiles.fire()`.

---

## Files changed

| File | Change |
|---|---|
| `data/essence_def.gd` | NEW — base resource with all hooks |
| `data/essence_context.gd` | NEW — per-unit context (unit + terrain + all_units + combat + last_shot/speed) |
| `systems/essence_system.gd` | NEW — static dispatcher mirroring ArtifactSystem |
| `data/essences/essence_armor_primer.gd` | NEW — +10 armor on_combat_start |
| `data/essences/essence_double_shot.gd` | NEW — schedule_refire on_unit_fired |
| `data/essences/resources/armor_primer.tres` | NEW — baked |
| `data/essences/resources/double_shot.tres` | NEW — baked |
| `units/unit.gd` | `essences: Array[EssenceDef]` field |
| `state/run_unit_state.gd` | `equipped_essences: Array[String]` + serialize |
| `systems/combat_manager.gd` | `_essence_ctx`, `_init_essences()`, `schedule_refire()`, 4 hook call sites |
| `autoloads/features.gd` | `essences_enabled = true` |
| `autoloads/run.gd` | Pre-equip armor_primer / double_shot for testing |
| `scripts/bake_resources.gd` | `_bake_essence()` helper + M22 bake calls + directory |
| `world/combat_scene.gd` | `_m22_smoke()` + call in `_smoke_test()` |

---

## Seams for later

| Seam | Notes |
|------|-------|
| **Equip validation** | Sum of `slot_cost` on `equipped_essences` vs. `upgrade_slots` — enforce at reward/event equip time |
| **Fusion reward flow** | `RunState.essence_pool: Array[String]` + reward screen category ESSENCE |
| **Default essence per unit** | `UnitDefinition.default_essence: String` — auto-equipped when unit enters squad via reward |
| **Essence compatibility** | `EssenceDef.allowed_factions` or `allowed_unit_types` filter at equip time |
| **Slot cost > 1** | `slot_cost` field already supports it; just needs content |
| **modify_projectile_strength** | Hook already defined; add per-unit strength scaling essences |
