# Code-drawn explosion: expanding circle that fades and frees itself (spec §11.3).
class_name ExplosionFX
extends Node2D

const DURATION := 0.3

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := _t / DURATION
	var r := lerpf(4.0, (Const.AOE_RADIUS + 0.5) * Const.VOXEL_SIZE, k)
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.6, 0.2, 1.0 - k))
	draw_circle(Vector2.ZERO, r * 0.6, Color(1.0, 0.9, 0.5, (1.0 - k) * 0.8))
