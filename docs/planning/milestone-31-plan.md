# M31 — Animation Sequencer

**Date:** 2026-06-22
**Status:** Complete — all smoke checks pass

## Problem

The game had no animation layer. Damage, death, projectile impact, and deployable events all resolved and rendered instantly. Multiple units dying silently, explosions leaving no trace, and status effects being invisible made combat unreadable. M31 introduces the central `AnimationSequencer` autoload and wires all placeholder animations through it.

## Design spec

`docs/design/artillery-space-animation-sequencer.md` (v0.2) — updated during this milestone.

---

## Locked decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Central autoload sequencer, not distributed per-node | Single place to control batch ordering; nodes stay dumb |
| 2 | Batch-parallel queue: entries in same batch play in parallel; batches sequential | Hits play together, then deaths play together — matches game logic wave structure |
| 3 | Completion via `signal anim_done` + `CONNECT_ONE_SHOT` | Nodes never reference the sequencer; zero coupling |
| 4 | Auto-batching by `event_type`: `"impact"` and `"death"` call `next_batch()` before enqueue | Separates hit wave → impact wave → death wave automatically |
| 5 | `fast_forward = true` auto-enabled when `ARTILLERY_SMOKE=1` | All tweens take the `duration == 0.0` synchronous branch; smoke test passes instantly |
| 6 | `WorldFXLayer` node handles world FX (projectile impact burst) | Sequencer needs a valid `target` node with `anim_done`; world effects have no natural owner |
| 7 | Dead units stay in scene tree; `death_fade` fades `modulate.a` to 0; no `queue_free` | Visual continuity during animation; avoids use-after-free on the entry target |
| 8 | Deployable `queue_free` moved to `on_complete` on `deploy_destroyed` entry | Ensures node isn't freed mid-animation; CombatManager still owns the array cleanup |
| 9 | `animations_enabled` feature flag | Can disable globally for testing or performance |
| 10 | `collapse_fall` stub only (no voxel translation) | Visual design for falling terrain columns is TBD; wired as immediate no-op pass-through |

---

## Architecture

### `AnimationEntry` — `animation/animation_entry.gd`

```gdscript
class_name AnimationEntry
extends RefCounted

var anim_id       : String         = ""
var target        : Node           = null
var params        : Dictionary     = {}
var duration      : float          = 0.0
var interruptible : bool           = true
var on_complete   : Callable

var event_type    : String         = ""
var wave          : int            = 0
var tags          : Array[String]  = []
```

`tags` must be populated with `.append()` not direct assignment (GDScript typed array limitation).

### `AnimationSequencer` — autoload

Queue structure:
- `_current_batch` — open, being filled by `enqueue()`
- `_batches` — sealed batches awaiting play
- `_active_batch` — batch currently playing
- `_active_count` — entries in active batch not yet done

Key invariant: `_on_entry_done` calls `_flush_and_play()` (not `_play_next_batch()`). This picks up any entries accumulated in `_current_batch` during the playing batch — critical for the `impact → death` ordering when signals fire synchronously during resolution.

### `WorldFXLayer` — `animation/world_fx_layer.gd`

Inner class `Burst` holds `pos`, `col`, `radius`, `alpha`. `play_anim("projectile_impact", ...)` creates a burst and tweens radius 4→20 and alpha 1→0 via separate tweens, calling `anim_done.emit()` via `tween_callback`. `_draw()` renders each burst as `draw_circle`.

### Animation interface on Unit and Deployable

Both implement:
```gdscript
signal anim_done
func play_anim(anim_id: String, params: Dictionary, duration: float) -> void
func snap_anim(anim_id: String) -> void
```

When `duration == 0.0` (fast_forward): apply end-state immediately and emit `anim_done` synchronously.

---

## EventBus wiring

| Signal | Entry | event_type | Notes |
|---|---|---|---|
| `unit_hit_taken` | `hit_flash` | `"hit"` | tag: `"player"` or `"enemy"` |
| `unit_died` | `death_fade` | `"death"` | `next_batch()` first; interruptible=false |
| `status_applied` | `status_pulse` | `"status"` | |
| `projectile_impact` | `projectile_impact` | `"impact"` | `next_batch()` first; target=world_fx |
| `tile_destroyed` | — | — | no-op stub |
| `tile_status_applied` | — | — | no-op stub |
| `deployable_placed` | `deploy_appear` | `"deploy"` | new signal added to EventBus |
| `deployable_died` | `deploy_destroyed` | `"deploy"` | `next_batch()` first; on_complete=d.queue_free |

---

## Files changed

| File | Change |
|---|---|
| `animation/animation_entry.gd` | NEW |
| `animation/animation_sequencer.gd` | NEW — registered as autoload |
| `animation/world_fx_layer.gd` | NEW |
| `project.godot` | Added AnimationSequencer autoload |
| `autoloads/features.gd` | Added `animations_enabled` flag |
| `autoloads/event_bus.gd` | Added `deployable_placed` signal |
| `units/unit.gd` | Added anim interface + `_dying` flag |
| `world/deployable.gd` | Added anim interface |
| `systems/combat_manager.gd` | Emit `deployable_placed`; removed `d.queue_free()` from `_on_deployable_died` |
| `world/combat_scene.tscn` | Added WorldFXLayer child node |
| `world/combat_scene.gd` | Wire `AnimationSequencer.world_fx`; added `_m31_smoke()` |

---

## Smoke test results

```
[smoke] -- M31 animation sequencer --
  fast_forward=true (expect true)      ✓
  world_fx valid=true (expect true)    ✓
  sequencer idle=true (expect true)    ✓
  foe took dmg=true (expect true)      ✓
```

All M1–M30 prior checks continue to pass. Pre-existing M6/M19 errors are unrelated to M31.

---

## Known issues / deferred

- `collapse_fall` — terrain column collapse has no visual; stub emits `anim_done` immediately
- Tag-based orchestration rules engine — `tags` field assigned and populated, but no rule-matching logic yet. Tags are available for future orchestration.
- No sound hooks — audio timing designed to plug into `on_complete` but no audio system yet
- `_dying` flag on Unit — used to prevent click/hover interactions on dying units, but guarding is not implemented in M31. Add guard in Unit input handling when needed.
