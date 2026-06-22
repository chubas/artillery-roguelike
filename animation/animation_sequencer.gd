# M31: Central animation sequencer. Sits between logic resolution and screen output.
# Logic resolves instantly; this sequencer controls when visuals play.
#
# Queue model: batches of AnimationEntry objects. Entries in the same batch play in parallel.
# Batches play sequentially. Batch boundaries are driven by event_type rules (impacts and deaths
# always start a new batch) and by explicit next_batch() calls from CombatManager.
extends Node

var fast_forward : bool = false
var world_fx     : Node = null   # WorldFXLayer set by combat_scene._ready()

var _batches       : Array = []  # Array[Array[AnimationEntry]] — sealed batches awaiting play
var _current_batch : Array = []  # open batch being filled by enqueue()
var _active_batch  : Array = []  # batch currently playing
var _active_count  : int  = 0    # entries in active batch not yet done

func _ready() -> void:
	if OS.get_environment("ARTILLERY_SMOKE") == "1":
		fast_forward = true
	if not Features.animations_enabled:
		return
	EventBus.unit_hit_taken.connect(_on_unit_hit)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.projectile_impact.connect(_on_projectile_impact)
	EventBus.tile_destroyed.connect(_on_tile_destroyed)
	EventBus.tile_status_applied.connect(_on_tile_status_applied)
	EventBus.deployable_placed.connect(_on_deployable_placed)
	EventBus.deployable_died.connect(_on_deployable_died)

# ── Public API ────────────────────────────────────────────────────────────────

func enqueue(entry: AnimationEntry) -> void:
	if not Features.animations_enabled:
		return
	_current_batch.append(entry)
	if _active_batch.is_empty() and _batches.is_empty():
		_flush_and_play()

# Seal the current open batch and push it to the queue. Called by CombatManager at explicit
# phase boundaries (between waves of the death cascade). Also called internally by event
# handlers that must start a new batch (impacts, deaths).
func next_batch() -> void:
	if not _current_batch.is_empty():
		_batches.append(_current_batch.duplicate())
		_current_batch.clear()
	if _active_batch.is_empty():
		_play_next_batch()

func interrupt_active_batch() -> void:
	for entry : AnimationEntry in _active_batch:
		if entry.interruptible and is_instance_valid(entry.target):
			entry.target.snap_anim(entry.anim_id)

# ── Internal queue ────────────────────────────────────────────────────────────

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
		if is_instance_valid(entry.target):
			entry.target.anim_done.connect(_on_entry_done.bind(entry), CONNECT_ONE_SHOT)
			entry.target.play_anim(entry.anim_id, entry.params, dur)
		else:
			_on_entry_done(entry)

func _on_entry_done(entry: AnimationEntry) -> void:
	if entry.on_complete.is_valid():
		entry.on_complete.call()
	_active_count -= 1
	if _active_count == 0:
		_active_batch.clear()
		_flush_and_play()

# ── EventBus handlers ─────────────────────────────────────────────────────────

func _on_unit_hit(unit: Unit, _damage: int, element: String, _source: Unit) -> void:
	var e := AnimationEntry.new()
	e.anim_id    = "hit_flash"
	e.target     = unit
	e.params     = {"color": _element_color(element)}
	e.duration   = 0.15
	e.event_type = "hit"
	e.tags.append("player" if unit.is_player else "enemy")
	enqueue(e)

func _on_unit_died(unit: Unit) -> void:
	next_batch()   # ensure deaths always follow hits
	var e := AnimationEntry.new()
	e.anim_id      = "death_fade"
	e.target       = unit
	e.params       = {}
	e.duration     = 0.5
	e.interruptible = false
	e.event_type   = "death"
	e.tags.append("player" if unit.is_player else "enemy")
	enqueue(e)

func _on_status_applied(target: Unit, status_id: String, _stacks: int) -> void:
	var e := AnimationEntry.new()
	e.anim_id    = "status_pulse"
	e.target     = target
	e.params     = {"status_id": status_id}
	e.duration   = 0.3
	e.event_type = "status"
	enqueue(e)

func _on_projectile_impact(world_pos: Vector2, _voxel: Vector2i, element: String) -> void:
	next_batch()   # impact always starts a fresh batch
	if world_fx == null or not is_instance_valid(world_fx):
		return
	var e := AnimationEntry.new()
	e.anim_id    = "projectile_impact"
	e.target     = world_fx
	e.params     = {"pos": world_pos, "col": _element_color(element)}
	e.duration   = 0.2
	e.event_type = "impact"
	enqueue(e)

func _on_tile_destroyed(_col: int, _row: int, _tile_type: int) -> void:
	pass   # collapse_fall stub: no visual for M31

func _on_tile_status_applied(_col: int, _row: int, _status_id: String) -> void:
	pass

func _on_deployable_placed(d: Deployable) -> void:
	var e := AnimationEntry.new()
	e.anim_id    = "deploy_appear"
	e.target     = d
	e.params     = {}
	e.duration   = 0.25
	e.event_type = "deploy"
	enqueue(e)

func _on_deployable_died(d: Deployable) -> void:
	next_batch()
	var e := AnimationEntry.new()
	e.anim_id      = "deploy_destroyed"
	e.target       = d
	e.params       = {}
	e.duration     = 0.4
	e.interruptible = false
	e.on_complete   = d.queue_free
	e.event_type   = "deploy"
	enqueue(e)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _element_color(element_id: String) -> Color:
	match element_id:
		"fire":     return Color(1.0, 0.45, 0.1)
		"electric": return Color(0.3, 0.85, 0.95)
		_:          return Color.WHITE
