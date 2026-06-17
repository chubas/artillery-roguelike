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
var deployables_enabled     : bool = true   # M6: mines/shield generators spawn + their hooks

# Future systems — false until implemented
var wind_enabled            : bool = true   # M8: wind force on projectiles + fire spread
var artifacts_enabled       : bool = true   # M9: passive squad-wide artifact effects
var keywords_enabled        : bool = false
var card_deck_enabled       : bool = true   # M5: card UI + targeting input path
