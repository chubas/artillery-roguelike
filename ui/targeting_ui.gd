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

# M5: which card (if any) is awaiting a target — highlights valid targets.
func set_card_state(pending_card: CardDefinition) -> void:
	_overlay.pending_card = pending_card

# M5: telegraphed reinforcement waves still to come — [{ "col": int, "turns_left": int }].
func set_reinforcement_state(warnings: Array) -> void:
	_overlay.pending_reinforcements = warnings

# M15: highlight the spawn-zone band during pre-combat placement.
func set_placement_state(active: bool, min_col: int, max_col: int) -> void:
	_overlay.placement_active = active
	_overlay.placement_min_col = min_col
	_overlay.placement_max_col = max_col

# Drop indicator: vertical line + unit name showing where the next unit will land.
func set_drop_indicator(col: int, name: String) -> void:
	_overlay.set_drop_indicator(col, name)
