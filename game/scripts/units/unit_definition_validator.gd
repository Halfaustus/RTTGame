class_name UnitDefinitionValidator
extends RefCounted

# Levels validate EXISTING fields, not new gameplay attributes.
# PARTIAL: static aiming inputs. COMPLETE: current firing/selection contract
# plus formal certification. Coverage gaps fail certification explicitly.
enum Level { TEST, PARTIAL, COMPLETE }

static func validate_unit_definition(definition: UnitDefinition,level: int = Level.TEST) -> Dictionary:
	var structure: Array[Dictionary] = []
	var aiming: Array[Dictionary] = []
	var combat: Array[Dictionary] = []
	var formal: Array[Dictionary] = []
	if definition == null:
		_add(structure,"$","missing_definition","Unit definition is null")
	elif level not in Level.values():
		_add(structure,"validation_level","invalid_level","Unknown validation level")
	else:
		structure.append_array(definition.installation_issues())
		if not definition.weapon_allocations_valid(): _add(structure,"weapon_allocations","invalid_allocation","Allocation reference, member, stock or shared model constraint failed")
		if not definition.spatial_valid(): _add(structure,"spatial","invalid_spatial","Geometry or mount definition is invalid")
		if definition.unit_type not in UnitDefinition.UnitType.values(): _add(structure,"unit_type","invalid_unit_type","Unknown unit type")
		var equipped: Array[Dictionary] = []
		if definition.weapon != null: _add(combat,"weapon","legacy_weapon","Legacy single weapon is not the current firing contract")
		for i: int in definition.hull_weapon_slots.size():
			var slot := definition.hull_weapon_slots[i]
			if slot == null: continue
			if not slot.local_position.is_finite(): _add(structure,"hull_weapon_slots[%d].local_position" % i,"invalid_position","Position must be finite")
			if slot.weapon != null:
				equipped.append({"weapon":slot.weapon,"path":"hull_weapon_slots[%d].weapon" % i})
				if definition.unit_type == UnitDefinition.UnitType.INFANTRY: _add(combat,"hull_weapon_slots[%d]" % i,"unused_installation","Infantry initialization does not consume Hull slots")
		for i: int in definition.mounts.size():
			var mount := definition.mounts[i]
			if mount == null: continue
			_number(combat,"mounts[%d].rotation_speed_degrees" % i,mount.rotation_speed_degrees,0.0,true)
			if definition.unit_type == UnitDefinition.UnitType.INFANTRY: _add(combat,"mounts[%d]" % i,"unused_installation","Infantry initialization does not consume mounts")
			for j: int in mount.weapon_slots.size():
				var slot := mount.weapon_slots[j]
				if slot == null: continue
				if not slot.local_position.is_finite(): _add(structure,"mounts[%d].weapon_slots[%d].local_position" % [i,j],"invalid_position","Position must be finite")
				if slot.weapon != null: equipped.append({"weapon":slot.weapon,"path":"mounts[%d].weapon_slots[%d].weapon" % [i,j]})
		for i: int in definition.weapon_allocations.size():
			var allocation := definition.weapon_allocations[i]
			var path := "weapon_allocations[%d]" % i
			if allocation == null:
				_add(structure,path,"missing_allocation","Allocation is null")
				continue
			if allocation.definition == null:
				_add(structure,path+".definition","missing_weapon_reference","Weapon reference is null")
				continue
			if allocation.initial_pending < 0: _add(structure,path+".initial_pending","invalid_pending","Initial pending count is negative")
			if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER and (definition.unit_type != UnitDefinition.UnitType.INFANTRY or allocation.member_id < 1 or allocation.member_id > definition.member_count):
				_add(structure,path+".member_id","invalid_member_reference","Allocation references an absent member")
			_inventory(structure,allocation,path)
			if allocation.node_kind == WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK:
				_add(combat,path,"unassigned_stock","Stock has no configured operator/installation")
				continue
			equipped.append({"weapon":allocation.definition,"path":path+".definition"})
			if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER:
				if allocation.retention_priority < 0: _add(combat,path+".retention_priority","missing_priority","Reassignment priority is unconfigured")
				if allocation.definition.required_operators < 1 or allocation.definition.required_operators > definition.member_count: _add(combat,path+".definition.required_operators","invalid_operators","Required operators must fit the squad")
		for entry: Dictionary in equipped:
			var weapon: WeaponDefinition = entry.weapon
			for issue: Dictionary in weapon.cadence_issues():
				var copy := issue.duplicate(true)
				copy.path = entry.path+"."+issue.path
				structure.append(copy)
			_weapon(weapon,entry.path,aiming,combat)
			if not weapon.temporary_fields.is_empty(): _add(formal,entry.path+".temporary_fields","test_configuration","Temporary fields cannot certify formal definitions")
		for field: String in ["hardened_speed","unhardened_speed","hardened_reverse_speed","unhardened_reverse_speed","turn_speed_degrees"]:
			_number(combat,field,float(definition.get(field)),0.0,field == "turn_speed_degrees")
		if definition.unit_type == UnitDefinition.UnitType.INFANTRY:
			_number(combat,"member_aim_speed_degrees",definition.member_aim_speed_degrees,0.0,true)
			_number(combat,"protection_kinetic",definition.protection_kinetic,5.0)
			_number(combat,"protection_chemical",definition.protection_chemical,5.0)
		else:
			_number(combat,"maximum_health",definition.maximum_health,10.0)
			if definition.maximum_health > 20: _add(combat,"maximum_health","unconfirmed_health_exception","Above common vehicle range requires explicit exception")
			for field: String in ["kinetic_armor_by_face","chemical_armor_by_face"]:
				var faces: Dictionary = definition.get(field)
				for face: String in ["front","side","rear","top"]:
					if not faces.has(face) or not _numeric(faces[face]): _add(combat,field+"."+face,"missing_armor","Directional armor is missing")
					else: _number(combat,field+"."+face,float(faces[face]),5.0)
		if definition.configuration_source.is_empty() or definition.configuration_source == "unconfigured": _add(formal,"configuration_source","missing_source","Configuration provenance is unconfigured")
		elif definition.configuration_source.begins_with("test_only"): _add(formal,"configuration_source","test_configuration","Test definitions cannot enter a formal catalog")
	# Existing baseline responsibilities absent from this schema; no invented
	# fields/defaults or blind approval. Runtime combat context is also separate.
	_add(formal,"$coverage.unit_configuration","unsupported_rule_coverage","DB40 identity/base/config references, observation, weight/transport and capability qualification are not fully represented/validated")
	var errors: Array[Dictionary] = []
	errors.append_array(structure)
	if level >= Level.PARTIAL: errors.append_array(aiming)
	if level >= Level.COMPLETE:
		errors.append_array(combat)
		errors.append_array(formal)
	return {"valid":errors.is_empty(),"level":level,"errors":errors,
		"structure_valid":structure.is_empty(),"partial_test_ready":structure.is_empty() and aiming.is_empty(),
		"implemented_combat_ready":structure.is_empty() and aiming.is_empty() and combat.is_empty(),
		"formal_catalog_ready":structure.is_empty() and aiming.is_empty() and combat.is_empty() and formal.is_empty(),
		"full_combat_ready":false,"combat_issues":aiming+combat,"formal_issues":formal,
		"scope":"static implemented contract; runtime permissions, visibility and full DB40 systems separate"}

static func _weapon(w: WeaponDefinition,path: String,aiming: Array[Dictionary],combat: Array[Dictionary]) -> void:
	if w.definition_id.is_empty(): _add(aiming,path+".definition_id","missing_weapon_id","Stable weapon ID is missing")
	_number(aiming,path+".range_m",w.range_m,0.0)
	_number(aiming,path+".aim_min_seconds",w.aim_min_seconds,0.0)
	_number(aiming,path+".aim_max_seconds",w.aim_max_seconds,w.aim_min_seconds)
	if w.allowed_target_types.is_empty(): _add(aiming,path+".allowed_target_types","missing_targets","Allowed target types are unconfigured")
	for target: int in w.allowed_target_types:
		if target not in WeaponDefinition.TargetType.values(): _add(aiming,path+".allowed_target_types","invalid_target","Unknown target type")
	if w.moving_aim_qualification not in [0,1]: _add(aiming,path+".moving_aim_qualification","missing_qualification","Moving qualification is unconfigured")
	if w.consumption_per_projectile <= 0: _add(aiming,path+".consumption_per_projectile","invalid_consumption","Consumption must be positive")
	if w.ammo_definitions.is_empty(): _add(aiming,path+".ammo_definitions","missing_ammo","Compatible ammo is unconfigured")
	if not w.preparation_cadence and (not is_finite(w.actual_round_interval) or w.actual_round_interval <= 0): _add(combat,path+".actual_round_interval","unconfigured_cadence","Applicable rpm/actual interval is unknown; consistency is not certified")
	if w.capacity <= 0: _add(combat,path+".capacity","missing_capacity","Ready capacity must be positive")
	_number(combat,path+".preparation_seconds",w.preparation_seconds,0.0,true)
	_number(combat,path+".game_projectile_interval",w.game_projectile_interval,0.0,not w.preparation_cadence)
	if w.projectile != null: _add(combat,path+".projectile","legacy_projectile","Current scheduler rejects legacy projectiles")
	if w.spread_policy != "fixed_world_radius": _add(combat,path+".spread_policy","unsupported_spread","Current scheduler requires fixed world radius")
	_number(combat,path+".spread_radius_m",w.spread_radius_m,0.0)
	_number(combat,path+".reduction_ignore",w.reduction_ignore,0.0)
	if w.reduction_ignore > 1: _add(combat,path+".reduction_ignore","invalid_ignore","Proportion exceeds one")
	if w.indoor_qualification not in [0,1]: _add(combat,path+".indoor_qualification","missing_qualification","Indoor qualification is unconfigured")
	var ids := {}
	for i: int in w.ammo_definitions.size():
		var ammo := w.ammo_definitions[i]
		var at := path+".ammo_definitions[%d]" % i
		if ammo == null:
			_add(aiming,at,"missing_ammo_reference","Ammo reference is null")
			continue
		if ammo.ammo_id.is_empty() or ids.has(ammo.ammo_id): _add(aiming,at+".ammo_id","invalid_ammo_id","Ammo ID must be nonempty and unique")
		ids[ammo.ammo_id] = true
		# DB40: distance-selected indirect launch has no fixed DATA speed.
		if not ammo.distance_selected_launch: _number(combat,at+".initial_speed_mps",ammo.initial_speed_mps,0.0,true)
		if ammo.damage_type not in ["kinetic","chemical"]: _add(combat,at+".damage_type","invalid_damage_type","Unknown damage type")
		for field: String in ["nominal_damage","explosion_radius_m","suppression","module_damage"]:
			_number(combat,at+"."+field,float(ammo.get(field)),0.0)
		var curve_distance := ammo.anchor_distance_m if is_finite(ammo.anchor_distance_m) and ammo.anchor_distance_m > 0 else 1.0
		if not is_finite(AmmoSelection.penetration(ammo,0)) or not is_finite(AmmoSelection.penetration(ammo,curve_distance)): _add(combat,at+".penetration","missing_curve","Selector cannot evaluate penetration")

static func _inventory(issues: Array[Dictionary],allocation: WeaponAllocation,path: String) -> void:
	var ids := {}
	for ammo: AmmoDefinition in allocation.definition.ammo_definitions:
		if ammo != null: ids[ammo.ammo_id] = true
	for id: Variant in allocation.initial_inventory:
		if not id is String or not ids.has(id): _add(issues,path+".initial_inventory."+str(id),"incompatible_inventory","Inventory ammo is incompatible")
		var count: Variant = allocation.initial_inventory[id]
		if not count is int or count < 0: _add(issues,path+".initial_inventory."+str(id),"invalid_inventory","Stock must be a nonnegative integer")

static func _numeric(value: Variant) -> bool:
	return value is int or value is float

static func _number(issues: Array[Dictionary],path: String,value: float,minimum: float,strict: bool = false) -> void:
	if not is_finite(value) or value < minimum or (strict and value == minimum): _add(issues,path,"missing_or_invalid_number","Must be finite and %s %s" % [">" if strict else ">=",minimum])

static func _add(issues: Array[Dictionary],path: String,code: String,message: String) -> void:
	issues.append({"path":path,"code":code,"message":message})
