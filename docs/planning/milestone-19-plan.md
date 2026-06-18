# Milestone 19 — Branching Map (Diamond DAG)

## Overview

Replace the linear M14 map with a **directed acyclic graph** the player walks forward through.
The prototype layout is a **1 → 2 → 3 → 2 → 1 diamond** (9 combat nodes), but the engine is
**graph-shaped**, not diamond-shaped: each node carries an explicit list of forward edges; layout
and content are data.

Player agency: after clearing a stage, the map shows **every legal next node** (typically two
choices on branching rows). The player picks one, then enters combat. No backward travel.

This mirrors the existing `MapScreen` + `RunController` flow; the change is **state + UI**, not a
new scene type.

---

## Locked decisions

| # | Decision |
|---|----------|
| 1 | **Forward-only DAG.** Each `MapNode` stores `next_nodes: Array[int]` — indices into `MapState.nodes`. No back-edges; validation rejects illegal picks. |
| 2 | **Field name:** `next_nodes` (not `next_possible_stages`) — stages live on the node via `stage_path`; edges are node indices. A helper `next_choices() -> Array[MapNode]` resolves indices for UI. |
| 3 | **`current` semantics change.** `current` is the **node index the player is on** (about to fight, or last cleared). Not a monotonic “step counter”. |
| 4 | **Selection flow.** If `current` is **not** in `visited`: the only legal fight is `nodes[current]` (row 0 of the diamond — single “Enter Stage”). If `current` **is** in `visited`: `next_choices()` = outgoing `next_nodes` that are not yet visited (prototype: all outgoing; no revisiting cleared nodes). Player **clicks a node** to set `current` and enter combat. |
| 5 | **Post-combat:** `mark_visited()` on the node just cleared; **do not** auto-advance. Return to map; if `next_choices()` is empty → **RUN COMPLETE**; else show picks. |
| 6 | **Prototype map:** `MapState.build_diamond(stage_paths)` — 9 nodes, edges below, stages assigned by cycling `stage_paths` (reuse `stage_01` / `stage_02` / `stage_03`). `Run.start_default_run()` switches from `build_linear` to `build_diamond`. |
| 7 | **Layout hint:** `MapNode.layer: int` (0 = top of diamond) baked at build time for UI positioning only — not used for gameplay rules. |
| 8 | **Linear builder kept.** `build_linear()` remains for smoke/regression; default run uses diamond. |
| 9 | **M14 smoke** updated, not removed — linear path still tested via `build_linear()` directly. New `_m19_smoke()` exercises diamond graph + `choose_next`. |

---

## Diamond prototype topology (9 nodes)

Row/layer indices and edges (`next_nodes`):

```
layer 0:  [0]
layer 1:  [1] [2]
layer 2:  [3] [4] [5]
layer 3:  [6] [7]
layer 4:  [8]

0  → [1, 2]
1  → [3, 4]
2  → [4, 5]
3  → [6]
4  → [6, 7]
5  → [7]
6  → [8]
7  → [8]
8  → []     ← terminal; clearing 8 with no outgoing = run complete
```

ASCII:

```
           (0)
          /   \
        (1)   (2)
       / | \ / | \
     (3)(4)(5)(4)(5)   ← 3,4,5 on layer 2
        \|/ \|/
        (6) (7)        ← layer 3
          \ /
          (8)          ← layer 4 / boss row
```

*(Layer-2 nodes are 3, 4, 5 — diagram is schematic.)*

Stage assignment (cycle `stage_paths`):

| Node | Layer | Example stage |
|------|-------|----------------|
| 0 | 0 | stage_01 |
| 1, 2 | 1 | stage_02, stage_03 |
| 3–5 | 2 | stage_01, stage_02, stage_03 |
| 6, 7 | 3 | stage_01, stage_02 |
| 8 | 4 | stage_03 |

Exact pairing is arbitrary for the prototype; cycling the three existing `.tres` files is enough.

---

## Data model changes

### `MapNode` (`state/map_node.gd`)

```gdscript
var next_nodes : Array[int] = []   # forward edges (node indices)
var layer      : int = 0           # UI row in the map diagram
```

`to_dict` / `from_dict` gain `next_nodes` and `layer`.

### `MapState` (`state/map_state.gd`)

**Remove / replace:**

| Old | New |
|-----|-----|
| `advance()` | `select_next(node_index: int)` — validates index ∈ legal choices, sets `current` |
| `is_last()` | `is_terminal()` — `current_node().next_nodes.is_empty()` |
| `is_complete()` | `visited` contains a terminal node **or** `current` is terminal and visited |

**Add:**

```gdscript
func next_choices() -> Array[MapNode]:
    # If current not yet visited → [nodes[current]] (must clear current first).
    # Else → nodes indexed by current_node().next_nodes (filter visited in prototype).

func can_select(node_index: int) -> bool:
    # True if node_index is a legal pick right now.

func build_diamond(stage_paths: Array) -> MapState:
    # Factory: 9 nodes, edges table above, layers 0..4.
```

**Visited semantics:** `mark_visited()` appends `current` if absent (unchanged). Called **after** a successful stage clear, before returning to the map.

---

## UI changes (`ui/map_screen.gd`)

Replace horizontal `NodeRow` strip with a **`MapGraphView`** (can remain inner class):

1. **Layout:** group nodes by `layer`; center each row; vertical spacing ~80px, horizontal spacing from row width.
2. **Edges:** draw lines from each node to each `next_nodes` target (only forward — already DAG).
3. **Node states:**
   - **Cleared** (`visited`) — green fill
   - **Current** (`index == map.current`) — gold ring
   - **Selectable** (`can_select(index)`) — bright outline, clickable
   - **Unreachable** — dim grey
4. **Interaction:** clicking a selectable node emits `stage_selected(node)` (same signal as M14 — `RunController` unchanged on the signal).
5. **Detail panel:** show selected/hovered node’s stage id, objective, `threat_tags` (reuse M14 detail string).
6. **Enter Stage button:** optional — can be removed in favor of click-to-enter on selectable nodes only; if kept, arms the single choice when `next_choices().size() == 1`.

**No backward clicks:** nodes not in `can_select()` ignore input.

---

## Run controller changes (`world/run_controller.gd`)

Minimal diff on `_on_all_rewards_done` post-combat branch:

```gdscript
# Before (M14):
m.mark_visited()
m.advance()
if m.is_complete(): ...

# After (M19):
m.mark_visited()
if m.is_terminal() and m.visited.has(m.current):
    _show_map_end("RUN COMPLETE")
else:
    _show_map()   # player picks from next_choices()
```

Pre-first-combat: after rewards, `_show_map()` with `current == 0`, not visited → single choice node 0.

`_enter_combat(node)` unchanged — still sets `combat_scene.stage` from `node.stage()`.

---

## Smoke / verification

### `_m19_smoke()` (new)

```
[diamond build]     9 nodes, layer counts 1/2/3/2/1, node0 next=[1,2]
[forward only]      select_next(1) from 0 OK; select_next(0) from 0 after visited fails
[path walk]         0 → 1 → 3 → 6 → 8 terminal; is_complete after mark_visited on 8
[serialization]     next_nodes + layer round-trip through RunState.to_dict
```

### `_m14_smoke()` (update)

Keep `build_linear()` walk for regression; default `Run.active.map` may now be diamond — smoke block that asserts `nodes==3` should use an explicit `build_linear()` local, not `Run.active.map`.

### Manual

- New run → rewards → map shows diamond, single node at top.
- Clear → map shows two choices on row 2; pick one → combat → repeat.
- Reach node 8, clear → RUN COMPLETE.

---

## Files changed

| File | Change |
|------|--------|
| `state/map_node.gd` | `next_nodes`, `layer`; serialize |
| `state/map_state.gd` | Graph API; `build_diamond()`; deprecate `advance()` |
| `ui/map_screen.gd` | Diamond `MapGraphView`; click-to-select |
| `autoloads/run.gd` | `build_diamond(_DEFAULT_MAP)` |
| `world/run_controller.gd` | Post-combat map advance logic |
| `world/combat_scene.gd` | `_m14_smoke` tweak + `_m19_smoke()` |
| `PROGRESS.md` | M19 entry |

---

## Seams for later

| Seam | Notes |
|------|-------|
| **Arbitrary graphs** | New `MapState.build_from_spec(dict)` — nodes + edges array, any shape; diamond is one preset. |
| **>2 branches** | `next_nodes` already supports N; UI lays out row by `layer` + index order. |
| **EVENT / SHOP nodes** | `MapNode.Type` already reserved; graph engine unchanged. |
| **Faction-biased stage pools** | Node picks stage from a pool at build time instead of fixed `stage_path`. |
| **Cross-row telegraphing** | `threat_tags` on descriptor already surfaced; add icons per node. |
| **Save/load** | `next_nodes` + `layer` in `to_dict` — ready once disk I/O lands. |

---

## Out of scope (M19)

- Procedural map generation
- Skipping / backtracking / revisiting cleared nodes for rewards
- Animated path transitions
- Separate “world map” scene — still `MapScreen` on `RunController`
