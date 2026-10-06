class_name WeaponAmmoCompatibility
extends RefCounted

# Membership and selection order only: never performance, stock or eligibility.
# Legacy Ammo.Weapon_ID remains the source association, not exclusive ownership.
# Reuse references one Ammo_ID; it does not clone an Ammo record.
static func from_legacy_rows(rows: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		result.append({"weapon_id":row.Weapon_ID,"ammo_id":row.Ammo_ID})
	return result

static func validate(relations: Variant,weapon_ids: Array,ammo_ids: Array) -> Dictionary:
	var errors: Array[Dictionary] = []
	var occupied := {}
	if not relations is Array: return {"valid":false,"errors":[{"path":"compatibility","code":"invalid_relations","message":"Expected relation array"}]}
	for i: int in relations.size():
		var row: Variant = relations[i]
		var path := "compatibility[%d]" % i
		if not row is Dictionary:
			errors.append({"path":path,"code":"invalid_relation","message":"Expected relation object"})
			continue
		for field: Variant in row:
			if field not in ["weapon_id","ammo_id"]: errors.append({"path":path+"."+str(field),"code":"unexpected_relation_field","message":"Compatibility holds only references; order is the array order"})
		var weapon: Variant = row.get("weapon_id")
		var ammo: Variant = row.get("ammo_id")
		if not weapon is String or not weapon_ids.has(weapon): errors.append({"path":path+".weapon_id","code":"missing_weapon_reference","message":"Weapon reference does not exist"})
		if not ammo is String or not ammo_ids.has(ammo): errors.append({"path":path+".ammo_id","code":"missing_ammo_reference","message":"Ammo reference does not exist"})
		var key := JSON.stringify([weapon,ammo])
		if occupied.has(key): errors.append({"path":path,"code":"duplicate_compatibility","related_path":occupied[key],"message":"Repeated membership must not duplicate ammo or inventory"})
		else: occupied[key] = path
	return {"valid":errors.is_empty(),"errors":errors}

static func ammo_ids_for(relations: Array[Dictionary],weapon_id: String) -> Array[String]:
	var result: Array[String] = []
	for relation: Dictionary in relations:
		if relation.weapon_id == weapon_id: result.append(relation.ammo_id)
	return result
