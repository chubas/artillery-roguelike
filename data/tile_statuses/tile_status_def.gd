# Data definition of a tile status effect (M3 spec §5.1). Tiles-as-actors layer:
# Burning and Electrified in M3. Immutable; a TileStatusInstance tracks per-tile state.
class_name TileStatusDef
extends Resource

@export var id           : String = ""
@export var display_name : String = ""
@export var duration     : int = 3    # turns; -1 = permanent

## Damage dealt to units touching this tile per tick (applied as physical — see note)
@export var tick_damage  : int = 1

## Unit status applied to units touching this tile (e.g. Burning → Burn).
##
## Spec deviation (M3 plan): the spec stores `tick_element: ElementDef` here, which makes
## fire ↔ burning a HARD circular resource reference (fire.tile_status = burning;
## burning.tick_element = fire) that Godot's .tres loader cannot resolve. We instead store
## the applied unit status directly — a clean DAG (fire → burning → burn). Tile tick damage
## is physical; affinity on a 1-dmg tick is a no-op anyway, so nothing is lost in M3.
@export var applied_status : StatusEffectDef = null

## Tags on this tile status; used by spread and cleanse rules
@export var tags : Array[String] = []

## Tile tag required on a neighbour for spread (empty = no spread)
@export var spreads_to_tag : String = ""

## Tile tag that instantly removes this status on contact (empty = none)
@export var removed_by_tag : String = ""
