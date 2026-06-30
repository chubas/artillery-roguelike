# Keyword lookup + collectors (M41). Static, lazy-loaded — mirrors PowerCalculator / DamageResolver.
#
# Two jobs:
#   1. Registry: id -> KeywordDef, lazily loaded once from res://data/keywords/*.tres.
#   2. Collectors: given an entity, return the ordered, de-duplicated list of keyword ids it has
#      RIGHT NOW (definition keywords + its shot's keywords + any keyword-backed active status).
#
# The status link is by shared id: a unit's active_statuses keys are checked against the registry,
# so a status whose id is a registered keyword (today: `boosted`) flows into the unit's keyword set
# automatically — this is how an applied effect (Boosted card / permanent_boosted) surfaces a keyword.
class_name KeywordRegistry

const DIR := "res://data/keywords"

static var _registry : Dictionary = {}   # id -> KeywordDef
static var _loaded   : bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var kw := load("%s/%s" % [DIR, file]) as KeywordDef
		if kw != null and kw.id != "":
			_registry[kw.id] = kw

static func def(id: String) -> KeywordDef:
	_ensure_loaded()
	return _registry.get(id, null)

static func has(id: String) -> bool:
	_ensure_loaded()
	return _registry.has(id)

# --- Collectors ----------------------------------------------------------------

## Keywords on a live combat unit: its definition's, its active shot's, and any keyword-backed
## active status (e.g. Boosted applied by a card).
static func for_unit(unit: Unit) -> Array:
	if not Features.keywords_enabled or unit == null:
		return []
	var ids : Array = []
	if unit.definition != null:
		ids.append_array(unit.definition.keywords)
	var shot := unit.get_active_shot()
	if shot != null:
		ids.append_array(shot.keywords)
	for sid in unit.active_statuses:
		if has(sid):
			ids.append(sid)
	return _dedup(ids)

## Keywords on a unit definition (no live unit): definition + its default shot.
static func for_definition(d: UnitDefinition) -> Array:
	if not Features.keywords_enabled or d == null:
		return []
	var ids : Array = []
	ids.append_array(d.keywords)
	if d.default_shot != null:
		ids.append_array(d.default_shot.keywords)
	return _dedup(ids)

## Keywords on a run-unit (squad viewer): its definition's, plus `boosted` if it carries permanent
## Boosted stacks applied across the run.
static func for_run_unit(rus: RunUnitState) -> Array:
	if not Features.keywords_enabled or rus == null:
		return []
	var d := load(rus.definition_id) as UnitDefinition
	var ids := for_definition(d)
	if rus.permanent_boosted > 0 and has("boosted") and not ids.has("boosted"):
		ids.append("boosted")
	return ids

static func for_shot(shot: ShotDefinition) -> Array:
	if not Features.keywords_enabled or shot == null:
		return []
	return _dedup(shot.keywords)

static func for_card(card: CardDefinition) -> Array:
	if not Features.keywords_enabled or card == null:
		return []
	return _dedup(card.keywords)

static func for_artifact(artifact: ArtifactDef) -> Array:
	if not Features.keywords_enabled or artifact == null:
		return []
	return _dedup(artifact.keywords)

# --- Formatting ----------------------------------------------------------------

## Multi-line tooltip body for a set of keyword ids: "Boosted — <desc>\nUnit — <desc>".
## Returns "" when empty/disabled so callers can skip appending. Unknown ids are shown by id.
static func tooltip(ids: Array) -> String:
	if not Features.keywords_enabled or ids.is_empty():
		return ""
	var lines : Array[String] = []
	for id in ids:
		var kw := def(id)
		if kw != null:
			var name := kw.display_name if kw.display_name != "" else kw.id
			var desc := kw.resolve_description()
			lines.append("%s — %s" % [name, desc] if desc != "" else name)
		else:
			lines.append(str(id))
	return "\n".join(lines)

static func _dedup(ids: Array) -> Array:
	var out : Array = []
	for id in ids:
		if id != "" and not out.has(id):
			out.append(id)
	return out
