class_name BattleHUDModel
extends RefCounted

# Consumes already-authorized presentation values. Never reads simulation state.
static func weapons(unit: Dictionary, structure: Dictionary, viewer: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if viewer <= 0 or int(unit.get("owner_player_id", 0)) != viewer: return rows
	if int(structure.get("unit_id", -1)) != int(unit.get("unit_id", -2)): return rows
	var grouped := {}
	for weapon: Dictionary in structure.get("weapons", []):
		var id := str(weapon.get("definition_id", ""))
		if id.is_empty(): continue
		if not grouped.has(id):
			grouped[id] = {"definition_id":id, "count":0, "inventory":{}, "channels":[]}
		var row: Dictionary = grouped[id]
		row.count += int(weapon.get("operable_count", 0))
		for ammo: String in weapon.get("inventory", {}):
			row.inventory[ammo] = int(row.inventory.get(ammo, 0)) + int(weapon.inventory[ammo])
		# Independent channels retain independent progress, not per-soldier timers.
		row.channels.append({"aim_progress":weapon.get("aim_progress", 0.0),
			"loading":weapon.get("fire", {}).get("loading", false),
			"loading_progress":weapon.get("fire", {}).get("loading_progress", 1.0)})
	var ids := grouped.keys()
	ids.sort()
	for id: String in ids: rows.append(grouped[id])
	return rows

static func command_slots(units: Array[Dictionary], viewer: int) -> Array[String]:
	var slots: Array[String] = ["", "", "", "", "", "", "", "", ""]
	for unit: Dictionary in units:
		if viewer <= 0 or int(unit.get("owner_player_id", 0)) != viewer or float(unit.get("health", 0.0)) <= 0: continue
		if int(unit.get("unit_type", -1)) == UnitDefinition.UnitType.ARMORED_VEHICLE:
			slots[0] = "fast"
			slots[2] = "reverse"
		if unit.get("armed", false): slots[1] = "attack_move"
		# Fire qualification is provided only from this owner's structure adapter.
		if unit.get("direct_fire", false): slots[4] = "ground_fire"
		if unit.get("artillery", false): slots[4] = "artillery"
	return slots

static func map_point(position: Vector3, bounds: Rect2, area: Rect2) -> Vector2:
	if bounds.size.x <= 0 or bounds.size.y <= 0: return area.position
	var relative := (Vector2(position.x, position.z) - bounds.position) / bounds.size
	return area.position + relative.clamp(Vector2.ZERO, Vector2.ONE) * area.size

static func selection_order(units: Array[Dictionary]) -> Array[int]:
	var values := units.duplicate(true)
	var categories := {"recon":0, "infantry":1, "armor":2, "support":3, "aircraft":4}
	values.sort_custom(func(a: Dictionary, b: Dictionary):
		var rank_a: int = categories.get(a.get("group_category", ""), 5)
		var rank_b: int = categories.get(b.get("group_category", ""), 5)
		if rank_a != rank_b: return rank_a < rank_b
		if a.get("configuration", "") != b.get("configuration", ""): return str(a.get("configuration", "")) < str(b.get("configuration", ""))
		return int(a.unit_id) < int(b.unit_id))
	var ids: Array[int] = []
	for value: Dictionary in values: ids.append(int(value.unit_id))
	return ids
