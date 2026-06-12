# Targeting overlay layer (terrain spec §8.4, §11.4). Renders above terrain/units,
# never mutates game state. The CanvasLayer follows the viewport so its child
# overlay can draw in world coordinates.
class_name TargetingUI
extends CanvasLayer

var _overlay : TargetingOverlay

func setup(terrain: TerrainManager, unit: PlayerUnit) -> void:
	follow_viewport_enabled = true
	_overlay = TargetingOverlay.new()
	_overlay.terrain = terrain
	_overlay.unit = unit
	add_child(_overlay)

# Pushed by World every frame; the overlay draws from this state.
func set_aim_state(angle_deg: float, charging: bool, power_frac: float) -> void:
	_overlay.angle_deg = angle_deg
	_overlay.charging = charging
	_overlay.power_frac = power_frac
