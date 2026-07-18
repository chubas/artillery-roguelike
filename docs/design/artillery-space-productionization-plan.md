# Artillery Space — Phase 2: Productionization Plan

**Design & Technical Roadmap · v0.1**

> Phase 1 (M1–M45) built the complete mechanical prototype: terrain, combat, run loop, cards,
> artifacts, economy, deterministic targeting. **Phase 2 freezes features** and productionizes:
> placeholder art, effects, audio, and game-feel — wired through *skinnable seams* so real assets
> can replace placeholders later without touching gameplay code. The exit criterion is a playable,
> polished-feeling **Act 1 boss stage** we can test different squads/builds against.

---

## 1. Where we are (the honest inventory)

Everything visible today is **code-drawn** (`_draw()` calls: rects, circles, lines, fallback-font
text). There are **zero** textures, particles, shaders, lights, or audio files in the project.
This is actually the ideal starting point: there is no legacy art pipeline to migrate — only
clean, well-located draw sites to put seams into.

### Current visual surface (every skinning seam)

| File | What it draws today | Skinning target |
|---|---|---|
| `rendering/chunk.gd` | Per-voxel colored rects (SOLID/RUBBLE/LIQUID/LAVA/MINERAL), variant shading, crack overlays, HP labels | Terrain tile atlas (§4.2) |
| `units/unit.gd` | Body rect + outline, selection border, HP bar, stat icons (circles), effect badges | Unit sprites + kept bars (§4.3) |
| `world/deployable.gd`, `world/shield_generator.gd` | Colored rects + aura circle | Deployable sprites (§4.3) |
| `world/ore.gd` | Pink circle + value label | Ore sprite/animation (§4.3) |
| `projectile/projectile.gd`, `spiral_satellite.gd`, `walker_crawler.gd` | Small circles/shapes in flight | Projectile sprites + trails (§4.4) |
| `projectile/explosion_fx.gd` | Expanding fading circle | GPUParticles2D explosion (§4.4) |
| `animation/world_fx_layer.gd` | Impact bursts (tweened circles) | Particle library dispatch (§4.4) |
| `ui/hud.gd` (raw `_draw`, by design) | Panels, cards, inspector, bars, buttons | UI palette now, Theme later (§4.6) |
| `ui/targeting_overlay.gd` | Aim arc, spawn zones, drop indicator, reinforcement warnings | Styled lines/markers (§4.6) |
| `ui/map_screen.gd`, `reward_screen.gd`, `unit_portrait.gd`, `pattern_glyph.gd` | Map nodes, reward cards, portraits | UI palette + icons (§4.6) |
| `systems/combat_manager.gd` | (drives `targeting_overlay` state) | — |

Non-visual gaps: **no audio at all** (no buses, players, or files), **no particles**, **no
lighting** (no `CanvasModulate`/`PointLight2D`/`WorldEnvironment`), **no shaders**, no screen
shake or hitstop. `AnimationSequencer` (M31) exists and is the right spine to hang juice on.

---

## 2. Architecture principle: skinnable seams, not rewrites

The single most important decision. Every visual/audio element is resolved through a **registry
lookup keyed by a stable id**, with a **code-drawn fallback** when no asset is registered:

```
gameplay code ──(id)──▶ VisualRegistry / FXManager / AudioManager ──▶ asset
                                        │
                                        └─ not registered? → today's code-drawn placeholder
```

Rules that make the system "easily skinnable":

1. **Definitions reference ids, not paths.** `UnitDefinition` gets `sprite_id: String`, shots get
   `fx_id`/`sfx_id`, tile types get atlas ids. A *skin* is then just a different registry mapping.
2. **One theme resource owns the mapping.** A `VisualTheme` resource (baked like everything else)
   maps `id → texture/region/frames/color/particle scene/audio stream`. Swapping themes = swapping
   one resource. This is the seam where lighting/shading variants also land later.
3. **Fallback is mandatory.** Every lookup that misses returns null and the caller keeps its
   current `_draw` placeholder. We can skin one entity at a time; the game never breaks because
   an asset is missing.
4. **Feature flags per layer** (house rule): `Features.skins_enabled`, `fx_enabled` (particles),
   `audio_enabled`, `juice_enabled`, `lighting_enabled`. Ship each layer dark, flip it on.
5. **EventBus stays the trigger bus.** FX and audio subscribe to existing signals
   (`aoe_resolved`, `mineral_destroyed`, `unit_shield_changed`, `tile_status_applied`,
   `ore_collected`, `deployable_placed`, `wind_changed`, turn/round signals…). Gameplay code does
   not call `play_sound()`; it emits what happened, and the presentation layer reacts. Most of the
   wiring we need already exists as signals.

---

## 3. Asset pipeline & conventions (build first, it's cheap)

- **Directory layout** (new):
  ```
  assets/
    sprites/units/        # one sheet per unit id (or shared atlas)
    sprites/terrain/      # tile atlas(es)
    sprites/projectiles/
    sprites/fx/           # flipbook effects if not particle-based
    sprites/ui/           # icons: cards, statuses, keywords, currency, intent
    particles/            # .tscn GPUParticles2D presets
    audio/sfx/            # .wav (short) — one file per sound id
    audio/music/          # .ogg loops
    shaders/              # .gdshader (hit flash, dissolve, water)
    themes/               # VisualTheme .tres + Godot Theme .tres
  ```
- **Grid & scale:** the world is authored on `VOXEL_SIZE = 16` px. Pixel-art at **16 px/voxel is
  the native choice** (a 2×3-voxel unit = 32×48 px sprite). Camera zoom already ranges 0.5–3.0, so
  set project-default texture filter to **Nearest** for the pixel look (or author at 32 px/voxel
  "2× HD" and filter Linear — decide once, in §8, before generating art; mixing looks worse than
  either choice).
- **Atlases:** prefer one PNG per domain (terrain, units, ui-icons) with `AtlasTexture` regions —
  fewer draw calls, better batching, and `chunk.gd` can keep its single-canvas-item-per-chunk
  design using `draw_texture_rect_region` (no scene-tree changes). ([sprite/atlas best-practice
  refs](https://ilovesprites.com/blog/godot-sprite-nuances-best-practices),
  [AtlasTexture guide](https://gamedevacademy.org/atlastexture-in-godot-complete-guide/))
- **Import presets:** commit `.import` files; lossless PNG, no mipmaps (2D), filter per §8 choice.
- **Naming = ids:** `unit_vanguard.png`, `sfx_explosion_small.wav` — the file stem IS the registry
  id, so the registry can auto-scan directories exactly like `MapLibrary` does for maps.

---

## 4. The systems to build

### 4.1 `VisualRegistry` (autoload) + `VisualTheme` (resource)
- `texture(id) -> Texture2D`, `frames(id) -> SpriteFrames`, `region(id) -> AtlasTexture`,
  `color(id) -> Color`, `icon(id) -> Texture2D`; all null-safe (fallback contract §2.3).
- `VisualTheme` is baked data (consistent with our `.tres` architecture); default theme =
  "placeholder". Later themes ("polish", "high-contrast") are content, not code.

### 4.2 Terrain skin
- Replace flat color rects in `chunk.gd` with atlas regions per `TileType` + `variant` (we already
  store `variant 0–3` per tile — it's been waiting for art since M1). Add **edge awareness** cheaply:
  a tile whose up-neighbor is void draws a "grass/surface" cap region; that one rule gives 80% of
  the terrain readability without full autotiling. Cracks: 2–3 overlay regions by hp fraction
  (replacing the drawn crack lines); keep HP labels behind a debug flag.
- LIQUID/LAVA get a simple scrolling `canvas_item` shader (first shader in the repo, ~10 lines).
- Background: 2–3 parallax layers (`ParallaxBackground`) per map biome id — hand-authored maps
  (M44) get a `biome:` metadata key later; sky gradient placeholder first.

### 4.3 Entity skins (units, deployables, ore)
- `UnitDefinition.sprite_id` → `SpriteFrames` with 4 states: **idle, fire, hit, dead**. Render via
  a child `AnimatedSprite2D` added in `Unit._ready()` when the registry resolves; `_draw` keeps
  bars/badges/selection (those are UI, not skin) and skips the body rect when a sprite exists.
- `AnimationSequencer` (M31) already routes `play_anim` — map its anim ids to sprite states
  (fire → "fire" flash frame, death_fade → "dead" + dissolve shader later).
- Barrel: a separate small `barrel` sprite rotated to `aim_angle_deg` (we already have
  `barrel_offset`); this is the piece that makes artillery units read as artillery.
- Deployables/Ore: single-sprite or 2-frame idle animations, same registry path.

### 4.4 `FXManager` (autoload) — particles & impact effects
- API: `FXManager.spawn(fx_id, world_pos, params={})`. Backed by a library of **GPUParticles2D
  preset scenes** (`assets/particles/*.tscn`), pooled, `one_shot = true`, self-freeing.
- First library (maps to existing events):
  `explosion_small/medium`, `dirt_debris` (terrain destroyed — colored by tile type),
  `fire_ignite/burning_loop`, `electric_arc/chain`, `mineral_break` + `ore_sparkle`,
  `collapse_dust`, `shield_hit/break`, `heal_pulse`, `muzzle_flash`, `teleport_flash`,
  `water/goo_splash`, `taunt_marker`.
- Wire via EventBus subscriptions (§2.5); `ExplosionFX`/`WorldFXLayer` become fallbacks when
  `fx_enabled` is off or an fx_id is missing. `ShotDefinition.fx_impact_id` (data) overrides the
  default explosion per shot family.

### 4.5 `AudioManager` (autoload) — buses, pooling, events
- Bus layout: `Master → Music / SFX / UI` (created in project settings; volume via
  `AudioServer.set_bus_volume_db`). ([Godot audio buses](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html))
- Pooled `AudioStreamPlayer`(UI/global) + `AudioStreamPlayer2D`(world, positional) — 8–16 players,
  round-robin, so overlapping shots never cut each other. ([audio manager recipe](https://kidscancode.org/godot_recipes/4.x/audio/audio_manager/index.html))
- `AudioManager.play(sfx_id, world_pos = null)`; per-id `pitch_scale` jitter (±5–10%) so repeated
  explosions don't sound machine-gunned. Registry auto-scans `assets/audio/sfx/`.
- First sound list (~20 ids): fire/launch, explosion ×2 sizes, dig hit, tile break, collapse
  rumble, unit hit, unit death, shield absorb/break, card draw/play, ore pickup, currency tick,
  move step, climb, UI hover/click/error, turn-start sting, victory/defeat stings, 1 music loop
  (map) + 1 (combat).

### 4.6 UI palette now, Godot Theme later
- The raw-`_draw` HUD is a deliberate house choice — don't migrate it yet. Instead extract a
  **`UIPalette`** (constants/theme section in `VisualTheme`): every hard-coded `Color(...)` in
  `ui/*.gd` moves to named entries (`panel_bg`, `accent_player`, `accent_enemy`, `hp_green`,
  `currency_gold`…). That single step makes the whole UI reskinnable and consistent.
- Replace placeholder circles (stat icons, effect badges, keyword chips, intent markers) with
  16/24 px **icon textures** via `VisualRegistry.icon(id)` — statuses, elements, currencies, and
  the M45 targeting-intent icons all become art-driven.
- Full `Control`/`Theme` migration (real buttons, tooltips, focus) is a *Phase 3* line item; note
  it, don't do it.

### 4.7 Juice layer (game feel)
Centralize in the existing `AnimationSequencer` + a tiny `Juice` autoload:
- **Screen shake:** trauma-based (add trauma on events, shake ∝ trauma², decay per frame; noise-
  driven offset — the standard GDC approach). Hooks: explosion size, collapse mass, unit death.
- **Hitstop:** 40–80 ms `Engine.time_scale` dip (or sequencer pause) on unit kills and big blasts.
- **Hit flash:** white-flash `canvas_item` shader on damaged units (1 shared shader, per-unit
  material instance), replacing nothing (new).
- **Tweens:** squash/stretch on unit land/fire, HP-bar drain lag (white "recent damage" segment),
  card punch-in on draw, floating damage numbers (pooled labels).
- All behind `Features.juice_enabled`; sequencer's `fast_forward` (smoke mode) must skip all of it.
  (Reference: [Juice it or Lose it](https://gamejuice.co.uk/resources/juice-it-or-lose-it),
  [juiciness checklist](https://gist.github.com/fguillen/e4d4b066621910d8d77174a96ea2ca99))

### 4.8 Lighting & shaders (planned seam, implemented later)
Where it will land, so nothing blocks it:
- `CanvasModulate` per map (`ambient:` map-metadata key) darkens the scene; **`PointLight2D`**
  attached to: explosions (via FXManager), burning tiles, lava, ore sparkle, muzzle flashes.
  ([Godot 2D lights & shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html))
- `LightOccluder2D` per terrain chunk (generated from solid edges — chunk.gd already knows dirty
  regions) for real shadows in caves. `WorldEnvironment` glow for lava/electric/explosions.
- Normal maps for terrain/units are a pure asset upgrade later (`CanvasTexture` pairs diffuse +
  normal; no code change if the registry hands back `CanvasTexture` instead of `Texture2D`).
  ([normal-map lighting](https://www.gdquest.com/tutorial/godot/2d/lighting-with-normal-maps/))
- Shaders to plan for: hit-flash (§4.7), death dissolve, liquid scroll (§4.2), heat shimmer over
  lava, screen-space vignette on low squad HP.

---

## 5. Data schema additions (small, all bake-side)

| Definition | New fields |
|---|---|
| `UnitDefinition` | `sprite_id`, `portrait_id`, `sfx_fire_id`, `sfx_death_id` |
| `ShotDefinition` | `projectile_sprite_id`, `trail_fx_id`, `fx_impact_id`, `sfx_fire_id`, `sfx_impact_id` |
| `StatusEffectDef` / `TileStatusDef` | `icon_id`, `fx_loop_id` |
| `CardDefinition` / `ArtifactDef` / `KeywordDef` | `icon_id` |
| `CustomMap` metadata | `biome:`, `ambient:` (color), `music:` (id) |
| NEW `VisualTheme` | the id→asset mapping tables (baked) |

All default to `""` → fallback path; content fills in as assets appear.

---

## 6. Phased roadmap

Each phase is one milestone-sized chunk, independently shippable, gameplay untouched.

| Phase | Deliverable | Exit test |
|---|---|---|
| **P0 — Seams** | Directories, import presets, `VisualRegistry`+`VisualTheme`, `FXManager`, `AudioManager`, `Juice` skeletons, feature flags, schema fields. Zero assets. | Game looks/plays identical; registries resolve nothing and fall back. Smoke passes. |
| **P1 — Terrain + entity skins** | Tile atlas (placeholder), surface caps, crack overlays; unit/deployable/ore/projectile sprites with idle/fire/hit/dead. | A full combat reads as "a game with art" in screenshots. |
| **P2 — FX pass** | Particle library (§4.4) wired to EventBus; per-shot impact fx. | Explosions, fire, electric, collapse, ore, shields all particle-driven; flag-off reverts cleanly. |
| **P3 — Audio pass** | Buses, pooled manager, ~20 SFX + 2 music loops. | Full combat with sound; volume sliders work (debug menu). |
| **P4 — Juice pass** | Screen shake, hitstop, hit flash, damage numbers, tween polish. | Firing feels weighty; smoke mode unaffected. |
| **P5 — UI palette + icons** | `UIPalette` extraction, icon set for statuses/elements/cards/intent. | No raw `Color(...)` literals in `ui/*.gd`; icons everywhere circles were. |
| **P6 — Act 1 Boss Stage** | See §7. | The Phase-2 exit criterion. |
| **P7+ (Phase 3)** | Lighting/occluders/normal maps, shaders, full Theme migration, menus, settings, export presets. | — |

P1–P5 order is swappable; P0 is the prerequisite for everything. Suggested rhythm: P0 next
milestone, then P1, then P6 can actually begin in parallel with P2–P5 since the boss is mostly
*content* (map + stage descriptor + enemy defs) on systems that already exist.

## 7. The Act 1 Boss Stage (Phase-2 exit)

Per the stage-design doc (§6.1, composite bosses) — lowest-risk, reuses existing machinery:

- **Thesis:** "The fortress core is protected; the battlefield degrades as you crack it."
- **Content, not new systems:** a hand-authored boss map (M44 format — bunker structure drawn in
  ASCII with `0` skeleton + high-hp shell rows), a `StageDescriptor` with objective = destroy-the-
  core (M13 objectives), escalating `reinforcements` waves, and 2–3 new enemy defs that exercise
  M45 targeting rules (a FIXED_LANE "sniper", a WEAKEST "finisher", a bypass-shot "driller").
  The "core" is a high-HP stationary enemy unit inside the shell (no new entity type needed).
- **Phase feel via waves + hazards**, not code: wave escalation on rounds, optional lava/rising
  hazard later. One new mechanic *allowed* if testing demands it (e.g. shell-regeneration enemy).
- **Measurable:** playable start-to-win/loss with 3 different squad builds; we record rounds-to-
  kill, damage taken, and which terrain relationships each build used — that's the balance loop
  this whole phase exists to enable.

## 8. Sizes & resolutions (defaults to confirm before art starts)

To be locked when you ask for sizes; recommended starting point:
- **Pixel-art, 16 px/voxel native**, Nearest filtering, `viewport` stretch mode.
- Base window 1280×720 (or 1920×1080 with 2× UI scale); world zoom already handles framing.
- Sprites: unit 32×48 (2×3 voxels) + 16×16 barrel; ore 16×16; projectiles 8–16 px; tile atlas
  16×16 cells (4 variants + surface cap + 3 crack overlays per type); UI icons 16 and 24 px;
  portraits 64×64; card art 96×64.

## 9. Placeholder asset shopping list

| Need | Source (license) |
|---|---|
| Terrain tiles, UI, icons, particles-as-sprites | [Kenney.nl](https://kenney.nl) — 40k+ assets, all CC0, consistent style; start with *Pixel Platformer*, *Particle Pack*, *Game Icons*, *UI Pack* ([overview](https://gamineai.com/blog/20-best-free-game-assets-every-developer-should-know-about)) |
| Unit/character sprites, biome tilesets | [itch.io CC0 assets](https://itch.io/game-assets/assets-cc0) (filter Free + CC0), [OpenGameArt](https://opengameart.org) (check per-asset license) |
| Sound effects (placeholder-perfect) | Generate with [jsfxr](https://sfxr.me/) / Bfxr — retro synth SFX in seconds, public domain; curated real sounds from [Freesound](https://freesound.org) (filter CC0) |
| Music loops | Kenney music packs (CC0), OpenGameArt CC0 loops |
| Fonts | Kenney fonts (CC0) or Google Fonts (OFL) to replace `ThemeDB.fallback_font` |
| Shaders to adapt | [godotshaders.com](https://godotshaders.com) (check per-shader license; most CC0/MIT) |

Attribution hygiene: keep `assets/CREDITS.md` from day one, even for CC0.

## 10. Sources

- [Godot: 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) · [Audio buses](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html)
- [GDQuest: lighting with 2D normal maps](https://www.gdquest.com/tutorial/godot/2d/lighting-with-normal-maps/)
- [KidsCanCode: audio manager recipe](https://kidscancode.org/godot_recipes/4.x/audio/audio_manager/index.html)
- [Sprite/atlas pipeline best practices](https://ilovesprites.com/blog/godot-sprite-nuances-best-practices) · [AtlasTexture guide](https://gamedevacademy.org/atlastexture-in-godot-complete-guide/)
- [Juice it or Lose it (talk + resources)](https://gamejuice.co.uk/resources/juice-it-or-lose-it) · [Juiciness checklist](https://gist.github.com/fguillen/e4d4b066621910d8d77174a96ea2ca99) · [Camera shake writeup](https://gt3000.medium.com/juice-it-adding-camera-shake-to-your-game-e63e1a16f0a6)
- Asset sources: [Kenney](https://kenney.nl) · [itch.io CC0](https://itch.io/game-assets/assets-cc0) · [OpenGameArt](https://opengameart.org) · [Freesound](https://freesound.org) · [jsfxr](https://sfxr.me/)
