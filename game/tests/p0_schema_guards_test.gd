extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func slot(id: String,weapon: WeaponDefinition) -> WeaponSlotDefinition:
	var value := WeaponSlotDefinition.new()
	value.slot_id = id
	value.weapon = weapon
	return value

func allocate(unit: UnitDefinition,weapon: WeaponDefinition,kind: int,id: String,at: String) -> WeaponAllocation:
	var value := WeaponAllocation.new()
	value.definition = weapon
	value.node_kind = kind
	value.mount_id = id
	value.member_id = 1
	value.slot_id = at
	unit.weapon_allocations.append(value)
	return value

func vehicle() -> UnitDefinition:
	var value := UnitDefinition.new()
	value.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	return value

func state(unit: UnitDefinition) -> UnitState:
	var value := UnitState.new(1,42,Vector3.ZERO)
	value.configure(1,unit)
	return value

func has_code(result: Dictionary,code: String,path: String = "") -> bool:
	for issue: Dictionary in result.errors:
		if issue.code == code and (path.is_empty() or issue.path == path): return true
	return false

func run() -> void:
	var weapon := WeaponDefinition.new()
	weapon.definition_id = "test_only:occupancy"
	var unit := vehicle()
	unit.hull_weapon_slots.append(slot("primary",weapon))
	check(unit.weapon_allocations_valid() and state(unit).runtime_weapons.size() == 1,"A07 slot only creates exactly one")
	unit = vehicle()
	allocate(unit,weapon,WeaponAllocation.NodeKind.HULL,"","primary")
	check(unit.weapon_allocations_valid() and state(unit).runtime_weapons.size() == 1,"A07 allocation only creates exactly one")
	unit.hull_weapon_slots.append(slot("secondary",weapon))
	check(unit.weapon_allocations_valid() and state(unit).runtime_weapons.size() == 2,"A07 distinct Hull slots coexist")
	unit.hull_weapon_slots[0].slot_id = "primary"
	var allocation := unit.weapon_allocations[0]
	allocation.mount_id = "cannot-hide-hull"
	check(not unit.weapon_allocations_valid(),"A07 Hull ID normalizes before collision check")
	var rejected := state(unit)
	check(rejected.runtime_weapons.is_empty() and rejected.armament_configuration_reason == "invalid_weapon_allocations","A07 collision rejects before ANY weapon creation")
	var result := UnitDefinitionValidator.validate_unit_definition(unit)
	check(has_code(result,"installation_collision","weapon_allocations[0]"),"A07 structured location")
	var issue: Dictionary = unit.installation_issues()[0]
	check(issue.related_path == "hull_weapon_slots[0]" and issue.installation[1] == "hull","A07 both sources and physical installation reported")
	unit = vehicle()
	for id: String in ["turretA","turretB"]:
		var mount := WeaponMountDefinition.new()
		mount.mount_id = id
		mount.weapon_slots.append(slot("primary",weapon))
		unit.mounts.append(mount)
	allocate(unit,weapon,WeaponAllocation.NodeKind.MOUNT,"turretA","coax")
	allocate(unit,weapon,WeaponAllocation.NodeKind.HULL,"","primary")
	check(unit.weapon_allocations_valid() and state(unit).runtime_weapons.size() == 4,"A07 multiple mounts slots and Hull remain independent")
	unit.weapon_allocations[0].slot_id = "primary"
	check(not unit.weapon_allocations_valid() and state(unit).runtime_weapons.is_empty(),"A07 mount slot/allocation collision rejects")
	unit = vehicle()
	unit.hull_weapon_slots.append(slot("empty",null))
	allocate(unit,weapon,WeaponAllocation.NodeKind.HULL,"","empty")
	check(unit.weapon_allocations_valid() and state(unit).runtime_weapons.size() == 1,"A07 empty declared slot does not equip twice")
	unit.hull_weapon_slots.append(slot("empty",weapon))
	unit.weapon_allocations[0].occupied_slots.assign(["other"])
	check(not unit.weapon_allocations_valid(),"A07 occupied_slots cannot conceal actual instance slot")
	unit = vehicle()
	unit.hull_weapon_slots.append(slot("dup",weapon))
	unit.hull_weapon_slots.append(slot("dup",weapon))
	check(not unit.weapon_allocations_valid(),"A07 duplicate slot-owned weapons reject")
	unit = vehicle()
	allocate(unit,weapon,WeaponAllocation.NodeKind.HULL,"","same")
	allocate(unit,weapon,WeaponAllocation.NodeKind.HULL,"another","same")
	check(not unit.weapon_allocations_valid(),"A07 allocation/allocation collision uses normalized Hull")
	unit = vehicle()
	var first := WeaponMountDefinition.new()
	first.mount_id = "a/b"
	first.weapon_slots.append(slot("c",weapon))
	var second := WeaponMountDefinition.new()
	second.mount_id = "a"
	second.weapon_slots.append(slot("b/c",weapon))
	unit.mounts.assign([first,second])
	check(unit.weapon_allocations_valid(),"A07 delimiter in IDs cannot create a false collision")
	var data := ConfirmedGameData.new()
	for row: Dictionary in data.records.Weapons:
		check(data.weapon_validation_issues(row.Weapon_ID).is_empty() and data.weapon(row.Weapon_ID) != null,"A10 existing DATA unchanged "+row.Weapon_ID)
	var cadence := data.weapon("W_M4A1")
	check(is_equal_approx(cadence.actual_round_interval,60.0/25.0) and is_equal_approx(cadence.game_projectile_interval,3.0*cadence.actual_round_interval),"A10 rpm counts actual ammo")
	cadence.game_projectile_interval += 1e-10
	check(cadence.cadence_issues().is_empty(),"A10 arithmetic error tolerated")
	cadence.game_projectile_interval += 0.1
	check(not cadence.cadence_issues().is_empty(),"A10 conflict detected")
	cadence.mechanical_loading = true
	check(not cadence.cadence_issues().is_empty(),"A10 mechanical loading is no exemption")
	cadence.preparation_cadence = true
	check(cadence.cadence_issues().is_empty(),"A10 dedicated preparation cadence exempt")
	for id: String in ["W_AT4","W_CG"]:
		check(data.weapon(id).preparation_cadence and data.weapon_validation_issues(id).is_empty(),"A10 DATA preparation exemption "+id)
	var runtime := state(GeneratedCombatCatalog.squad()).runtime_weapons[1]
	check(is_equal_approx(runtime.shot_interval(),runtime.definition.game_projectile_interval/runtime.configured_count),"A10 fixed N applied once by runtime")
	var before := runtime.shot_interval()
	runtime.inventory.clear()
	check(runtime.shot_interval() == before,"A10 interval does not depend on stock")
	for row: Dictionary in data.records.Weapons:
		if row.Weapon_ID == "W_M4A1": row.Single_Weapon_Projectile_Interval_s = 8.0
	check(data.weapon("W_M4A1") == null,"A10 conflicting DATA cannot be adapted")
	check(data.weapon_validation_issues("W_M4A1")[0].path == "Weapons.W_M4A1.Single_Weapon_Projectile_Interval_s","A10 source column diagnostic")
	unit = UnitDefinition.new()
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.TEST)
	check(result.valid and result.structure_valid and not result.implemented_combat_ready,"A12 incomplete fixture allowed for structural tests only")
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.COMPLETE)
	check(not result.valid and has_code(result,"missing_or_invalid_number","protection_kinetic"),"A12 complete level identifies missing current fields")
	unit = GeneratedCombatCatalog.squad()
	# Only this new complete-contract test input: no fixture/DATA rewrite.
	for item: WeaponAllocation in unit.weapon_allocations: item.definition.indoor_qualification = 0
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.COMPLETE)
	if not result.implemented_combat_ready: print("Covered-contract diagnostics: ",result.combat_issues)
	check(result.structure_valid and result.partial_test_ready and result.implemented_combat_ready,"A12 complete implemented combat fixture passes covered contract")
	check(not result.valid and not result.formal_catalog_ready and not result.full_combat_ready,"A12 test success never becomes formal/full combat certification")
	check(has_code(result,"test_configuration","configuration_source") and has_code(result,"unsupported_rule_coverage"),"A12 explicit temporary provenance and unsupported coverage")
	unit.configuration_source = "confirmed-looking-label"
	for item: WeaponAllocation in unit.weapon_allocations: item.definition.temporary_fields.clear()
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.COMPLETE)
	check(not result.formal_catalog_ready and has_code(result,"unsupported_rule_coverage"),"A12 relabeling cannot bypass missing schema coverage")
	unit.weapon_allocations[0].definition.aim_min_seconds = NAN
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.PARTIAL)
	check(not result.valid and has_code(result,"missing_or_invalid_number","weapon_allocations[0].definition.aim_min_seconds"),"A12 partial aiming scope reports field")
	check(UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.TEST).valid,"A12 partial fixture still usable for unrelated structural tests")
	unit.weapon_allocations[0].initial_inventory["unknown_ammo"] = 1
	result = UnitDefinitionValidator.validate_unit_definition(unit)
	check(not result.valid and has_code(result,"incompatible_inventory","weapon_allocations[0].initial_inventory.unknown_ammo"),"A12 incompatible ammo reference fails structural validation")
	check(not UnitDefinitionValidator.validate_unit_definition(null).valid,"A12 null definition rejected")
	check(not UnitDefinitionValidator.validate_unit_definition(UnitDefinition.new(),99).valid,"A12 unknown level rejected")
	unit = GeneratedCombatCatalog.mortar()
	unit.weapon_allocations[0].definition.indoor_qualification = 0 # Local test qualification only.
	unit.weapon_allocations[0].definition.moving_aim_qualification = 0
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.COMPLETE)
	check(result.implemented_combat_ready,"A12 DB40 indirect ammo fixed speed is not applicable")
	var mortar := unit.weapon_allocations[0].definition.ammo_definitions[0]
	check(mortar.distance_selected_launch and is_nan(mortar.initial_speed_mps),"A12 indirect readiness never fabricates a fixed DATA speed")
	unit.weapon_allocations[0].definition.actual_round_interval = NAN
	result = UnitDefinitionValidator.validate_unit_definition(unit,UnitDefinitionValidator.Level.COMPLETE)
	check(not result.implemented_combat_ready and has_code(result,"unconfigured_cadence","weapon_allocations[0].definition.actual_round_interval"),"A12 unknown cadence never certified complete")
	check(UnitDefinitionValidator.validate_unit_definition(unit).valid,"A12 unknown cadence retained for structural fixture")
	unit.weapon_allocations[0].member_id = 999
	check(has_code(UnitDefinitionValidator.validate_unit_definition(unit),"invalid_member_reference","weapon_allocations[0].member_id"),"A12 member reference diagnostic")
	unit.weapon_allocations[0].definition = null
	check(has_code(UnitDefinitionValidator.validate_unit_definition(unit),"missing_weapon_reference","weapon_allocations[0].definition"),"A12 missing weapon reference diagnostic")
	weapon.actual_round_interval = 0.2
	weapon.game_projectile_interval = 0.4
	weapon.consumption_per_projectile = 1
	var guarded := vehicle()
	allocate(guarded,weapon,WeaponAllocation.NodeKind.HULL,"","primary")
	var guarded_state := state(guarded)
	var enemy := state(UnitDefinition.new())
	enemy.unit_id = 2
	enemy.team_id = 2
	enemy.position = Vector3(0,0,-10)
	var firing := guarded_state.runtime_weapons[0]
	weapon.range_m = 100
	weapon.aim_min_seconds = 0
	weapon.aim_max_seconds = 0
	weapon.allowed_target_types.assign([WeaponDefinition.TargetType.INFANTRY])
	weapon.moving_aim_qualification = 0
	weapon.capacity = 10
	weapon.preparation_seconds = 3
	var ammo := AmmoDefinition.new()
	ammo.ammo_id = "test_only:guard"
	weapon.ammo_definitions.append(ammo)
	firing.inventory[ammo.ammo_id] = 10
	firing.bind_target(AttackTarget.unit(enemy))
	var aiming := AimingSimulation.new()
	aiming.units = {1:guarded_state,2:enemy}
	aiming.visibility = func(_owner,_target): return true
	aiming.clear_path = func(_from,_to): return true
	aiming.moving = func(_id): return false
	aiming.advance(1)
	check(FixedFireScheduler._eligibility(firing,aiming) == "cadence_configuration_invalid","A10 direct runtime definition mutation refused")
	check(firing.inventory[ammo.ammo_id] == 10,"A10 runtime cadence refusal never debits stock")
	var catalog := load("res://data/prototype_deployment.tres") as DeploymentConfig
	# Use the same existing valid deployment inputs; never rewrite a fixture.
	if catalog == null:
		check(false,"A12 expected deployment resource available")
	else:
		var movement := load("res://data/prototype_movement.tres") as MovementConfig
		var map := load("res://data/prototype_map.tres") as PrototypeMapDefinition
		check(movement != null and map != null,"A12 expected map/movement fixtures available")
		if movement != null and map != null:
			var economy := DeploymentEconomy.new()
			check(economy.initialize(catalog,movement,map,60).is_empty(),"A12 existing test directory initializes")
			var formal := catalog.duplicate(true) as DeploymentConfig
			formal.temporary_test_values = false
			check(not DeploymentEconomy.new().initialize(formal,movement,map,60).is_empty(),"A12 partial test catalog cannot deploy as formal")
	print("P0 schema guards: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
