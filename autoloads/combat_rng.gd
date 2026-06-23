extends Node

var rng : RandomNumberGenerator = RandomNumberGenerator.new()

func init(stage_seed: int) -> void:
	rng.seed = stage_seed ^ Time.get_ticks_msec()
