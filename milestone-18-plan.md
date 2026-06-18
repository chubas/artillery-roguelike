# Milestone 18 — Faction identifiers on content

## What was built

Stable faction **ids** on units, cards, and artifacts — engine-only; no reward-pool filtering yet.
Display names (Seekers / Awakened / Shamans) live in `Faction.display_name()`, not on content.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Ids:** `neutral`, `army` (Seekers), `cell` (Awakened), `bio` (Shamans) — `Faction` class constants. |
| 2 | **`faction: String`** on `UnitDefinition`, `CardDefinition`, `ArtifactDef`. Default `neutral`. |
| 3 | **All current units** baked as `army`. |
| 4 | **Neutral cards:** shield_buff, boosted_card, direct_strike. **Army cards:** mine_card, halve_wind. |
| 5 | **Neutral artifacts:** squad_regen, lifesteal, free_first_card. **Army artifacts:** the rest. |
| 6 | **`RunState.run_meta.faction`** seeded to `army` in `start_default_run()` — seam for run identity / pool filtering later. |

---

## Files changed

| File | Change |
|---|---|
| `data/factions/faction.gd` | Id constants + `display_name()` |
| `data/units/unit_definition.gd` | `faction` field |
| `data/cards/card_definition.gd` | `faction` field |
| `data/artifact_def.gd` | `faction` field |
| `scripts/bake_resources.gd` | Bake assignments |
| `autoloads/run.gd` | `run_meta.faction` |
| `world/combat_scene.gd` | `_m18_smoke()` |

---

## Seams for later

- Reward pools filter by `run_meta.faction` + neutral (`run-design` §6).
- Squad select sets `run_meta.faction` at run start.
- Cross-faction bonus rewards in acts 2–3.
