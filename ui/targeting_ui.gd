# Targeting overlay layer. Renders above terrain/units, never mutates game state.
# The CanvasLayer follows the viewport so its child overlay draws in world coords.
class_name TargetingUI
extends CanvasLayer

var _overlay : TargetingOverlay

func setup(terrain: TerrainManager, units: Array) -> void:
	follow_viewport_enabled = true
	_overlay = TargetingOverlay.new()
	_overlay.terrain = terrain
	_overlay.units = units
	add_child(_overlay)

# Pushed by CombatManager every frame; the overlay draws from this state.
func set_aim_state(active_unit: Unit, charging: bool, power_frac: float) -> void:
	_overlay.active_unit = active_unit
	_overlay.charging = charging
	_overlay.power_frac = power_frac
