# Single entry point for folding a unit's PowerMods into its effective attack (M40).
#
# Two-tier fold (locked design):
#   permanent = max(0, (base_power + Σ perm_add) × Π perm_mult)   ← card / round-start value
#   combat    = max(0, (permanent  + Σ comb_add) × Π comb_mult)   ← live in-combat value
#
# Clamped to ≥ 0 at BOTH tier boundaries so a net-negative permanent can't flip sign when a
# combat multiplier is applied. Shot-level bonuses (flight-time, conditional_bonus) are applied
# AFTER this in DamageResolver / AoEResolver; zone × affinity and the single floor() also live
# downstream — effective_attack_f keeps float precision for them.
class_name PowerCalculator

## Effective attack as an int (UI / display). include_combat=false → permanent (card) value only.
static func effective_attack(unit, include_combat := true) -> int:
	return int(floor(effective_attack_f(unit, include_combat)))

## Effective attack as a float, preserving precision for downstream zone/affinity multipliers.
static func effective_attack_f(unit, include_combat := true) -> float:
	var base : float = unit.definition.base_power
	var pa := 0.0
	var pm := 1.0
	var ca := 0.0
	var cm := 1.0
	for m in unit.power_mods:
		if not m.active_for(unit):
			continue
		if m.tier == PowerMod.Tier.PERMANENT:
			if m.op == PowerMod.Op.ADD: pa += m.value
			else: pm *= m.value
		else:
			if m.op == PowerMod.Op.ADD: ca += m.value
			else: cm *= m.value
	var perm := maxf(0.0, (base + pa) * pm)
	if not include_combat:
		return perm
	return maxf(0.0, (perm + ca) * cm)

## Permanent-tier value from a RunUnitState (card / logbook display, no live combat unit).
## Folds only the serialized permanent mods over the definition's base_power.
static func card_attack(run_state, definition) -> int:
	var base : float = definition.base_power
	var add := 0.0
	var mult := 1.0
	for d in run_state.power_mods:
		if int(d.get("tier", PowerMod.Tier.PERMANENT)) != PowerMod.Tier.PERMANENT:
			continue
		if int(d.get("op", PowerMod.Op.ADD)) == PowerMod.Op.ADD:
			add += float(d.get("value", 0.0))
		else:
			mult *= float(d.get("value", 1.0))
	return int(floor(maxf(0.0, (base + add) * mult)))

## Ordered breakdown of active mods for inspector tooltips:
## [{ "label": String, "op": Op, "value": float, "tier": Tier }, ...] (base row first).
static func breakdown(unit, include_combat := true) -> Array:
	var rows : Array = [{ "label": "Base", "op": PowerMod.Op.ADD,
			"value": float(unit.definition.base_power), "tier": PowerMod.Tier.PERMANENT }]
	for m in unit.power_mods:
		if m.tier == PowerMod.Tier.COMBAT and not include_combat:
			continue
		if not m.active_for(unit):
			continue
		rows.append({ "label": m.label, "op": m.op, "value": m.value, "tier": m.tier })
	return rows
