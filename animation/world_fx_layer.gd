# M31: Handles position-based world FX (projectile impact bursts, etc.).
# Implements the animation interface so AnimationSequencer can target it like any other node.
# All FX are drawn in _draw(); each active burst is a small dict tracked in _bursts.
class_name WorldFXLayer
extends Node2D

signal anim_done

class Burst extends RefCounted:
	var pos    : Vector2
	var col    : Color
	var radius : float
	var alpha  : float = 1.0

var _bursts : Array = []

func play_anim(anim_id: String, params: Dictionary, duration: float) -> void:
	if duration == 0.0:
		anim_done.emit()
		return
	match anim_id:
		"projectile_impact":
			var b := Burst.new()
			b.pos    = params.get("pos", Vector2.ZERO)
			b.col    = params.get("col", Color.WHITE)
			b.radius = 4.0
			_bursts.append(b)
			queue_redraw()
			var t := create_tween()
			t.tween_property(b, "radius", 20.0, duration * 0.5)
			t.tween_property(b, "alpha",  0.0,  duration * 0.5)
			t.tween_callback(func() -> void:
				_bursts.erase(b)
				queue_redraw()
				anim_done.emit())
		_:
			anim_done.emit()

func snap_anim(_anim_id: String) -> void:
	_bursts.clear()
	queue_redraw()
	anim_done.emit()

func _draw() -> void:
	for b : Burst in _bursts:
		var c := b.col
		c.a = b.alpha
		draw_circle(b.pos, b.radius, c)
