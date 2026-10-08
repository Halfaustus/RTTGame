class_name EditorAcceptanceCatalog
extends RefCounted

# Narrow TEST ONLY adapter, never a formal DATA importer or reference-data path.
const PATH := "res://data/test_only/acceptance_06c.json"
const ARMOR_HALF_EXTENTS := Vector3(0.5,0.25,0.5) # TEST ONLY: ground blast can pass below Hull for zero-direction review.
static var _document: Dictionary = {}

static func definition(name: String) -> UnitDefinition:
	if _document.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary or parsed.get("format") != "rtt-unit-editor" or parsed.get("version") != 5:
			push_error("TEST ONLY editor document invalid")
			return null
		_document = parsed
	var binding := find(_document.bindings,"Relations",name)
	if binding.is_empty() or not binding.get("TestOnly",false): return null
	var body := find(_document.bodies,"id",binding.BodyId)
	var loadout := find(_document.loadouts,"Id",binding.LoadoutId)
	if body.is_empty() or loadout.is_empty() or not body.testOnly or not loadout.TestOnly: return null
	var fields: Dictionary = body.fields
	if not numbers(fields,["memberCount","maximumHealth","roadSpeed","offroadPenalty","turnSpeed","kinetic.front","kinetic.side","kinetic.rear","kinetic.top","chemical.front","chemical.side","chemical.rear","chemical.top"]): return null
	if binding.Relations.MemberCount != fields.memberCount or not fields.memberCount.is_valid_int() or int(fields.memberCount) < 1: return null
	if body.unitType not in ["infantry","ground_vehicle"] or not body.tags.is_empty() or loadout.Entries.size() > 1: return null
	if body.unitType == "ground_vehicle" and fields.memberCount != "1": return null
	if body.unitType == "infantry":
		if binding.Relations.Members.size() != int(fields.memberCount) or float(fields.maximumHealth) != int(fields.memberCount)*5: return null
		for energy: String in ["kinetic","chemical"]:
			for face: String in ["front","side","rear","top"]:
				if fields[energy+"."+face] != fields[energy+".front"] or fields[energy+"."+face] not in ["6","8","10"]: return null
	var unit := UnitDefinition.new()
	unit.configuration_source = "test_only:rtt_unit_editor:"+binding.Id
	unit.resource_name = name
	unit.member_count = int(binding.Relations.MemberCount)
	unit.maximum_health = float(fields.maximumHealth)
	unit.hardened_speed = float(fields.roadSpeed)
	unit.unhardened_speed = unit.hardened_speed*(1.0-float(fields.offroadPenalty))
	# Temporary prototype reverse policy retained; no new editor field/framework.
	unit.hardened_reverse_speed = unit.hardened_speed*0.5
	unit.unhardened_reverse_speed = unit.unhardened_speed*0.5
	unit.turn_speed_degrees = float(fields.turnSpeed)
	if body.unitType == "ground_vehicle":
		unit.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
		unit.hitbox_half_extents = ARMOR_HALF_EXTENTS
		for face: String in ["front","side","rear","top"]:
			unit.kinetic_armor_by_face[face] = float(fields["kinetic."+face])
			unit.chemical_armor_by_face[face] = float(fields["chemical."+face])
	else:
		unit.protection_kinetic = float(fields["kinetic.front"])
		unit.protection_chemical = float(fields["chemical.front"])
	for entry: Dictionary in loadout.Entries:
		var source := find(_document.weapons,"id",entry.WeaponId)
		if source.is_empty() or not source.testOnly: return null
		var weapon := WeaponDefinition.new()
		var w: Dictionary = source.fields
		if not numbers(w,["operators","minRange","maxRange","spread","aimMin","aimMax","rpm","consumption","capacity","reload","ignoreReduction"]): return null
		var vehicle: bool = body.unitType == "ground_vehicle"
		var mechanical: bool = "mechanical_loading" in source.tags
		if entry.Quantity != "1" or w.operators != "1" or w.minRange != "0" or w.slotRule != ("vehicle_slot" if vehicle else "primary") or w.reloadRule != "continuous" or w.reload != ("4" if mechanical else "3") or w.actualInterval != null: return null
		if source.tags not in [[],["top_attack"],["mechanical_loading"]] or source.targets != ["infantry","ground_vehicle"] or source.ammoIds.size() != 1 or entry.AmmoOrder != source.ammoIds: return null
		if binding.Relations.Roles.size() != 1: return null
		var role: Dictionary = binding.Relations.Roles[0]
		if role.EntryId != entry.Id or role.Quantity != "1" or role.OperatorIds != [binding.Relations.Members[0].Id] or role.CandidateRoleIds != []: return null
		if entry.Inventory.keys() != entry.AmmoOrder or not str(entry.Inventory[entry.AmmoOrder[0]]).is_valid_int(): return null
		weapon.definition_id = source.id
		weapon.data_source = "test_only:rtt_unit_editor"
		weapon.required_operators = int(w.operators)
		weapon.range_m = float(w.maxRange)
		weapon.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY,WeaponDefinition.TargetType.GROUND_VEHICLE]
		weapon.aim_min_seconds = float(w.aimMin)
		weapon.aim_max_seconds = float(w.aimMax)
		weapon.moving_aim_qualification = 0
		weapon.indoor_qualification = 0
		weapon.can_fire_while_moving = false
		weapon.capacity = int(w.capacity)
		weapon.consumption_per_projectile = int(w.consumption)
		weapon.actual_round_interval = 60.0/float(w.rpm)
		weapon.game_projectile_interval = weapon.consumption_per_projectile*weapon.actual_round_interval
		weapon.preparation_seconds = float(w.reload)
		weapon.spread_radius_m = float(w.spread)
		weapon.reduction_ignore = float(w.ignoreReduction)/100.0
		weapon.attack_top = "top_attack" in source.tags
		weapon.mechanical_loading = mechanical
		for ammo_id: String in entry.AmmoOrder:
			var a := find(_document.ammo,"id",ammo_id)
			if a.is_empty() or not a.testOnly: return null
			if not numbers(a.fields,["damage","penetration","speed","blast","suppression","moduleDamage"]): return null
			if a.fields.damageType != "chemical" or a.fields.category not in ["HE","HEAT"] or a.fields.anchorRange != null or a.fields.anchorPenetration != null: return null
			if a.fields.category == "HE" and a.fields.moduleDamage != "0": return null
			if a.fields.category == "HEAT" and (a.fields.blast != "0" or a.fields.suppression != "0" or a.fields.moduleDamage != "100"): return null
			var ammo := AmmoDefinition.new()
			ammo.ammo_id = a.id
			ammo.damage_type = a.fields.damageType
			ammo.nominal_damage = float(a.fields.damage)
			ammo.penetration_upper = float(a.fields.penetration)
			ammo.anchor_penetration = ammo.penetration_upper # Chemical constant, not a kinetic distance anchor.
			ammo.initial_speed_mps = float(a.fields.speed)
			ammo.explosion_radius_m = float(a.fields.blast)
			ammo.suppression = float(a.fields.suppression)
			ammo.module_damage = float(a.fields.moduleDamage)
			ammo.configure_confirmed_curve()
			weapon.ammo_definitions.append(ammo)
		var allocation := WeaponAllocation.new()
		allocation.definition = weapon
		allocation.member_id = 1 # Supported single-operator, single-entry fixture only.
		allocation.primary_weapon = true # TEST ONLY: the sole configured weapon is the marker primary.
		if vehicle:
			var installations: Variant = _document.get("installations",{}).get(body.id)
			if not installations is Array or installations.size() != 1 or installations[0].Kind != "hull" or installations[0].Index != "1" or entry.MountKind != "hull" or entry.MountIndex != "1" or entry.InstallationId != installations[0].Id: return null
			allocation.node_kind = WeaponAllocation.NodeKind.HULL
			allocation.member_id = 0
			allocation.slot_id = "hull"
			allocation.armored_primary_weapon = true # TEST ONLY compatibility alias for existing armor fixtures.
		allocation.retention_priority = 0
		for ammo_id: String in entry.Inventory: allocation.initial_inventory[ammo_id] = int(entry.Inventory[ammo_id])
		unit.weapon_allocations.append(allocation)
	return unit if UnitDefinitionValidator.validate_unit_definition(unit).implemented_combat_ready else null

static func numbers(fields: Dictionary,keys: Array) -> bool:
	for key: String in keys:
		if not fields.get(key) is String or not fields[key].is_valid_float() or not is_finite(float(fields[key])): return false
	return true

static func find(rows: Array,key: String,value: String) -> Dictionary:
	for row: Dictionary in rows:
		if (str(row[key].get("Name","")) if key == "Relations" else str(row[key])) == value: return row
	return {}
