# Milestone 21 — Shards Currency & Upgrade Slots

## What was built

Two run-state primitives from the currency/retire/fusion design doc, establishing the
scaffolding for future spend mechanics (shop, repair, fusion, upgrades) without implementing
any of those sinks yet.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Single currency: Shards.** Added as `"shards"` key in `RunState.resources` dict (alongside placeholder gold/scrap/intel keys). No second spendable currency. |
| 2 | **Starting Shards: 10.** Set in `Run.start_default_run()`. Sources (terrain destruction, kills, stage clear) are deferred. |
| 3 | **Upgrade slots on `RunUnitState`.** `upgrade_slots: int = 2` — the shared pool for permanent upgrades and fused essences per design doc §5. No upgrade mechanics yet; field is the seam. |
| 4 | **Slot count is per-unit-instance**, not per-definition. A future artifact could expand slots on specific units without touching the definition. |
| 5 | **Serialization:** `upgrade_slots` round-trips through `to_dict`/`from_dict` with `d.get("upgrade_slots", 2)` default (backwards-compatible). |

---

## Files changed

| File | Change |
|---|---|
| `state/run_state.gd` | `"shards": 0` added to default `resources` dict |
| `autoloads/run.gd` | `rs.resources["shards"] = 10` in `start_default_run()` |
| `state/run_unit_state.gd` | `upgrade_slots: int = 2` field + `to_dict`/`from_dict` |
| `world/combat_scene.gd` | `_m21_smoke()` — verifies shards=10, upgrade_slots=2, round-trip |

---

## Seams for later

| Seam | Notes |
|------|-------|
| **Shard sources** | Terrain destruction, kills, stage clear bonuses — all add to `resources["shards"]` |
| **Shard sinks** | Shop purchases, repair, fusion cost, deck thinning, rerolls (design doc §1.3) |
| **Upgrade content** | `RunUnitState.upgrades: Array[String]` already exists; populate once upgrade definitions exist |
| **Slot expansion** | Artifacts/upgrades can increment `upgrade_slots` on specific units |
| **Retire/Fuse** | Retire yields shards; fuse consumes a unit and transplants essence into an upgrade slot |
| **Per-unit prestige** | `kills` field already tracked; design doc §6 describes the future leveling path |
