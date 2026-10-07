extends "res://tests/prototype_06b_test.gd"

func vehicle_fixture(mounted: bool = false) -> Dictionary:
	var test := fixture(1)
	var definition: UnitDefinition = test.unit.definition.duplicate(true)
	definition.configuration_source = "test_only:06e_vehicle"
	definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	definition.maximum_health = 1000
	definition.member_count = 0
	definition.kinetic_armor_by_face = {"front":5.0,"side":5.0,"rear":5.0,"top":5.0}
	definition.chemical_armor_by_face = definition.kinetic_armor_by_face.duplicate()
	definition.hardened_speed = 4.0
	definition.unhardened_speed = 4.0
	definition.hardened_reverse_speed = 1.0
	definition.unhardened_reverse_speed = 1.0
	definition.hitbox_half_extents = Vector3(0.3,0.3,0.3)
	definition.movement_radius = 0.3
	var allocation := WeaponAllocation.new()
	allocation.definition = test.weapon.definition
	allocation.node_kind = WeaponAllocation.NodeKind.HULL
	if mounted:
		var mount := WeaponMountDefinition.new()
		mount.mount_id = "test_only:turret"
		definition.mounts.clear()
		definition.mounts.append(mount)
		allocation.node_kind = WeaponAllocation.NodeKind.MOUNT
		allocation.mount_id = mount.mount_id
	allocation.slot_id = "test_only:hull"
	allocation.initial_inventory = test.weapon.inventory.duplicate()
	definition.weapon_allocations.clear()
	definition.weapon_allocations.append(allocation)
	test.unit.configure(1,definition)
	test.weapon = test.unit.runtime_weapons[0]
	test.weapon.bind_target(AttackTarget.unit(test.target),true)
	test.weapon.sampled_aim_seconds = 0.04
	test.weapon.aim_progress = 1.0
	test.weapon.aim_timer_complete = true
	test.timeline.direct_hit_enabled = true
	test.timeline.modules_enabled = true
	test.timeline.module_runtime = VehicleModuleRuntime.new()
	test.timeline.module_runtime.random.seed = 123 # TEST ONLY reproducible server stream.
	test.timeline.module_runtime.begin(test.aiming)
	return test

func shot(test: Dictionary,amount: float = 200) -> void:
	incoming(test,1.0,0.0)
	var index: int = test.timeline.projectiles.active_slots[0]
	test.timeline.projectiles.slots[index].ammo_values.module_damage = amount

func movement_for(test: Dictionary,reverse: bool = false) -> MovementSimulation:
	var movement := MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	movement.initialize_navigation(PrototypeMapDefinition.new())
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	check(movement.request_move(test.unit.unit_id,42,Vector3(0,0,5 if reverse else -5),MovementSimulation.MoveMode.REVERSE if reverse else MovementSimulation.MoveMode.BASIC) == "","vehicle legal movement")
	test.aiming.moving = func(id): return movement.is_moving(id)
	return movement

func run() -> void:
	for reverse: bool in [false,true]:
		var test := vehicle_fixture()
		test.weapon.enabled = false
		test.unit.vehicle_modules.levels.assign([2,2,2,0])
		test.timeline.module_runtime.apply_modifiers(test.unit,test.aiming)
		var movement := movement_for(test,reverse)
		shot(test)
		var result: Dictionary = test.timeline.step_movement(movement,test.aiming)
		check(not test.timeline.halted and result.module_results.size() == 1,"actual vehicle impact commits modules")
		if test.timeline.halted or result.damage_results.is_empty():
			push_error(test.timeline.failure_reason)
			quit(1)
			return
		var at: float = result.damage_results[0].time_seconds
		var speed := 1.0 if reverse else 4.0
		var distance := speed*(at+(GravityBallistics.STEP_SECONDS-at)*0.2)
		check(absf(test.unit.position.z-distance*(1.0 if reverse else -1.0)) < 0.00001,"remaining forward/reverse motion uses mobility factor")
		check(test.unit.vehicle_modules.levels == [2,2,2,2] and test.unit.vehicle_modules.amount == 0,"last two levels reach eight-level limit")
		check(result.module_results[0].upgrades.size() == 2 and result.module_results[0].upgrades[0].module == VehicleModuleState.Module.MOBILITY,"actual chosen results internally recorded")
		check(not test.unit.snapshot().has("modules") and test.unit.structure_snapshot().modules == [2,2,2,2],"module grades only in private structure")
		check(not test.timeline.direct_hits.prepare(result.settlements[0].input).ok,"duplicate impact rejected")
		test.timeline.projectiles.collision.close()
	for mechanical: bool in [false,true]:
		var test := vehicle_fixture()
		test.unit.vehicle_modules.levels.assign([2,2,0,2])
		test.timeline.module_runtime.apply_modifiers(test.unit,test.aiming)
		test.weapon.definition.mechanical_loading = mechanical # TEST ONLY loading exception.
		test.weapon.fire_state.loading = true
		test.weapon.fire_state.loading_progress = 0.25
		var duration: float = test.weapon.loading_seconds()
		shot(test)
		var result: Dictionary = test.timeline.step(test.aiming)
		var at: float = result.damage_results[0].time_seconds
		var personnel := 1.0 if mechanical else 5.0
		var expected := 0.25+at/(duration*personnel)+(GravityBallistics.STEP_SECONDS-at)/(duration*personnel*5.0)
		check(not test.timeline.halted and absf(test.weapon.fire_state.loading_progress-expected) < 0.000001,"loading preserves fraction, mechanical skips personnel "+str(mechanical))
		test.timeline.projectiles.collision.close()
	var test := vehicle_fixture()
	test.unit.vehicle_modules.levels.assign([0,2,2,2])
	test.timeline.module_runtime.apply_modifiers(test.unit,test.aiming)
	test.weapon.aim_progress = 0.5
	test.weapon.aim_timer_complete = false
	var movement := movement_for(test)
	movement.request_stop([test.unit.unit_id],42)
	shot(test)
	var result: Dictionary = test.timeline.step_movement(movement,test.aiming)
	var at: float = result.damage_results[0].time_seconds
	var expected := 0.5+at/(0.04*5.0)+(GravityBallistics.STEP_SECONDS-at)/(0.04*25.0)
	check(not test.timeline.halted and absf(test.weapon.aim_progress-expected) < 0.000001,"hull aim remaining interval uses optics/personnel product")
	check(result.emissions.is_empty(),"not-yet-aimed vehicle cannot emit early")
	check(test.timeline.module_runtime.repair_level_completed(test.unit.unit_id,VehicleModuleState.Module.OPTICS,test.aiming),"actual completed single repair interface")
	check(test.aiming.inputs[test.unit.unit_id].aim_time_multiplier == 10 and test.unit.vehicle_modules.amount == 0,"repair reapplies factors and clears shared meter")
	test.timeline.projectiles.collision.close()
	test = vehicle_fixture()
	test.unit.vehicle_modules.levels.assign([2,0,2,2])
	test.timeline.module_runtime.apply_modifiers(test.unit,test.aiming)
	test.weapon.fire_state.interval_remaining = 0.02
	shot(test)
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and not result.emissions.is_empty() and test.weapon.aim_progress == 1,"heavy personnel preserves completed aim and allows legal firing")
	check(test.unit.vehicle_modules.levels[VehicleModuleState.Module.PERSONNEL] == 2 and test.aiming.inputs[test.unit.unit_id].spread_multiplier == 5,"vehicle personnel affects spread without infantry Q")
	check(test.unit.suppression == null,"vehicle never gains infantry suppression state")
	test.timeline.projectiles.collision.close()
	test = vehicle_fixture()
	test.weapon.enabled = false
	test.weapon.target = null
	shot(test)
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and result.module_results.size() == 1,"unassigned vehicle weapon survives module refresh")
	test.timeline.projectiles.collision.close()
	test = vehicle_fixture()
	test.weapon.enabled = false
	shot(test,0)
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and result.module_results.is_empty() and test.unit.vehicle_modules.amount == 0,"zero destruction does not add module damage")
	test.timeline.projectiles.collision.close()
	test = vehicle_fixture()
	test.weapon.enabled = false
	shot(test)
	var slot_index: int = test.timeline.projectiles.active_slots[0]
	test.timeline.projectiles.slots[slot_index].ammo_values.module_damage = null
	result = test.timeline.step(test.aiming)
	check(test.timeline.halted and test.unit.health == 1000 and test.unit.vehicle_modules.amount == 0,"unknown module configuration rejects before life or module mutation")
	test.timeline.projectiles.collision.close()
	test = vehicle_fixture(true)
	test.unit.vehicle_modules.levels.assign([0,2,2,2])
	test.timeline.module_runtime.apply_modifiers(test.unit,test.aiming)
	test.weapon.aim_progress = 0.5
	test.weapon.aim_timer_complete = false
	movement = movement_for(test)
	movement.request_stop([test.unit.unit_id],42)
	shot(test)
	result = test.timeline.step_movement(movement,test.aiming)
	at = result.damage_results[0].time_seconds
	expected = 0.5+at/(0.04*5.0)+(GravityBallistics.STEP_SECONDS-at)/(0.04*25.0)
	check(not test.timeline.halted and absf(test.weapon.aim_progress-expected) < 0.000001,"turret aim preserves fraction through optics upgrade")
	check(result.emissions.is_empty() and test.unit.mounts.size() == 1,"turret never fires before new aim completion")
	test.timeline.projectiles.collision.close()
	print("06E INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
