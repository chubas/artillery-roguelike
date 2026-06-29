# Feature flags (M3 spec §2.2). Systems check their flag at their ENTRY POINT and go
# dormant when disabled. Content (a fire shot) can exist while its system (elements)
# is off — the shot simply behaves as elementless.
extends Node

# Systems — disable to make the system go dormant entirely
var elements_enabled        : bool = true
var tile_statuses_enabled   : bool = true
var unit_statuses_enabled   : bool = true

# Content flags — disable specific effects without touching system code
var fire_enabled            : bool = true
var electric_enabled        : bool = true
var burning_tile_enabled    : bool = true
var electrified_tile_enabled: bool = true
var shields_enabled         : bool = true   # M5: shield mitigation layer in Unit.take_damage
var armor_enabled           : bool = true   # M20: armor mitigation layer in Unit.take_damage
var deployables_enabled     : bool = true   # M6: mines/shield generators spawn + their hooks

# Future systems — false until implemented
var wind_enabled            : bool = true   # M8: wind force on projectiles + fire spread
var collapse_enabled        : bool = true   # M17: collapsible terrain fall + crush
var artifacts_enabled       : bool = true   # M9: passive squad-wide artifact effects
var keywords_enabled        : bool = false
var card_deck_enabled       : bool = true   # M5: card UI + targeting input path
var essences_enabled        : bool = true   # M22: per-unit essence upgrade hooks
var sandbox_enabled         : bool = true   # M24: debug sandbox overlay in combat scene
var stacking_enabled        : bool = true   # M29: units/deployables may share the same voxel
var animations_enabled      : bool = true   # M31: AnimationSequencer batch queue + placeholder FX
var terrain_profiles_enabled : bool = true  # M32: profile-driven terrain generation + MapData pipeline
var stage_rng_enabled        : bool = true  # M33: seeded RNG per stage and combat
var run_seed                 : int  = 42    # M33: 0 = random each run; nonzero = fixed seed (repeatable)
var shop_enabled             : bool = true  # M34: shop node type + purchase screen
var events_enabled           : bool = true  # M35: event node type + event screen
var repair_enabled           : bool = true  # M36: repair node type + repair screen
var upgrade_enabled          : bool = true  # M36: upgrade node type + upgrade screen
var deck_viewer_enabled      : bool = true  # M37: deck viewer modal (world + combat)
var squad_viewer_enabled     : bool = true  # M37: squad viewer modal (world + combat)
var weight_mobility_enabled  : bool = true  # M38: weight-based climb limits + AP costs
var power_formula_enabled    : bool = true  # M39: permanent_mult + conditional_bonus in DamageResolver
