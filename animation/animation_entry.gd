# M31: Data bag for a single queued animation. Grouped into batches by AnimationSequencer.
# Batch members play in parallel; batches are sequential.
class_name AnimationEntry
extends RefCounted

var anim_id       : String          = ""
var target        : Node            = null
var params        : Dictionary      = {}
var duration      : float           = 0.0
var interruptible : bool            = true
var on_complete   : Callable

# -- Tagging fields --
var event_type : String       = ""   # canonical category: "impact", "hit", "death",
                                     #   "status", "deploy", "terrain"
var wave       : int          = 0    # cascade depth: 0 = direct, 1 = first-order chain, etc.
var tags       : Array[String] = []  # free-form labels for future rule matching
