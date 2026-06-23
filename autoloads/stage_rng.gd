extends Node

var rng : RandomNumberGenerator = RandomNumberGenerator.new()

func init(seed_val: int) -> void:
	rng.seed = seed_val

func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
