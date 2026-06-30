# Milestone 41 — Keyword System + Tooltips (+ two QoL tweaks)

## Why

Reusable mechanics (today only **Boosted**) appear on units, shots, and card effects and can
*transfer* — the Overdrive card (`boosted_card.tres`, effect `ADD_BOOSTED`) applies the Boosted
status to a unit, which then "has" Boosted. There was no shared way to name these mechanics, attach
them to entities, or explain them on hover. M41 adds a lightweight keyword layer + hover tooltips.
Shield and armor are deliberately **not** keywords yet.

## What shipped

- **`KeywordDef`** (`data/keyword_def.gd`): `id`, `display_name`, `description_template`, `color`.
  Baked to `data/keywords/`. Three keywords: `boosted` (real), `unit`/`shot` (throwaway test
  keywords to verify unit→ and shot→tooltip mapping).
- **`KeywordRegistry`** (`systems/keyword_registry.gd`): static, lazy-loaded id→KeywordDef registry
  plus collectors that return the keyword ids an entity has *right now*:
  - `for_unit(unit)` = definition.keywords + active shot.keywords + any keyword-backed active
    status (status→keyword link is **by shared id**, so the `boosted` status surfaces the `boosted`
    keyword automatically — this is how applied/transferred effects show up).
  - `for_definition(def)`, `for_run_unit(rus)` (adds `boosted` if `permanent_boosted > 0`),
    `for_shot`, `for_card`, and `tooltip(ids)` → multi-line "Name — desc" text ("" when empty).
- **Keyword fields**: `keywords: Array[String]` added to `UnitDefinition`, `ShotDefinition`,
  `CardDefinition`, and `ArtifactDef`. Bake tags every unit `["unit"]` and every shot `["shot"]` via
  a centralized `_tag_test_keywords()` post-pass; the Overdrive card and the Battle Drills artifact
  (both grant Boosted) get `["boosted"]` at their construction sites.
- **`Features.keywords_enabled`** (pre-existing seam, now `true`) gates all collectors.
- **Tooltips on four surfaces** via Godot built-in `tooltip_text` (matching `CardChip`/`ArtifactChip`):
  - Cards in combat — `CardChip._ready` (`ui/hud.gd`).
  - Unit card in combat — `UnitInspector._get_tooltip` (live recompute, so a Boosted applied
    mid-combat appears on the next hover without re-inspecting).
  - Reward previews — `OptionCard.setup` (`ui/reward_screen.gd`), for unit / card / artifact options.
  - Artifact chips in combat — `ArtifactChip._ready` (`ui/hud.gd`).
  - Deck/Squad viewers — row-button `tooltip_text`; deck detail panel also lists keywords.
- **Shared `PatternGlyph`** (`ui/pattern_glyph.gd`): the AoE glyph renderer extracted from
  `UnitInspector._draw_pattern_glyph` so the combat inspector and the reward preview draw identically.

## QoL

1. **Smaller default combat zoom** — `world/combat_scene.gd` `DEFAULT_ZOOM := 0.83` (≈ two `1/1.1`
   steps out from 1.0), set on the camera in `_ready()`. Applies to the battlefield camera.
2. **Richer unit reward preview** — `reward_screen._draw_unit` now draws the default shot's pattern
   glyph + `resolve_description(null)`, conveying the same info as the combat inspector.

## Verification

1. Bake: `godot --headless --import` → `godot --headless --path . res://scripts/bake_runner.tscn`
   → `godot --headless --import`. Confirms `data/keywords/{boosted,unit,shot}.tres` written, every
   unit/shot retagged, and the unit base_power validator still passes.
2. Smoke (`_m41_smoke`, all pass): registry has the 3 keywords; `for_unit` fresh = `["unit","shot"]`;
   after `apply(boosted)` includes `"boosted"`; `for_card(Overdrive)` = `["boosted"]`; `tooltip`
   non-empty and contains "Boosted"; `keywords_enabled=false` → `[]`; `DEFAULT_ZOOM = 0.83`.
   (Pre-existing unrelated failures remain: `_m6_smoke` needs a 3rd player unit; `_m19` MapState.)
3. Manual: hover a hand card / the unit inspector (lists Unit, Shot) → play Overdrive on a unit then
   hover it (now also lists Boosted + description) → Deck/Squad viewer row tooltips → unit reward
   preview shows shot pattern + description → battlefield starts more zoomed-out.
