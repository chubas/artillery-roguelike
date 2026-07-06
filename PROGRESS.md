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

## Current state (2026-07-06 M44)

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
  M16 (battle rewards + dig vs unit damage separation),
  M17 (collapsible terrain: column collapse, crush damage, resolve API),
  M18 (faction ids on units, cards, artifacts),
  M19 (branching map: diamond DAG, click-to-select),
  M20 (armor mitigation layer + element × layer matrix),
  M21 (Shards currency + upgrade slots),
  M22 (Essence system: EssenceDef/Context/System, Armor Primer, Double Shot),
  M23 (Unit capacity + skip rewards),
  M24 (Debug sandbox overlay),
  M25 (Sandbox II: spawn overrides, terrain, inspector, round advance),
  M26 (Tooltip templating + formula-driven leveling),
  M27 (Map squad bar, Shards HUD, repair & retire),
  M28 (Aura visualization + deployable selection),
  M29 (Unit stacking: remove overlap constraint, 2.5D depth offset, scroll-wheel inspector cycle),
  M30 (Elemental prime cards: fire/electric prime cards replace always-on shot selector; shot selector removed),
  M31 (Animation Sequencer: central autoload batch-parallel queue, placeholder animations, EventBus wiring),
  M32 (Profile-driven terrain generation: TerrainGenerator static class, MapData resource, 4 starter profiles),
  M33 (RNG architecture + stage profile variation: RunRng, StageRng, CombatRng autoloads; random terrain profile per stage; first stage always legacy),
  **M34 (Shop node: SHOP type on diamond nodes 3 & 5, ShopScreen CanvasLayer with 5 cards/3 artifacts/1 unit offers, artifact seen-set cycling shared with rewards, re-roll at escalating cost, starting shards 25, +20 shards per combat clear, sandbox Give Shards control; AP rebalance 10→5, all card costs to 1 AP, Halve Wind 0 AP, Direct Strike damage 2; Rarity metadata on all content types with BASIC/COMMON/RARE/EPIC/LEGENDARY/BOSS/EVENT tiers)**,
  **M35 (Special event nodes + extended map: 15-node (1,2,3,3,3,2,1) run map via `build_run_map()`; two event types — Field Triage and Blood Price — with `EventDef` base class, text-based `EventScreen` CanvasLayer, choices resolved directly against `RunState`; EVENT nodes rendered as teal on map; two shops guaranteed at different layers; `act_tags` metadata on stages and events; `Features.events_enabled` kill switch)**,
  **M36 (Repair shop + upgrade shop + CONSUMABLE keyword: REPAIR node (L2) and UPGRADE node (L3) added to map; `RepairScreen` with three options — distribute 4 HP / heal one unit 6 HP / add Heal Vial card; `UpgradeScreen` with three options — upgrade unit stat (+ATK/+Boosted/+FirePrime/+Dig) / fuse two units (transfer essences, 5◆ refund, `FUSION_REFUND` const) / remove up to 2 deck cards; `HEAL` EffectType and `is_consumable` on `CardDefinition` — consumable cards purged from run deck after one use; four permanent upgrade fields on `RunUnitState` applied at combat start via `CombatBridge`; `SquadOps.fuse_units()`; sandbox REPAIR and UPGRADE debug sections; `Features.repair_enabled` and `Features.upgrade_enabled` kill switches)**,
  **M37 (Card Viewer + Squad Viewer: `DeckViewer` and `SquadViewer` modals — `Control` nodes with `set_as_top_level(true)`, open from both world map and combat HUD; "Deck [N]" button top-left and "Squad" button top-right on `MapScreen`; HUD deck label replaced with clickable button, Squad button added in HUD top-right column; `DeckViewer` two-column layout: scrollable card list with cost+name, hover updates detail panel showing effect/target/magnitude/CONSUMABLE; `SquadViewer` shows units with HP, Retire button visible only in world mode (`world_mode=true`), retire calls `SquadOps.retire_unit()`; `Features.deck_viewer_enabled` and `Features.squad_viewer_enabled` kill switches; `CombatManager._process()` null-guard for `_hud`/`_targeting` before `setup()` runs; 60s safety quit timer in `_smoke_test()` to prevent infinite-loop hangs)**,
  **M38 (Unit Weight Classes: `UnitDefinition.weight` integer field replaces `climb_max` — 0=weightless, 1=light, 2=medium, 3=heavy; `UnitMovement.free_climb_for_weight()` and `max_climb_for_weight()` static helpers; `resolve_move()` extended to loop through 1..max_climb voxels finding lowest accessible ledge; `CombatManager._move_ap_cost()` helper computes 1 or 2 AP based on climb height vs free-climb threshold; `try_move()` refactored to separate AP calculation from token handling — token covers 1 AP, extended climbs still deduct remainder from action pool; all current units baked at weight=2 (medium) with light/heavy candidate comments; `Features.weight_mobility_enabled` kill switch)**,
  **M39 (Unified damage formula: `DamageResolver.compute_base(attacker, shot, context) -> float` is the single entry point — formula is `(attack + combat_flat + conditional_bonus) × permanent_mult × combat_mult`; single `floor()` at AoE application, no min-1; `ShotDefinition.strength` and `strength_mult` removed (shots carry AoE pattern + element only); `UnitDefinition.base_power` removed; `Unit.power` renamed `combat_mult`, `Unit.attack_modifier` renamed `combat_flat`; `RunUnitState.permanent_mult` field added with serialization; new `ShotContext` scaffolding class for future conditional bonuses; `ShotDefinition.conditional_bonus: Dictionary` empty on all current shots; `AoEResolver._zone_damage()` returns float (no rounding/min), `_calc_damage()` renamed `_calc_affinity()` returns mult only, final damage is `int(floor(zone_dmg × affinity))`; `Salvo.strength` changed to float; `player_split` baked at attack=1 (multishot unit); `★ N` attack display in UnitInspector HUD; `Features.power_formula_enabled` kill switch)**,
  **M40 (Source-attributed power modifiers: replaces M39's three-field scheme (`attack`/`combat_flat`/`combat_mult`) and `RunUnitState.permanent_mult`/`bonus_attack` with `base_power` + a list of `PowerMod` objects; new `systems/power_mod.gd` (`source`/`label`/`op` ADD|MULT/`value`/`tier` PERMANENT|COMBAT/optional `condition: Callable` compute-time predicate) and `systems/power_calculator.gd` (two-tier fold `permanent = max(0,(base+Σadd)×Πmult)` then `combat = max(0,(permanent+Σadd)×Πmult)`, clamped ≥0 at both tiers; `effective_attack`/`effective_attack_f`/`card_attack`/`breakdown`); `Unit.power_mods` with `add_power_mod`/`adjust_power_mod`/`remove_power_mod`/`attack_value`; permanent mods serialized on `RunUnitState.power_mods` (legacy `bonus_attack` migrated to a permanent ADD mod, `permanent_mult` dropped); `UnitDefinition.attack` removed (base_power is the printed number: 3 standard / 10 Drill / 1 Splitter); `DamageResolver.compute_base` reads `PowerCalculator.effective_attack_f`; `enemy_debuff` artifact migrated to an accumulating −3 COMBAT ADD mod; new `ArtifactLastStand` (×1.5 COMBAT MULT gated by a sole-survivor predicate) validates the conditional path; HUD inspector shows `★ N` plus a per-mod breakdown; flight-time `modify_projectile_strength` hook widened to float; `Features.power_mods_enabled` kill switch)**,
  **M41 (Keyword system + hover tooltips: `KeywordDef` resource (`data/keyword_def.gd`) baked to `data/keywords/` — `boosted` real keyword + `unit`/`shot` test keywords; `KeywordRegistry` static lazy registry (`systems/keyword_registry.gd`) with collectors `for_unit`/`for_definition`/`for_run_unit`/`for_shot`/`for_card` and `tooltip(ids)` formatter; status→keyword link by shared id so the Boosted status surfaces the `boosted` keyword; `keywords: Array[String]` on UnitDefinition/ShotDefinition/CardDefinition, bake tags all units `["unit"]` + all shots `["shot"]` via `_tag_test_keywords()`, Overdrive card `["boosted"]`; built-in `tooltip_text` tooltips on combat hand cards, combat unit inspector (`_get_tooltip` live recompute), reward previews, and Deck/Squad viewer rows; shared `PatternGlyph` (`ui/pattern_glyph.gd`) extracted from UnitInspector; `Features.keywords_enabled` gate; QoL — combat `DEFAULT_ZOOM=0.83` set in `_ready`, unit reward preview shows shot pattern glyph + description)**,
  **M42 (Mineral terrain + Ore drops + currency rename: run currency moved from `RunState.resources["shards"]` to `RunState.currency` with `add_currency`/`spend_currency`/`can_afford` (UI keeps "◆ Shards", combat HUD readout added, `from_dict` migrates legacy saves); new `Tile.TileType.MINERAL` (durability 2, collapsible, standable via broadened `is_solid`), pink `COLOR_MINERAL` in `chunk.gd`; `TerrainManager.scatter_minerals(seed)` clustered patches (some surface-exposed) run in `_setup_terrain`, gated by `Features.minerals_enabled`; breaking a MINERAL emits `EventBus.mineral_destroyed` → `OreSystem` (`systems/ore_system.gd`) spawns an `Ore` (`world/ore.gd`, floating pink circle above units in a new OreLayer); on `aoe_resolved` ores fall under gravity one voxel at a time until blocked by terrain/map floor, merging only when landing on another Ore (buried ore never rises); Ore shows its currency value in purple; a player unit collects an Ore inside its footprint or one voxel below its base via `try_collect` in `try_move` for `value×2` currency (`EventBus.ore_collected`); move-undo snapshots ore set + currency and restores both; `ORE_CURRENCY=2`)**,
  **M43 (Terrain generation v2 — placer contract + anchors + seams + validation: pipeline reordered to noise-first (A base+noise everywhere → B features → C seams → D HP/variants → E validation) so features anchor to the real surface; per-feature placer modules in `terrain/placers/` registered in `TerrainGenerator.PLACERS`, each returning a `FeatureInstance` (`terrain/feature_instance.gd`: id, footprint, named anchors — exact `Vector2i` or zone `Rect2i` — edge specs, gap rects) carried on `MapData.features`; anchors exported per construct (bunker `core`/`aperture_n`/`interior`, ridge `summit_center`/`reverse_slope`, pit rims, pillar top, crystal vein); `terrain/seam_pass.gd` reconciles edges (RAMP staircase 2 voxels/column until ground, GAP re-carve, FLUSH foundations, CLIFF no-op) with new `GenOrigin.SEAM`; `terrain/map_validator.gd` checks dig-cost-weighted reachability to the enemy zone (budget 40), zone clearance (2×3), and per-placer validators, with reroll `hash([seed, attempt])` ≤5 attempts then loud warning; HP sprinkle now skips feature tiles (was silently downgrading bunker shells); sandbox minimap gains anchors overlay + toggle, SEAM color, and a validation readout; `Features.terrain_v2_enabled` gates seams+validation; design doc updated to v0.2)**,
  **M44 (Hand-authored ASCII maps — procedural generation deactivated: maps are plain-text files (`data/maps/*.txt` + drop-in `user://maps/*.txt`) with `key: value` metadata (id/title/description/notes/width/height + `spawn_zones`/`enemy_zones` as `[x0,y0,x1,y1]` boxes) and an ASCII grid (`'.'` void, `1`–`9` SOLID hp N, `0` indestructible, `M` MINERAL); `terrain/custom_map.gd` parses + builds MapData, `terrain/map_library.gd` scans/caches both dirs; `MapNode.custom_map_id` assigned randomly per combat node from the pool (run-seeded, node 0 included), profiles/legacy only as fallback; `combat_scene._setup_terrain` loads the map and skips `scatter_minerals` (M chars are the only minerals); `CombatManager._zone_surface_top` finds the topmost floor WITHIN a zone box (caves/islands) for placement, `_random_zone_drop` (StageRng) places initial enemies/reinforcements/deployables in enemy zones ignoring stage cols; placement overlay draws zone boxes; sandbox Map dropdown + Load Map; `Features.custom_maps_enabled`; generator classes remain dormant + smoke-tested; test map `test_flat`)**.
- **Main scene:** `world/run_controller.tscn` (swaps map ↔ reward screens ↔ `combat_scene.tscn`).
  `combat_scene.tscn` is still standalone-runnable. Map is 120×100 voxels. Default run map is a
  15-node extended map (`MapState.build_run_map`); `build_diamond` and `build_linear` kept for smoke/regression.
- **Verify:** `ARTILLERY_SMOKE=1 godot --headless --path . res://world/combat_scene.tscn` runs M3–M27 checklists headless (all pass). Use the `.tscn` form — `-s combat_scene.gd` skips autoload registration at parse time and fails to compile. After adding new `class_name` scripts, run `godot --headless --import` once (and commit the generated `.uid` files). M24/M25 have no smoke test — they're dev tools verified manually.
- **Re-bake resources** after changing any generator in `scripts/bake_resources.gd`:
  `godot --headless --import` → `godot --headless --path . res://scripts/bake_runner.tscn` → `godot --headless --import`.
  Do not use `-s scripts/bake_resources.gd` — that entry skips autoload registration at parse time.
- **Known orphan:** `world/world.tscn` references a deleted `world/world.gd` and logs a harmless
  load error on import. Left in place intentionally.

---

## 2026-07-06 — Milestone 44: Hand-Authored ASCII Maps (generator deactivated)

Pivot: procedural output wasn't hitting the quality bar, so combat maps are now **hand-designed
text files**; the M32/M43 generator stays in the repo, dormant behind its flags. Full design +
file format in [docs/planning/milestone-44-plan.md](docs/planning/milestone-44-plan.md).

- **Format:** `key: value` metadata (id, title, description, notes, width, height,
  `spawn_zones`/`enemy_zones` as `[x0, y0, x1, y1]` boxes) then `data:` + an ASCII grid — `' '`
  void, `1`–`9` SOLID with that hp, `0` indestructible, `M` MINERAL (Ore economy, M42).
- **Loading:** `MapLibrary` scans `res://data/maps/*.txt` and `user://maps/*.txt` (drop-in, user
  overrides by id). Parse problems are loud warnings and the file is skipped.
- **Selection:** every combat node (incl. the first) draws a random map id at run start
  (run-seeded). Missing/broken map → profile/legacy fallback. `Features.custom_maps_enabled`.
- **Zones:** placement clicks resolve to the spawn zone box and drop on the topmost floor
  *within the box* (`_zone_surface_top` — works inside caves/on islands); enemies,
  reinforcements, and deployables ignore stage `col`s and land at seeded random spots in the
  enemy zones (`_random_zone_drop`). The placement overlay draws the zone boxes.
- **Sandbox:** Map dropdown + Load Map button (live terrain + minimap + zones + parse readout).
- **New files:** `terrain/custom_map.gd`, `terrain/map_library.gd`, `data/maps/test_flat.txt`.
  **Smoke:** `_m44_smoke()`; `_m33_smoke` expectation updated (profiles superseded).

## 2026-07-03 — Milestone 43: Terrain Generation v2 (Placers, Anchors, Seams, Validation)

Implements the generator-side architecture of the terrain-generation design doc **v0.2**
(updated this milestone). Full design in
[docs/planning/milestone-43-plan.md](docs/planning/milestone-43-plan.md).

- **Pipeline reorder:** noise/base fill now runs FIRST across all columns; features are stamped
  against the real surface (v1 anchored them on an empty map). Stages: A noise → spawn platform →
  B features → C seams → D HP/variants → E validation.
- **Placer contract:** one module per construct in `terrain/placers/` (registry
  `TerrainGenerator.PLACERS`); each returns a `FeatureInstance` (footprint, named anchors — exact
  voxel or zone rect — edge specs, gap rects) collected on `MapData.features`. Adding a construct =
  one placer script + one registry line + a `.tres`.
- **Seam pass:** RAMP staircases (2 voxels/column, climbable) down to the natural ground, GAP
  re-carving, FLUSH foundations, CLIFF no-op; seam tiles carry `GenOrigin.SEAM`.
- **Validation + reroll:** dig-cost-weighted reachability (spawn → enemy zone, budget 40), zone
  clearance, per-placer function checks; on failure regenerate with a derived seed (≤5), then warn
  loudly and use the last attempt. `Features.terrain_v2_enabled` gates seams + validation.
- **Fix:** the reinforced-HP sprinkle no longer touches feature tiles (it could silently downgrade
  bunker shell tiles from hp 8–12 to 6).
- **Sandbox:** minimap anchors overlay (+ "Anchors" toggle), SEAM color, `gen: attempt N/5` readout.
- **New files:** `terrain/feature_instance.gd`, `terrain/seam_pass.gd`, `terrain/map_validator.gd`,
  `terrain/placers/*.gd`. **Smoke:** `_m43_smoke()` (`_m32_smoke` still passes).

## 2026-06-30 — Milestone 42: Mineral Terrain + Ore Drops + Currency Rename

Adds a mine-and-collect economy and renames the run currency. Full design in
[docs/planning/milestone-42-plan.md](docs/planning/milestone-42-plan.md).

- **Currency rename:** `RunState.currency: int` + `add_currency`/`spend_currency`/`can_afford`
  replaces `resources["shards"]` at all ~15 sites (`from_dict` migrates legacy saves). UI keeps
  "◆ Shards" wording; a live readout was added to the combat HUD.
- **MINERAL terrain:** new `Tile.TileType.MINERAL` (durability 2, collapsible, standable), pink in
  `chunk.gd`; `TerrainManager.scatter_minerals(seed)` places small clustered patches (some exposed)
  after terrain build in `_setup_terrain`, gated by `Features.minerals_enabled`.
- **Ore drops:** breaking a MINERAL vein emits `EventBus.mineral_destroyed` → `OreSystem` spawns an
  `Ore` (floating pink circle with its currency value in purple, high z-index above
  units/deployables). On `aoe_resolved` (post-collapse) ores **fall under gravity** one voxel at a
  time until blocked by terrain or the map floor, merging only when landing on another Ore (values
  sum; buried ore never rises). A player unit collects an Ore inside its footprint or one voxel
  below its base (`try_collect` in `try_move`) for `value × 2` currency (`EventBus.ore_collected`).
  Move-undo snapshots the ore set + currency and restores both.
- **New files:** `world/ore.gd`, `systems/ore_system.gd`. **Smoke:** `_m42_smoke()`.

## 2026-06-30 — Milestone 41: Keyword System + Tooltips

Adds a named-mechanic **keyword** layer with hover tooltips, plus two QoL tweaks. Currently the only
real keyword is **Boosted**; `unit`/`shot` are throwaway test keywords proving unit/shot→tooltip
mapping. Shield and armor are intentionally not keywords yet. Full design in
[docs/planning/milestone-41-plan.md](docs/planning/milestone-41-plan.md).

- **`KeywordDef`** (`data/keyword_def.gd`): `id`/`display_name`/`description_template`/`color`, baked
  to `data/keywords/`. **`KeywordRegistry`** (`systems/keyword_registry.gd`): static lazy registry +
  collectors `for_unit` / `for_definition` / `for_run_unit` / `for_shot` / `for_card` and a
  `tooltip(ids)` formatter. Status→keyword link is **by shared id**, so a unit carrying the `boosted`
  status (via the Overdrive card or `permanent_boosted`) surfaces the `boosted` keyword automatically.
- **`keywords: Array[String]`** added to `UnitDefinition`/`ShotDefinition`/`CardDefinition`. Bake tags
  every unit `["unit"]` and every shot `["shot"]` through a centralized `_tag_test_keywords()` pass;
  Overdrive card → `["boosted"]`. `Features.keywords_enabled` (existing seam) flipped on; gates all
  collectors.
- **Tooltips** (Godot built-in `tooltip_text`, matching `CardChip`/`ArtifactChip`) on all four
  surfaces: combat hand cards (`CardChip`), combat unit inspector (`UnitInspector._get_tooltip`, live
  recompute so mid-combat Boosted shows on next hover), reward previews (`OptionCard`), and Deck/Squad
  viewer rows (+ keyword list in the deck detail panel).
- **`ui/pattern_glyph.gd`** (`PatternGlyph.draw`): AoE glyph renderer extracted from
  `UnitInspector._draw_pattern_glyph` and shared with the reward preview.
- **QoL:** combat camera `DEFAULT_ZOOM := 0.83` (≈ two scroll steps out) set in `combat_scene._ready`;
  unit reward preview now shows the default shot's pattern glyph + description.
- **Smoke:** `_m41_smoke()` — registry loads 3 keywords; `for_unit` fresh `["unit","shot"]`, +`boosted`
  after applying the status; `for_card(Overdrive)=["boosted"]`; tooltip formatting; flag-off → `[]`.

## 2026-06-29 — Milestone 40: Source-Attributed Power Modifiers

Reworks attack power into `base_power` + a list of source-tagged `PowerMod`s, folded on demand by
`PowerCalculator` in two tiers (permanent → combat). Modifiers can be additive or multiplicative,
carry the `source` that created them (so they can be removed/shown/stacked), and may gate behind a
compute-time predicate. The unit holds no scalar attack field; effective attack is computed.
Full design in [docs/planning/milestone-40-plan.md](docs/planning/milestone-40-plan.md).

- **Two-tier fold:** `permanent = max(0, (base_power + Σ perm_add) × Π perm_mult)` is the card /
  round-start value; `combat = max(0, (permanent + Σ comb_add) × Π comb_mult)` is the live value.
  Clamped ≥0 at both boundaries so a net-negative permanent can't flip sign under a combat mult.
- **`PowerMod`** (`systems/power_mod.gd`): `source`, `label`, `op` (ADD|MULT), `value`, `tier`
  (PERMANENT|COMBAT), optional `condition: Callable`. `to_dict`/`from_dict` (predicate not
  serialized — conditional mods are re-attached live by their source each combat).
- **`PowerCalculator`** (`systems/power_calculator.gd`): `effective_attack` / `effective_attack_f`
  (live unit), `card_attack(run_state, definition)` (permanent-tier only, for cards/logbook),
  `breakdown` (ordered rows for the inspector tooltip).
- **`Unit`**: `power_mods: Array[PowerMod]` + `add_power_mod` / `adjust_power_mod` (accumulating) /
  `remove_power_mod` / `attack_value`. `_ready()` seeds permanent mods from `run_state.power_mods`.
- **`RunUnitState`**: `permanent_mult` and `bonus_attack` removed; `power_mods: Array` of dicts
  serialized; `add_permanent_mod()`; `from_dict` migrates legacy `bonus_attack` → permanent ADD mod.
- **`DamageResolver.compute_base`** now reads `PowerCalculator.effective_attack_f`; the single
  `floor()` still lives in AoEResolver. `UnitDefinition.attack` removed (base_power is the number).
- **Artifacts:** `enemy_debuff` → accumulating −3 COMBAT ADD mod; new `ArtifactLastStand` (×1.5
  COMBAT MULT gated by a "sole surviving player unit" predicate) proves the conditional path.
- **UI:** inspector shows `★ N` plus a per-mod breakdown; upgrade/reward/sandbox use the new API.
- **Smoke:** `_m40_smoke()` asserts the two-tier fold (8 then 13.50/13), ≥0 clamp, predicate
  on/off, `card_attack` ignoring combat mods, and the Last Stand artifact. `power_mods_enabled` flag.

## 2026-06-28 — Milestone 38: Unit Weight Classes

Weight-based climb mobility: `UnitDefinition.weight` replaces `climb_max`. Light units (weight=1) climb up to 3 voxels (1–2 free, 3rd costs 2 AP); medium (weight=2) up to 2 voxels (1 free, 2nd costs 2 AP); heavy (weight=3) are ground-locked. Boosted move token still covers 1 AP — extended climbs deduct the remainder from the action pool. All baked units set to weight=2. Full design in [docs/planning/milestone-38-plan.md](docs/planning/milestone-38-plan.md).

## 2026-06-26 — Milestone 37: Card Viewer + Squad Viewer

Persistent modals for reviewing the run deck and squad roster, accessible from both the world map and active combat. Full design in [docs/planning/milestone-37-plan.md](docs/planning/milestone-37-plan.md).

- **`DeckViewer`** (`ui/deck_viewer.gd`) — `Control` with `set_as_top_level(true)`. Two-column layout: left = scrollable card list (cost + name, ◇ for CONSUMABLE), right = detail panel (effect/target/magnitude) updated on hover. Deduplicates deck paths with counts. Click backdrop to close.
- **`SquadViewer`** (`ui/squad_viewer.gd`) — `Control` with `set_as_top_level(true)`. Unit rows with HP. Clicking a row selects it (gold highlight). In `world_mode=true`, "Retire Unit" button is visible and enabled when a unit is selected; calls `SquadOps.retire_unit()` and emits `retired`. Button is hidden entirely in `world_mode=false` (combat).
- **`MapScreen`** — "Deck [N]" button added to top-left of top row (updates in `_refresh()`); "Squad" button added to top-right. Handlers open the respective viewer as a child; `retired` signal triggers `_refresh()`.
- **`HUD`** — `_deck_label` replaced with `_deck_btn` (same text "Deck N · Discard N", now clickable → `DeckViewer`). "Squad" button added in top-right column below "Undo Move". Viewers open as HUD children in combat mode (no Retire).
- **`CombatManager._process()`** — null guard added (`if _hud == null or _targeting == null: return`) to prevent error spam during the 1-frame window before `setup()` is called.
- **`_smoke_test()`** — 60s safety quit timer added at the start. `get_tree().quit(1)` on timeout prevents the runner from hanging indefinitely on future errors.
- **`Features`** — `deck_viewer_enabled`, `squad_viewer_enabled` kill switches.
- **Smoke:** `_m37_smoke()` — DeckViewer and SquadViewer (world + combat mode) instantiate and enter tree correctly; feature flags true (all pass).

---

## 2026-06-24 — Milestone 35: Special Event Nodes + Extended Map

Extends the run map from a 9-node diamond to a 15-node (1,2,3,3,3,2,1) structure with dedicated event and shop placement. Two text-based events resolve immediately against `RunState` via a new `EventDef` base class. Full design in [docs/planning/milestone-35-plan.md](docs/planning/milestone-35-plan.md).

- **`EventDef` base class** (`data/event_def.gd`) — `Resource` with `event_id`, `title`, `description`, `act_tags: Array[String]`; virtual `choices(rs: RunState) -> Array[Dictionary]` and `resolve(choice_index, rs)`.
- **`EventTriage`** (`data/events/scripts/event_triage.gd`) — "Field Triage": choice A restores the most-hurt or dead unit to full HP (revives); choice B restores 2 HP to all units.
- **`EventBloodPrice`** (`data/events/scripts/event_blood_price.gd`) — "Blood Price": choice A grants 10 free shards; choice B sacrifices 3 HP from the highest-HP unit for 20 shards (disabled if that unit has ≤3 HP).
- **`EventScreen`** (`ui/event_screen.gd`) — CanvasLayer showing title, description, and choice buttons. Disabled buttons for unavailable choices. Calls `ev.resolve(idx, Run.active)` on selection, emits `event_completed`.
- **`MapState.build_run_map(stage_paths, event_paths)`** — 15-node map with fixed type assignments: L2 node 3=EVENT(triage), L3 node 7=SHOP, L4 node 10=EVENT(blood_price), L5 node 12=SHOP. Edges follow a fully connected branching pattern. `build_diamond()` and `build_linear()` preserved unchanged.
- **`MapNode`** — added `event_path: String = ""` field and `event() -> EventDef` method. Serialized in `to_dict()/from_dict()`.
- **`StageDescriptor`** — added `@export var act_tags: Array[String] = ["act_1"]` (metadata only; all stages baked with `["act_1"]`).
- **`Run.start_default_run()`** — switches from `build_diamond(_DEFAULT_MAP)` to `build_run_map(_DEFAULT_MAP, _EVENT_PATHS)`.
- **`RunController`** — `_on_node_selected()` dispatches EVENT nodes to `_enter_event()`; fallback to combat if event resource is null.
- **`MapScreen`** — EVENT nodes render as teal; detail text shows event title via `ev.title`.
- **`Features.events_enabled`** kill switch.
- **Baked resources:** `data/events/resources/event_triage.tres`, `data/events/resources/event_blood_price.tres`.
- **Smoke:** `_m35_smoke()` — node_count=15, shop_count=2, event_count=2, shops_different_layers=true, events_have_paths=true, events_loadable=true, stage_act_tags=["act_1"], triage/blood_price choice_count=2 (all correct).

---

## 2026-06-23 — Milestone 33: RNG Architecture + Stage Profile Variation

Three explicit RNG layers separate deterministic run sequencing from per-stage reproducibility from real-time combat non-determinism. Full design in [docs/planning/milestone-33-plan.md](docs/planning/milestone-33-plan.md).

- **`StageRng` autoload** (`autoloads/stage_rng.gd`) — seeded per combat from node's `stage_seed`. Provides `init(seed)` and `shuffle(arr)` (Fisher-Yates). Used for deck shuffle in `CombatManager._build_deck()` and `_reshuffle_discard()`.
- **`CombatRng` autoload** (`autoloads/combat_rng.gd`) — seeded with `stage_seed ^ Time.get_ticks_msec()` for intentional non-determinism. Used for wind variance (`combat_manager.gd`) and enemy fire error (`enemy_system.gd`).
- **`Run.run_rng`** — `RandomNumberGenerator` on the `Run` autoload, seeded from `run_meta["seed"]` (already existed; was always `randi()`). Used in `RunController._sample()` for deterministic reward sampling. `_assign_terrain_variations()` draws `stage_seed` and `terrain_profile_path` per node from `run_rng`.
- **`MapNode`** — two new fields: `terrain_profile_path: String` and `stage_seed: int`. Both serialized in `to_dict()/from_dict()`. Node 0 always gets `terrain_profile_path = ""` (legacy generator); all others get a random profile from `_TERRAIN_PROFILES`.
- **`CombatScene`** — `terrain_profile_path` and `active_stage_seed` fields; `RunController._enter_combat()` sets these from the `MapNode` before entering. `_setup_terrain()` reads them (falls back to `stage.terrain_seed`/`stage.terrain_profile` for standalone runs).
- **`Features.stage_rng_enabled`** kill switch — when false, decks use built-in `.shuffle()`, wind/fire use global `randf_range()`, RNG autoloads stay unseeded.
- **Smoke:** `_m33_smoke()` — `StageRng.rng.seed=12345`, `CombatRng.rng.seed≠0`, determinism check passes (same `run_seed` → same `node[1].stage_seed`), `node[0].terrain_profile_path=''`, `node[1].terrain_profile_path='res://data/terrain/profiles/open_field.tres'` (all correct).

---

## 2026-06-22 — Milestone 32: Profile-Driven Terrain Generation

Introduced a decoupled terrain pipeline: `TerrainGenerator` (static class) takes a `TerrainProfile` + seed and produces a serializable `MapData` resource; `TerrainManager.load_map()` hydrates it into live `Tile` objects. Existing stages use the legacy `generate()` path unchanged. Full design in [docs/planning/milestone-32-plan.md](docs/planning/milestone-32-plan.md).

- **`MapData` resource** (`terrain/map_data.gd`) — flat cell array of `null|Dictionary`, owns `width` + `height`, `GenOrigin` enum per cell for the visualizer. Serializable, saveable, hand-authorable.
- **`TerrainGenerator` static class** (`terrain/terrain_generator.gd`) — `generate(profile, seed) -> MapData`. 4 passes: Pass 1 places skeletal features (ridge, pit, pillar, bunker, crystal deposit); Pass 2 fills unclaimed columns with noise (amplitude capped by profile); Pass 3 assigns 10% reinforced HP; Pass 4 assigns visual variants. No autoload needed.
- **`TerrainProfile` + `FeatureDefinition` resources** — profile specifies map dimension ranges, noise amplitude cap, slot assignments (left/center/right), background features, and enemy zone bounds. `FeatureDefinition` carries type, dimension ranges, and a `special_params` dict (slope_edges, aperture_count, gap_from_terrain).
- **`TerrainManager` changes** — added `map_width`/`map_height` instance vars (default to Const), `chunks_wide()`/`chunks_tall()` helpers, and `load_map(MapData)`. `generate()` kept as legacy path.
- **`TerrainRenderer` change** — `_build_chunks()` and `_on_tile_changed()` now call `_terrain.chunks_wide()`/`chunks_tall()` instead of `Const.chunks_*()`; renderer must be set up after `load_map()`.
- **`StageDescriptor`** — added `terrain_profile: TerrainProfile = null`; null selects legacy path; existing stage .tres files unchanged.
- **`_setup_terrain()` in `combat_scene.gd`** — routes to generator or legacy based on profile/feature flag.
- **4 starter profiles baked** — `open_field`, `ridge_assault` (center ridge), `fortress_siege` (right bunker), `pit_crossing` (center pit).
- **Sandbox Terrain Visualizer** — new section in sandbox overlay (backtick). Profile dropdown, seed field, "Preview" button, minimap colored by `GenOrigin`: grey=noise, cyan=spawn platform, orange/yellow/green=left/center/right slot, cyan=crystal.
- **`Features.terrain_profiles_enabled`** kill switch.
- **Smoke:** `_m32_smoke()` — `map_size=122x106`, `solid_fraction=0.55`, `ridge_center_tiles=390`, `bunker_shell_tiles=97` (all correct).

---

## 2026-06-22 — Milestone 31: Animation Sequencer

Introduced the central `AnimationSequencer` autoload to decouple logic resolution from visual playback. All placeholder animations (color flashes, fades, world bursts) are now queued through a batch-parallel system. Full design in [docs/planning/milestone-31-plan.md](docs/planning/milestone-31-plan.md).

- **`AnimationSequencer` autoload** — registered in `project.godot`. Subscribes to 8 EventBus signals in `_ready()`. Guards on `Features.animations_enabled`. `fast_forward = true` when `ARTILLERY_SMOKE=1` so all animations complete synchronously.
- **Batch-parallel queue** — `_batches: Array` of sealed batches; entries in the same batch play in parallel; batches play sequentially. `enqueue(entry)` appends to the open `_current_batch`. `next_batch()` seals and pushes it. `_flush_and_play()` / `_play_next_batch()` drive playback.
- **`AnimationEntry` class** (`animation/animation_entry.gd`) — `RefCounted` with fields: `anim_id`, `target`, `params`, `duration`, `interruptible`, `on_complete: Callable`, `event_type`, `wave`, `tags: Array[String]`.
- **Auto-batching by `event_type`** — impact and death handlers call `next_batch()` before enqueue; this automatically separates hit wave → impact wave → death wave in a single turn resolution.
- **CONNECT_ONE_SHOT completion** — `entry.target.anim_done.connect(_on_entry_done.bind(entry), CONNECT_ONE_SHOT)`. Nodes own their tween logic and emit `anim_done` when done; they never reference the sequencer.
- **`WorldFXLayer`** (`animation/world_fx_layer.gd`) — `Node2D` child of `combat_scene.tscn`. Handles null-target world FX (projectile impact burst: circle tween, radius + alpha). `combat_scene._ready()` sets `AnimationSequencer.world_fx = world_fx`.
- **Unit animation interface** (`units/unit.gd`) — added `signal anim_done`, `var _dying: bool`, `play_anim()`, `snap_anim()`, `_apply_anim_end_state()`. Animations: `hit_flash` (tint tween), `death_fade` (alpha to 0), `status_pulse` (alpha flicker). Dead units stay in the scene tree until `death_fade` completes — no `queue_free`.
- **Deployable animation interface** (`world/deployable.gd`) — same interface. Animations: `deploy_appear` (scale 0→1), `deploy_destroyed` (modulate flash + alpha to 0). `queue_free` deferred to `on_complete` callback on the `deploy_destroyed` entry; `CombatManager._on_deployable_died()` no longer calls `d.queue_free()` directly.
- **EventBus: `deployable_placed`** — new signal in `event_bus.gd`; emitted in `CombatManager._spawn_deployables()` and mine spawn.
- **`Features.animations_enabled`** — kill switch added to `features.gd`.
- **Smoke:** `_m31_smoke()` — verifies `fast_forward=true`, `world_fx` valid, sequencer idle after resolve, and foe took damage.

---

## 2026-06-21 — Milestone 30: Elemental Prime Cards + Shot Selector Removal

Fire and electric shots were always-available 1/2/3 key options. M30 converts them to one-use cards that prime the next shot with an element, and removes the shot-selection UI. Full design in [docs/planning/milestone-30-plan.md](docs/planning/milestone-30-plan.md).

- **Two new cards** — `Fire Prime` (2 AP) and `Electric Prime` (2 AP), both ALLY-targeted. Baked to `data/cards/fire_prime.tres` and `data/cards/electric_prime.tres`. Starting deck gets 2 copies of each; `card_pool` includes both for rewards.
- **`Unit.primed_elements: Array[ElementDef]`** — accumulated by prime cards; multiple elements stack (a single shot can be fire + electric). Consumed at fire time, not on impact.
- **`Salvo.element_overrides: Array[ElementDef]`** — captured from `firing_unit.primed_elements` in `ProjectileManager.fire()` at launch time.
- **Multi-element AoE** — `_resolve_blast()` loops over `element_overrides`, calling `AoEResolver.resolve()` once per element at full strength. When empty, resolves normally (one pass with the pattern's own element).
- **`AoEResolver.resolve()` extended** — optional `element_override: ElementDef = null` param; overrides `group.element` when set. All existing callers pass no override → unchanged behavior.
- **Shot selector fully removed** — `_select_shot()`, `signal shot_selected`, KEY_1/2/3 branches, `set_shots()` HUD method, and shot-chip strip all deleted. `unit.selected_shot` kept (inert).
- **Family unit loadouts trimmed** — `_make_family()` still bakes the full trio (elemental shots stay on disk) but returns `[trio[0]]` (basic only). `player_heavy` and `player_light` also set to `[basic_ref]`.
- **Primed indicator** — `UnitInspector._draw()` shows `PRIMED: FIRE` (orange) / `PRIMED: ELECTRIC` (cyan) lines for each active prime.
- **Smoke:** `_m30_smoke()` — applies fire prime card to ally, verifies `primed_elements[0].id == "fire"`, fires AoE on enemy with the element, confirms damage.

---

## 2026-06-21 — Milestone 29: Unit Stacking

Dropped the constraint that two units (or deployables) cannot occupy the same voxel. Full design in [docs/planning/milestone-29-plan.md](docs/planning/milestone-29-plan.md).

- **Stacking allowed** — `UnitMovement.resolve_move()` no longer calls `overlaps_any_unit()` after settling. `_placement_drop()` and `_find_valid_spawn()` also drop their overlap guards. `overlaps_any_unit()` kept as a utility for future queries.
- **2.5D depth offset** — `stack_visual_offset: Vector2` added to `Unit` and `Deployable`. `_recompute_stack_offsets()` in `CombatManager` assigns `Vector2(-2*i, -2*i)` to stacked entities and is called after every move, death, placement confirm, and reinforcement spawn. `Unit._draw()` applies the offset via `draw_set_transform(stack_visual_offset)`. `Deployable._draw()` shifts only the body rect (shield generator aura stays at true map position).
- **Scroll-wheel inspector cycling** — hovering 2+ stacked entities and scrolling cycles the HUD inspector through them (inspect-only; active-turn unit unchanged). Scroll zoom removed from `combat_scene._unhandled_input()`; keyboard +/- still zooms. `CombatManager._scroll_stack_cycle()` + `_entities_at_vox()` handle the cycle logic.
- **AoE/mine triggers unchanged** — `AoEResolver` already iterates all units; stacked units each take damage independently. Mine Chebyshev trigger already catches distance 0.
- **Feature flag** — `Features.stacking_enabled` gates the system (`features.gd`).
- **Smoke:** `_m29_smoke()` — stacks two enemies, checks same-voxel, verifies `-2,-2` offset, fires `diamond_r2` AoE and confirms both took damage.

---

## 2026-06-20 — Milestone 27: Map Squad Bar, Shards HUD, Repair & Retire

World map is now the squad-management hub between stages. Full design in [docs/planning/milestone-27-plan.md](docs/planning/milestone-27-plan.md).

- **Shards HUD** on `MapScreen`: `◆ Shards: N` always visible (starts at 10 from M21).
- **Squad portrait bar** (`UnitPortrait`): card-frame placeholders using `UnitDefinition.color`; hover tooltip shows name + HP; disabled units are desaturated with a red border.
- **Unit actions** (click any portrait): **Retire (+2 ◆)** on any unit; **Repair (5 ◆)** on disabled units only. `SquadOps` static utility owns repair/retire/capacity logic.
- **Repair** restores full HP and clears `is_disabled`. **Retire** removes the unit from squad and frees capacity.
- **Smoke:** `_m27_smoke()` in `combat_scene.gd`. New `class_name` scripts require `godot --headless --import` once (commit the generated `.uid` files).

---

## 2026-06-20 — Milestone 26: Tooltip Templating + Formula-Driven Leveling

Description strings now resolve from the same formula the gameplay code uses. Full design in [docs/planning/milestone-26-plan.md](docs/planning/milestone-26-plan.md).

- **`description_template` + `resolve_description()`** added to all def types: `ShotDefinition`, `CardDefinition`, `ArtifactDef`, `EssenceDef`, `StatusEffectDef`. Templates use `{token}` placeholders resolved by `String.format()`.
- **Shot resolver** (`ShotDefinition.resolve_params(unit)`) computes `damage`, `dig`, `count`, `cost`, `uses` from the same formula `ProjectileManager` uses — tooltip values and gameplay values are mechanically coupled. AoE shape is NOT tokenized (use `[[shape]]` placeholder where text is needed; visual glyph is the display).
- **Card level scaling** (`CardDefinition.effective_magnitude(level)`): `magnitude + magnitude_per_level * level`. Level source is card upgrade tier from `Run.active.card_upgrades.get(card.id, 0)` (not unit level). `RunState.card_upgrades: Dictionary = {}` added as the seam.
- **Essence level scaling** (`EssenceDef.effective_value(level)`): `base_value + value_per_level * level`. Level from `unit.run_state.level`. `RunUnitState.level: int = 0` added as the seam. `EssenceArmorPrimer` reads `def.effective_value(level)` instead of a hardcoded 10.
- **Display sites updated:** `hud.gd` (shot inspector panel + artifact icon tooltip), `reward_screen.gd` (artifact option cards).
- **Bake script updated:** all `description` → `description_template` assignments use `{token}` placeholders where values come from def fields. `armor_primer.tres` gains `base_value = 10`.
- **Smoke test command fixed:** `-s combat_scene.gd` silently skipped autoload registration at GDScript parse time, causing `Identifier not found: Run` after any cache invalidation. Correct form: `godot --headless --path . res://world/combat_scene.tscn`.
- **Type annotation fix:** `var card_level : int =` (not `:=`) on the `Dictionary.get()` call in `CombatManager._apply_card()` — Godot 4 treats inferred-Variant as an error.

---

## 2026-06-20 — Milestone 25: Sandbox II

Enhancements to the debug overlay. Full design in [docs/planning/milestone-25-plan.md](docs/planning/milestone-25-plan.md).

- **Spawn overrides.** HP%, shield, and armor SpinBoxes apply to each newly spawned unit immediately after placement. A status injection sub-panel (OptionButton + stacks SpinBox + [Apply]) writes a `StatusInstance` into the last-spawned unit's `active_statuses`.
- **Terrain controls.** New TERRAIN section: seed LineEdit + [Regenerate] → `TerrainManager.generate(seed)`. All live units are re-snapped to the new surface via `get_surface_row(col)`.
- **Inspector click.** When the overlay is open and no spawn is pending, left-clicking any unit calls `hud.set_inspected_unit(unit)`, opening the existing HUD inspector panel for that unit.
- **Force N rounds.** SpinBox + [Advance Rounds] → loops `debug_advance_round()` N times. New `CombatManager.debug_advance_round()` ticks tile and unit statuses and increments `round_index`.

---

## 2026-06-20 — Milestone 24: Debug sandbox overlay

Toggleable debug overlay for rapid content authoring and synergy testing during development. Full design in [docs/planning/milestone-24-plan.md](docs/planning/milestone-24-plan.md).

- **`debug/sandbox_overlay.gd`** — `CanvasLayer` added to `combat_scene` in `_ready()`, gated by `Features.sandbox_enabled`. Toggle with backtick (`` ` ``). Right-side scrollable panel, ~210px wide.
- **Spawn panel.** Lists all `UnitDefinition` resources from `data/units/` (loaded at setup via `DirAccess`). Select a unit, click [As Player] or [As Enemy] to arm spawn, then click terrain to place. Uses `canvas_transform.affine_inverse()` for world-coordinate conversion from a CanvasLayer.
- **Card injection.** Lists all `CardDefinition` from `data/cards/`. [→ Hand] calls `combat.debug_inject_card_to_hand()`, [→ Deck] calls `debug_inject_card_to_deck()`.
- **Artifact injection.** Lists all `ArtifactDef` from `data/artifacts/resources/`. [Activate] calls `combat.debug_inject_artifact()`.
- **Cheats.** [Refill AP] → `debug_refill_ap()`, [End Player Turn] → `end_player_turn()`, [Force Wave] → `debug_force_next_wave()`.
- **Isolation toggles.** [Player Invulnerable] sets `debug_invulnerable` on all player units (guard in `Unit.take_damage()`). [Enemies Passive] sets `CombatManager.debug_enemies_passive` (skip in `_run_enemy_turn()`). Toggle buttons turn green when active.
- **Production entry points only.** All actions route through public `debug_*` methods on `CombatManager` — no direct private-field access from the overlay.
- No smoke test; verified manually.

---

## 2026-06-20 — Milestone 23: Unit capacity & skip rewards

Two run-management features. Full design in [docs/planning/milestone-23-plan.md](docs/planning/milestone-23-plan.md).

- **Unit capacity.** `UnitDefinition.capacity_cost: int = 2` (all current units). `RunState.MAX_SQUAD_CAPACITY = 8` constant → max 4 units in squad. The UNIT reward is suppressed entirely (returns `[]` from `_pick_reward_options`) when capacity is full, so the offer never appears. No bake needed — GDScript defaults are picked up automatically by existing `.tres` files.
- **Capacity display.** Map screen shows "Squad Capacity: X / 8" in purple below the title, computed from `capacity_cost` sum across live squad. Unit reward cards show a "Capacity: 2" stat line.
- **Skip rewards.** `RewardScreen` gains `signal reward_skipped()`. A "— Skip —" label (clickable, dim colour) appears below the option cards for all reward categories (UNIT, CARD, ARTIFACT). `RunController._on_reward_skipped()` calls `_show_next_reward()` with no reward applied.

---

## 2026-06-20 — Milestone 22: Essence system

Per-unit upgrades that occupy upgrade slots; structurally parallel to the artifact system.
Full design in [docs/planning/milestone-22-plan.md](docs/planning/milestone-22-plan.md).

- **`EssenceDef / EssenceContext / EssenceSystem`** — same Def/Context/System triple as artifacts.
  `EssenceContext.unit` holds the owning unit; the combat manager swaps it before each hook call.
  `EssenceSystem` is a static dispatcher gated by `Features.essences_enabled`.
- **`RunUnitState.equipped_essences: Array[String]`** — serialized paths, loaded onto `Unit.essences`
  at combat start via `_init_essences()`. Slot cost validation deferred to the equip UI.
- **Essence 1 — Armor Primer** (`data/essences/essence_armor_primer.gd`): `on_combat_start` adds 10
  armor to the owning unit. Stacks with `UnitDefinition.base_armor`.
- **Essence 2 — Double Shot** (`data/essences/essence_double_shot.gd`): `on_unit_fired` calls
  `CombatManager.schedule_refire()` — a new async method that waits 2 seconds and fires a second
  projectile at the same angle/speed. No AP cost; essence hooks suppressed on refire to prevent loops.
- **Hooks wired** in: `_fire_active()` (unit fired), `_begin_round()`, `end_player_turn()`,
  `_on_unit_died()`.
- **Test fixture:** `run.gd` pre-equips Armor Primer on Cluster, Double Shot on Bypass. Essences are
  not unit-specific by design — wiring moves to reward/event flow in a later milestone.

---

## 2026-06-19 — Milestone 21: Shards currency & upgrade slots

Two run-state primitives scaffolding the currency/retire/fusion system (design doc
[artillery-space-currency-retire-fusion.md](docs/design/artillery-space-currency-retire-fusion.md)).
Full design in [docs/planning/milestone-21-plan.md](docs/planning/milestone-21-plan.md).

- **Shards.** `RunState.resources["shards"]` is the single fungible run currency. Starts at **10**
  per `Run.start_default_run()`. Sources (terrain destruction, kills, stage clear) and sinks (shop,
  repair, fusion, deck thinning, rerolls) are deferred milestones.
- **Upgrade slots.** `RunUnitState.upgrade_slots: int = 2` — the bounded shared pool for permanent
  upgrades and fused essences per design doc §5. No upgrade mechanics yet; field serializes through
  `to_dict`/`from_dict` with a backwards-compatible default of 2.

---

## 2026-06-18 — Milestone 20: Armor mitigation layer

Borderlands-style armor pool above shield, with element × mitigation-layer multipliers.
Full matrix in [artillery-space-mechanics-compatibility.md](artillery-space-mechanics-compatibility.md) §1.

- **`Unit.armor`** — flat per-combat absorb pool; pipeline is shield → armor → HP.
- **`ElementDef`** — `vs_armor_mult`, `vs_shield_mult`, `vs_hp_mult` applied per layer in
  `take_damage()`.
- **`UnitDefinition.base_armor`** — Cluster spawns with 4 armor each combat.
- **`Armor Up` card** — +5 armor, 2 AP, 3 copies in default deck and card pool.
- **`Features.armor_enabled`** kill switch.

---

## 2026-06-18 — Milestone 19: Branching map (diamond DAG)

Forward-only run map with explicit `next_nodes` edges and click-to-select UI. Full design in
[milestone-19-plan.md](milestone-19-plan.md).

- **`MapNode`:** `next_nodes: Array[int]`, `layer: int` (UI layout hint); serialized in `to_dict`.
- **`MapState`:** `next_choice_indices()`, `can_select()`, `select_next()`, `is_terminal()`,
  `build_diamond()` (9-node 1-2-3-2-1 prototype); `build_linear()` kept for regression.
- **`MapScreen`:** `MapGraphView` draws diamond layers, edges, and node states; click legal
  forward nodes to enter combat.
- **`Run.start_default_run()`** uses `build_diamond(_DEFAULT_MAP)`; post-combat returns to map
  for branching picks instead of auto-advancing.

---

## 2026-06-18 — Milestone 18: Faction identifiers on content

Engine-first faction tagging (run-design §5). Full design in [milestone-18-plan.md](milestone-18-plan.md).

- **`Faction`** (`data/factions/faction.gd`): ids `neutral`, `army` (Seekers), `cell` (Awakened),
  `bio` (Shamans); `display_name()` for UI.
- **`faction: String`** on `UnitDefinition`, `CardDefinition`, `ArtifactDef`.
- **Bake:** all units → `army`; shield / overdrive / direct strike cards → `neutral`; mine / calm
  winds → `army`; squad regen, lifesteal, free first card → `neutral` artifacts; rest → `army`.
- **`RunState.run_meta.faction`** seeded to `army` in `start_default_run()` (filtering deferred).

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
