class_name ReplayContent
extends RefCounted

const MAP_ID := "prototype-map-0.2"
const RULES_ID := "prototype-rules-0.2"
const FILES: Array[String] = ["res://data/prototype_map.tres", "res://data/prototype_movement.tres", "res://data/prototype_combat.tres", "res://data/unit_mobile.tres", "res://data/unit_stationary.tres", "res://data/unit_unarmed.tres", "res://data/weapon_mobile.tres", "res://data/weapon_stationary.tres"]

static func fingerprints() -> Dictionary:
	var result := {}
	for path: String in FILES:
		result[path] = FileAccess.get_file_as_string(path).replace("\r\n", "\n").sha256_text()
	return result

static func compatibility(data: Dictionary) -> String:
	var error := ReplayFormat.compatibility(data, MAP_ID, RULES_ID, fingerprints())
	if not error.is_empty():
		return error
	# Require the complete current manifest; an empty/subset manifest must not bypass checks.
	if data.header.content_fingerprints.size() != FILES.size():
		return "incomplete content fingerprint manifest"
	return ""
