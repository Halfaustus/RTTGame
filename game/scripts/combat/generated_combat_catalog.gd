class_name GeneratedCombatCatalog
extends RefCounted

# Authorized development units only. No formal INF/vehicle configurations.
static func squad() -> UnitDefinition:
	var data := ConfirmedGameData.new()
	var unit := UnitDefinition.new()
	unit.configuration_source = "test_only:db33_active_generated"
	unit.resource_name = "test_only_db33_active_generated"
	unit.member_count = 4
	unit.maximum_health = 20
	unit.turn_speed_degrees = 360
	unit.member_aim_speed_degrees = 360
	unit.protection_kinetic = 6
	unit.protection_chemical = 6
	for i in range(4):
		var weapon := data.weapon("W_M249" if i == 0 else "W_M4A1")
		# Only missing-instance fields; confirmed performance remains untouched.
		if weapon.required_operators < 0: weapon.required_operators = 1
		if not is_finite(weapon.aim_min_seconds): weapon.aim_min_seconds = 0.1
		if not is_finite(weapon.aim_max_seconds): weapon.aim_max_seconds = 0.1
		weapon.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY,WeaponDefinition.TargetType.GROUND_VEHICLE]
		weapon.reduction_ignore = 0
		weapon.spread_radius_m = 0.15
		weapon.temporary_fields.assign(["test_only:operators_if_missing","test_only:aim_if_missing","test_only:attack_types","test_only:ignore","test_only:spread"])
		# Same model shares a single definition, as required by the channel contract.
		if i > 1: weapon = unit.weapon_allocations[1].definition
		var allocation := WeaponAllocation.new()
		allocation.definition = weapon
		allocation.member_id = i+1
		allocation.retention_priority = 0 if weapon.squad_weapon else 1
		for ammo: AmmoDefinition in weapon.ammo_definitions:
			allocation.initial_inventory[ammo.ammo_id] = int(data.number(data.record("Ammo",ammo.ammo_id),"Initial_Inventory_rounds"))
		unit.weapon_allocations.append(allocation)
	return unit

static func mortar() -> UnitDefinition:
	var data := ConfirmedGameData.new()
	var unit := UnitDefinition.new()
	unit.configuration_source = "test_only:db33_active_mortar"
	unit.resource_name = "test_only_db33_active_mortar"
	unit.member_count = 3
	unit.maximum_health = 15
	unit.protection_kinetic = 6
	unit.protection_chemical = 6
	var weapon := data.weapon("W_M252")
	weapon.aim_min_seconds = 0.1
	weapon.aim_max_seconds = 0.1
	weapon.capacity = 1 # Missing DATA field; authorized isolated test value.
	weapon.preparation_seconds = 4 # Missing DATA field; not formal reload time.
	weapon.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY,WeaponDefinition.TargetType.GROUND_VEHICLE]
	weapon.reduction_ignore = 0
	weapon.spread_radius_m = 0.15
	weapon.temporary_fields.assign(["test_only:aim","test_only:capacity","test_only:reload","test_only:attack_types","test_only:ignore","test_only:spread"])
	var allocation := WeaponAllocation.new()
	allocation.definition = weapon
	allocation.member_id = 1
	allocation.retention_priority = 0
	for ammo: AmmoDefinition in weapon.ammo_definitions:
		allocation.initial_inventory[ammo.ammo_id] = int(data.number(data.record("Ammo",ammo.ammo_id),"Initial_Inventory_rounds"))
	unit.weapon_allocations.append(allocation) # One mortar N=1, three operators.
	return unit
