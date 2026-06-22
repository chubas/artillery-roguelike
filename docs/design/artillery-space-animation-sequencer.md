# Artillery Space — Animation Sequencer
**Technical Specification · v0.2**

> Defines the central animation sequencer that sits between logical event resolution and screen output. All placeholder animations should be built through this layer — not as cosmetic polish, but as the mechanism that governs timing, readability, and the tick/real-time boundary. The sequencer must be correct before any content animation is added.

---

## 1. The One Rule This Spec Enforces

**Logic resolves instantly. Animation plays in real time. The sequencer is the boundary between them.**

Logical events (damage, death, status application, terrain destruction, deployment) resolve synchronously and completely before any animation begins. The sequencer then plays the resulting animations in a controlled batch queue, gating when the next wave of animations may begin. Nothing that affects game state happens inside an animation callback — animations are read-only presentations of state that has already fully resolved.

The test: if you pause every animation and inspect logical state only, nothing should be ambiguous or mid-resolution. If it is, a decision is leaking into presentation time and must move back to logic.

---

## 2. Architecture: Central Sequencer, Not Distributed

The sequencer is a **single autoload** (`AnimationSequencer`) that owns a batch queue and dispatches animations to their target nodes. Target nodes (units, deployables, tiles, WorldFXLayer) implement an animation interface but do not own their own scheduling.

**Why not distributed:** the death-cascade queue and EventBus already centralize logical event sequencing. A distributed animation model would create a second implicit ordering governed by individual nodes, producing timing bugs that are hard to reproduce. A central sequencer keeps the seam visible, testable, and auditable.

### Core data type

```gdscript
class_name AnimationEntry
extends RefCounted

var anim_id       : String          # e.g. "hit_flash", "death_fade"
var target        : Node            # unit, deployable, tile, or WorldFXLayer — never null
var params        : Dictionary      # element, damage, color, world position, etc.
var duration      : float           # seconds; 0 in fast-forward mode
var interruptible : bool = true     # can this be snapped to end-state early?
var on_complete   : Callable        # optional; called when entry finishes or is interrupted

# -- Tagging fields (used by sequencer rules and future orchestrators) --
var event_type : String       = ""  # canonical category: "impact", "hit", "death",
                                    #   "status", "deploy", "terrain", "chain"
var wave       : int          = 0   # cascade depth: 0 = direct action, 1 = first-order
                                    #   chain, 2 = second-order, etc.
var tags       : Array[String] = [] # free-form labels for edge-case rule matching
                                    #   e.g. ["player", "shield_generator", "aoe"]
```

**`event_type`** is the canonical category the sequencer uses to apply batching rules now and in the future. **`wave`** tracks cascade depth so effects from the same logical phase group into the same batch. **`tags`** are free-form and intentionally unstructured — they exist so future rules can match on them without changing the core entry schema.

Example populated entry:
```gdscript
var e        := AnimationEntry.new()
e.anim_id    = "death_fade"
e.target     = unit_node
e.params     = {"faction_color": Color.RED}
e.duration   = 0.5
e.interruptible = false
e.on_complete   = unit_node.queue_free
e.event_type = "death"
e.wave       = 0
e.tags       = ["player", "shield_generator"]
```

---

## 3. Batch-Parallel Queue

**Logic resolves in waves. Animations play in batches. One batch per wave.**

The queue is a list of *batches*. Each batch is an array of `AnimationEntry` objects that play in parallel. Batches play sequentially — the next batch starts only after every entry in the current batch has completed or been interrupted to its end-state.

```
_batches : Array[Array[AnimationEntry]]

Wave 0 → Batch 0: [projectile_impact]
Wave 1 → Batch 1: [hit_flash(A), hit_flash(B)]        ← parallel; same blast
Wave 2 → Batch 2: [death_fade(A), death_fade(B)]      ← parallel; same wave of deaths
Wave 3 → Batch 3: [hit_flash(D)]                      ← D hit by A's on-death trigger
Wave 4 → Batch 4: [death_fade(D)]
```

This structure solves two competing concerns:
- **Readability** — the player sees cause and effect in order: blast → units flash → units die → chain fires.
- **Endgame speed** — eight simultaneous deaths play in one 0.5s batch, not 4 seconds of sequential fades.

### Batch lifetime

- **`enqueue(entry)`** — appends to the open batch. If nothing is playing, flushes immediately.
- **`next_batch()`** — seals the open batch (appends it to the queue) and opens a new one. Called by `CombatManager` at logical phase boundaries (between each wave of the death-cascade processing loop).
- **Batch advance** — when all entries in the active batch emit `anim_done`, the sequencer starts the next batch.

### Interruptible vs. committed

- `interruptible = true` — entry can be snapped to its end-state if `interrupt_active_batch()` is called. Example: `hit_flash` can be cut short if the unit immediately starts dying.
- `interruptible = false` — plays fully regardless. Example: `death_fade` completes before the node is freed.

`interrupt_active_batch()` snaps all interruptible entries in the currently playing batch to their end-states. This is called at the start of `_play_next_batch()` when the incoming batch contains an entry on the same target as an active interruptible entry. Not exposed broadly — reserved for internal sequencer logic.

### Fast-forward mode

`AnimationSequencer.fast_forward : bool` — when true, all durations are treated as `0` and `anim_done` fires immediately in the same frame. Enabled automatically when `ARTILLERY_SMOKE=1`. Expose as a runtime toggle for a future player speed-up option. With fast-forward active, the full batch queue and wave boundaries are still exercised; only wall-clock time is collapsed.

---

## 4. Sequencer Implementation

```gdscript
# autoloads/animation_sequencer.gd
extends Node

var fast_forward : bool = false

var _batches       : Array = []   # Array[Array[AnimationEntry]]
var _current_batch : Array = []   # open batch being filled by enqueue()
var _active_batch  : Array = []   # batch currently playing
var _active_count  : int  = 0     # entries in active batch not yet done

func enqueue(entry: AnimationEntry) -> void:
    _current_batch.append(entry)
    if _active_batch.is_empty() and _batches.is_empty():
        _flush_and_play()

func next_batch() -> void:
    if not _current_batch.is_empty():
        _batches.append(_current_batch.duplicate())
        _current_batch.clear()
    if _active_batch.is_empty():
        _play_next_batch()

func _flush_and_play() -> void:
    if not _current_batch.is_empty():
        _batches.append(_current_batch.duplicate())
        _current_batch.clear()
    _play_next_batch()

func _play_next_batch() -> void:
    if _batches.is_empty():
        return
    _active_batch = _batches.pop_front()
    _active_count = _active_batch.size()
    for entry : AnimationEntry in _active_batch:
        var dur := 0.0 if fast_forward else entry.duration
        entry.target.anim_done.connect(_on_entry_done.bind(entry), CONNECT_ONE_SHOT)
        entry.target.play_anim(entry.anim_id, entry.params, dur)

func _on_entry_done(entry: AnimationEntry) -> void:
    if entry.on_complete.is_valid():
        entry.on_complete.call()
    _active_count -= 1
    if _active_count == 0:
        _active_batch.clear()
        _play_next_batch()

func interrupt_active_batch() -> void:
    for entry : AnimationEntry in _active_batch:
        if entry.interruptible:
            entry.target.snap_anim(entry.anim_id)
```

Nodes never reference `AnimationSequencer` directly. The sequencer is the only side that knows about both the queue and the targets. Nodes emit `anim_done`; the sequencer listens via `CONNECT_ONE_SHOT`, which auto-disconnects after the first fire.

---

## 5. How Logical Events Connect to the Sequencer

Logical systems emit signals on EventBus; the sequencer subscribes and enqueues. No animation logic lives in CombatManager, AoEResolver, or any gameplay system.

```gdscript
# In AnimationSequencer._ready():
EventBus.unit_hit_taken.connect(_on_unit_hit)
EventBus.unit_died.connect(_on_unit_died)
EventBus.status_applied.connect(_on_status_applied)
EventBus.tile_destroyed.connect(_on_tile_destroyed)
EventBus.tile_status_applied.connect(_on_tile_status_applied)
EventBus.deployable_placed.connect(_on_deployable_placed)
EventBus.deployable_destroyed.connect(_on_deployable_destroyed)
EventBus.projectile_impact.connect(_on_projectile_impact)
```

Each handler constructs an `AnimationEntry`, populates `event_type`, `wave`, and relevant `tags`, then calls `enqueue()`.

### Wave assignment

`CombatManager` exposes `_anim_wave : int` (starts at 0, reset each action). It calls `AnimationSequencer.next_batch()` and increments `_anim_wave` between each processing step of the death-cascade queue:

```gdscript
# CombatManager (sketch):
func _process_death_cascade() -> void:
    while not _death_queue.is_empty():
        var unit := _death_queue.pop_front()
        _resolve_on_death(unit)
        AnimationSequencer.next_batch()
        _anim_wave += 1
```

EventBus signal handlers in `AnimationSequencer` read the current `_anim_wave` from `CombatManager` and stamp it on each entry. This stamps are informational — the batch boundaries produced by `next_batch()` are what actually sequences the animations. The `wave` field on the entry lets future orchestrators inspect or reorder without changing the queue structure.

---

## 6. World FX Target

`projectile_impact` and other position-based effects have no unit or tile as a natural target. Rather than allowing `null` targets (which would crash `target.play_anim()`), the sequencer routes these to a `WorldFXLayer` node — a `Node2D` in the combat scene that implements the full animation interface.

```gdscript
# WorldFXLayer: implements play_anim / snap_anim / anim_done
# play_anim("projectile_impact", {pos: Vector2, element_id: String}, dur)
#   → draws a burst at world position, emits anim_done when done
```

`AnimationSequencer` holds a `world_fx : WorldFXLayer` reference, set by the combat scene during setup. All position-based entries use `world_fx` as their target.

---

## 7. Animation Interface on Target Nodes

Every node that can be animated implements two methods and one signal. Nothing else is required.

```gdscript
# On Unit, Deployable, Tile, WorldFXLayer:

signal anim_done   # emit when play_anim finishes (or immediately if duration == 0)

func play_anim(anim_id: String, params: Dictionary, duration: float) -> void:
    ## Begin the named animation.
    ## Emit anim_done when complete. If duration == 0, apply end-state and emit immediately.

func snap_anim(anim_id: String) -> void:
    ## Immediately apply the end-state of the named animation without playing it.
    ## Called when an interruptible entry is cut short.
```

The node is responsible for its own Tween/AnimationPlayer management. The sequencer does not know how a node implements `play_anim` — only that `anim_done` fires when it is done.

Typical pattern using Godot 4 tweens:

```gdscript
func play_anim(anim_id: String, params: Dictionary, duration: float) -> void:
    if duration == 0.0:
        _apply_end_state(anim_id, params)
        anim_done.emit()
        return
    match anim_id:
        "hit_flash":
            var col : Color = params.get("color", Color.WHITE)
            var tween := create_tween()
            tween.tween_property(self, "modulate", col, duration * 0.3)
            tween.tween_property(self, "modulate", Color.WHITE, duration * 0.7)
            await tween.finished
            anim_done.emit()
        # ...
```

`await tween.finished` inside `play_anim` makes it a GDScript coroutine. The sequencer does not `await` it — the `CONNECT_ONE_SHOT` on `anim_done` is the completion hook. The two mechanisms are independent.

---

## 8. Death Node Lifecycle

When a unit dies:
1. `unit_died` fires → unit removed from `CombatManager.player_units` / `enemy_units` (logic complete).
2. Visual node stays in the scene tree with `_dying := true` (blocks click/hover/inspection).
3. `death_fade` entry is enqueued with `on_complete = unit_node.queue_free` and `interruptible = false`.
4. `on_complete` fires after the animation; `queue_free` removes the node from the scene.

This ensures the visual "no longer exists" moment coincides with what the player sees, not with when logic resolved.

---

## 9. Priority Placeholder Animations (M1 Scope)

These are the minimum set. All are placeholder quality: color rectangles, scaled shapes. No sprite art required.

| Animation ID | Target | Duration | Interruptible | event_type | What it does |
|---|---|---|---|---|---|
| `hit_flash` | Unit | 0.15s | true | `"hit"` | Brief color pulse in element color |
| `death_fade` | Unit | 0.5s | false | `"death"` | Fades to faction color then transparent; `on_complete = queue_free` |
| `status_pulse` | Unit | 0.3s | true | `"status"` | Ring expanding from unit center in status element color |
| `projectile_impact` | WorldFXLayer | 0.2s | true | `"impact"` | Burst at impact point, element-colored |
| `deploy_appear` | Deployable | 0.25s | true | `"deploy"` | Scale from 0 to full size |
| `deploy_destroyed` | Deployable | 0.4s | false | `"deploy"` | Flash then fade; `on_complete` handles on-destroyed cleanup |
| `collapse_fall` | Tile/voxel | 0.3s | true | `"terrain"` | Voxel translates downward to landing position |

Durations above are starting points; tune against feel during testing.

---

## 10. Explicitly Out of Scope (M1)

- Terrain destruction animation beyond instant-removal with a one-frame dust stub
- Unit movement slide/lerp (snap-to-position is sufficient)
- Overlap/parallel entries *within* a single batch member (one entry per node per event)
- Any sprite art or real particle systems
- Sound — timing hooks should be reserved but no audio implementation yet
- Aura animation — aura voxel highlighting is UI, not sequenced animation; it updates live
- Tag-based batching rules engine — tags are assigned now; rules are evaluated later

---

## 11. Headless / Smoke Test Behavior

`ARTILLERY_SMOKE=1` sets `AnimationSequencer.fast_forward = true` before any combat scene loads. Every `play_anim` call applies end-state and emits `anim_done` in the same frame. The batch queue, `next_batch()` calls, and wave boundaries are still fully exercised — only wall-clock duration is collapsed to zero. All existing smoke tests must pass with the sequencer active.

---

## 12. Build Order

1. `AnimationEntry` class — all fields including `event_type`, `wave`, `tags`.
2. `AnimationSequencer` autoload — batch queue, `enqueue`, `next_batch`, `_play_next_batch`, `fast_forward`, EventBus subscriptions.
3. `WorldFXLayer` node stub — implements `play_anim` / `snap_anim` / `anim_done` with no-op placeholder bodies.
4. `play_anim`, `snap_anim`, `anim_done` stubs on `Unit` and `Deployable` — emit `anim_done` immediately (fast-forward behavior for everything until real animations are wired).
5. `CombatManager._anim_wave` counter + `next_batch()` calls in death-cascade loop.
6. `hit_flash` and `death_fade` on Unit — first real animations; immediately expose ordering issues in the death-cascade queue.
7. `projectile_impact` on WorldFXLayer and `status_pulse` on Unit.
8. `deploy_appear` and `deploy_destroyed` on Deployable.
9. `collapse_fall` on TerrainRenderer / voxel node.
10. Verify fast-forward mode passes all existing smoke tests with sequencer fully wired.
