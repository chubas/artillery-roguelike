# Stable faction identifiers for content tagging (run-design §5). These are code ids —
# not display names. UI / telegraphing maps ids → player-facing names via display_name().
class_name Faction
extends RefCounted

const NEUTRAL : String = "neutral"
const ARMY    : String = "army"   # Seekers
const CELL    : String = "cell"   # Awakened
const BIO     : String = "bio"    # Shamans

static func all_ids() -> Array[String]:
	return [NEUTRAL, ARMY, CELL, BIO]

static func is_valid(id: String) -> bool:
	return id in all_ids()

## Player-facing name for a faction id (rewards UI, map telegraphing, etc.).
static func display_name(id: String) -> String:
	match id:
		ARMY: return "Seekers"
		CELL: return "Awakened"
		BIO:  return "Shamans"
		_:    return "Neutral"
