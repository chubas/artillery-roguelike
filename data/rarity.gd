# Content rarity tiers (M34). Used on cards, units, and artifacts as a metadata tag.
# No gameplay effect yet — drives visual presentation and future loot weighting.
class_name Rarity
extends RefCounted

const BASIC     : String = "basic"
const COMMON    : String = "common"
const RARE      : String = "rare"
const EPIC      : String = "epic"
const LEGENDARY : String = "legendary"
const BOSS      : String = "boss"
const EVENT     : String = "event"

static func all() -> Array[String]:
	return [BASIC, COMMON, RARE, EPIC, LEGENDARY, BOSS, EVENT]

static func display_name(id: String) -> String:
	match id:
		BASIC:     return "Basic"
		COMMON:    return "Common"
		RARE:      return "Rare"
		EPIC:      return "Epic"
		LEGENDARY: return "Legendary"
		BOSS:      return "Boss"
		EVENT:     return "Event"
		_:         return id.capitalize()
