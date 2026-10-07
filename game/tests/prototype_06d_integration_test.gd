extends "res://tests/prototype_06b_test.gd"

func enable(test: Dictionary) -> void:
	test.unit.definition.protection_kinetic = 6
	test.unit.definition.protection_chemical = 6
	test.timeline.direct_hit_enabled = true
	test.timeline.suppression_enabled = true

func run() -> void:
	var test := fixture(3)
	enable(test)
	incoming(test,1.0,0.0)
	var slot: Dictionary = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
	slot.ammo_values.suppression = 240.0 # TEST ONLY threshold stimulus.
	test.weapon.fire_state.interval_remaining = 0.02
	var result: Dictionary = test.timeline.step(test.aiming)
	check(not test.timeline.halted,"actual direct-hit suppression consumer")
	check(test.unit.health == 15 and test.unit.suppression.q == 240,"zero damage effective hit adds Q")
	check(test.unit.suppression.personnel_state() == InfantrySuppressionState.PersonnelState.DISABLED,"actual disabled threshold")
	check(test.aiming.inputs[test.unit.unit_id].aim_time_multiplier == 5 and test.unit.personnel_speed_multiplier == 0.2,"real action modifiers applied")
	check(not result.emissions.is_empty(),"disabled personnel does not prohibit legal firing")
	check(not result.suppression_results.is_empty(),"actual server suppression audit output")
	check(not test.unit.snapshot().has("personnel"),"public unit snapshot never contains Q or personnel")
	check(test.unit.structure_snapshot().personnel.ratio == 1,"private own structure ratio")
	for tick: int in 360: result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and test.unit.suppression.q < 240,"real clock recovers without new hits")
	check(test.unit.suppression.personnel_state() == InfantrySuppressionState.PersonnelState.PANIC,"disabled automatically released")
	check(test.aiming.inputs[test.unit.unit_id].personnel_load_multiplier == 2,"recovery reapplies action rates")
	test.timeline.projectiles.collision.close()
	test = fixture(3)
	enable(test)
	incoming(test,1.0,100.0)
	slot = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
	slot.ammo_values.suppression = 1000.0
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and test.unit.suppression.alive_count == 2,"same attack uses post-casualty population")
	check(test.unit.suppression.q == 160 and test.unit.health == 10,"new population hard cap after damage")
	test.timeline.projectiles.collision.close()
	var manager = load("res://scripts/networking/network_manager.gd").new()
	manager._peer_players[42] = 1
	manager._peer_players[43] = 2
	test.unit.owner_player_id = 1
	manager._authoritative_units[test.unit.unit_id] = test.unit
	check(not manager._replication_arguments_for_peer("_receive_unit_structures",[[test.unit.structure_snapshot()]],42).is_empty(),"personnel projection reaches authenticated owner")
	check(manager._replication_arguments_for_peer("_receive_unit_structures",[[test.unit.structure_snapshot()]],43).is_empty(),"other client never receives private personnel projection")
	manager.free()
	# Same-step movement is resampled from the actual hit, not next tick.
	test = fixture(3)
	enable(test)
	var movement := MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	check(movement.initialize_navigation(PrototypeMapDefinition.new()),"D empty movement map initialized")
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	check(movement.request_move(test.unit.unit_id,42,Vector3(0,0,-5)) == "","D lawful straight movement")
	test.aiming.moving = func(id): return movement._targets.has(id)
	incoming(test,1.0,0.0)
	slot = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
	slot.ammo_values.suppression = 240.0
	result = test.timeline.step_movement(movement,test.aiming)
	check(not test.timeline.halted and not result.damage_results.is_empty(),"moving early suppression impact settles")
	var hit_time: float = result.damage_results[0].time_seconds
	var speed: float = test.unit.definition.speed_on(false)
	var expected := speed*(hit_time+(GravityBallistics.STEP_SECONDS-hit_time)*0.2)
	check(absf(test.unit.position.z+expected) < 0.00001,"remaining translation immediately uses disabled speed")
	check(result.motion.records[test.unit.unit_id].start_time == hit_time,"remaining collider is event-origin motion")
	var previous: Vector3 = test.unit.position
	result = test.timeline.step_movement(movement,test.aiming)
	check(not test.timeline.halted and absf(test.unit.position.distance_to(previous)-speed*GravityBallistics.STEP_SECONDS*0.2) < 0.00001,"next route step preserves task with new speed")
	test.timeline.projectiles.collision.close()
	# Retain a partially completed aim when an early hit changes its duration.
	test = fixture(3)
	enable(test)
	movement = MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	movement.initialize_navigation(PrototypeMapDefinition.new())
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	test.aiming.moving = func(id): return movement.is_moving(id)
	test.weapon.sampled_aim_seconds = 0.04
	test.weapon.aim_progress = 0.5
	test.weapon.aim_timer_complete = false
	test.weapon.is_aimed = false
	incoming(test,1.0,0.0)
	slot = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
	slot.ammo_values.suppression = 240.0
	result = test.timeline.step_movement(movement,test.aiming)
	hit_time = result.damage_results[0].time_seconds
	expected = 0.5+hit_time/0.04+(GravityBallistics.STEP_SECONDS-hit_time)/0.2
	check(not test.timeline.halted and absf(test.weapon.aim_progress-expected) < 0.000001,"aim completed fraction retained with remaining duration at new rate")
	check(result.emissions.is_empty(),"early suppression invalidates formerly ready late shot")
	test.timeline.projectiles.collision.close()
	for mechanical: bool in [false,true]:
		test = fixture(3)
		enable(test)
		test.weapon.definition.mechanical_loading = mechanical # TEST ONLY exception fixture.
		test.weapon.fire_state.loading = true
		test.weapon.fire_state.loading_progress = 0.25
		var duration: float = test.weapon.loading_seconds()
		incoming(test,1.0,0.0)
		slot = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
		slot.ammo_values.suppression = 240.0
		result = test.timeline.step(test.aiming)
		hit_time = result.damage_results[0].time_seconds
		expected = 0.25+hit_time/duration+(GravityBallistics.STEP_SECONDS-hit_time)/(duration*(1.0 if mechanical else 5.0))
		check(not test.timeline.halted and absf(test.weapon.fire_state.loading_progress-expected) < 0.000001,"remaining loading progress personnel exception "+str(mechanical))
		test.timeline.projectiles.collision.close()
	# Actual explosive projectile: several members, one full squad input.
	for lethal: bool in [false,true]:
		test = fixture(3)
		enable(test)
		test.weapon.enabled = false
		incoming(test,1.0,1000.0 if lethal else 0.0)
		slot = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
		slot.ammo_values.explosion_radius_m = 10.0 # TEST ONLY stimulus.
		slot.ammo_values.explosion_radius_squared = 100.0
		slot.ammo_values.inverse_explosion_radius_squared = 0.01
		slot.ammo_values.suppression = 150.0
		result = test.timeline.step(test.aiming)
		check(not test.timeline.halted and result.damage_results.size() == 3,"real explosion reaches three members "+str(lethal))
		check(result.suppression_inputs.size() == 1 and result.suppression_results.size() == 1,"explosion produces exactly one squad Q event")
		check(test.unit.suppression.q == (0.0 if lethal else 150.0),"explosion full amount once, dead squad receives no Q")
		var before_q: float = test.unit.suppression.q
		check(not test.timeline.direct_hits.prepare(result.settlements[0].input).ok and test.unit.suppression.q == before_q,"duplicate explosion cannot settle twice")
		test.timeline.projectiles.collision.close()
	# Waiting ends inside a movement step; integrate the two actual rates.
	test = fixture(3)
	enable(test)
	test.weapon.enabled = false
	test.timeline.suppression_runtime = InfantrySuppressionRuntime.new()
	test.timeline.suppression_runtime.begin(test.aiming,0.0)
	var recovery_input: Array[Dictionary] = [{"unit_id":test.unit.unit_id,"amount":240.0}]
	test.timeline.suppression_runtime.commit({"source_event_id":"test_only:recovery","time_seconds":0.0},[test.unit.unit_id],recovery_input,test.aiming)
	test.timeline.fire.time_seconds = 9.99
	test.timeline.projectiles.time_seconds = 9.99
	movement = MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	movement.initialize_navigation(PrototypeMapDefinition.new())
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	movement.request_move(test.unit.unit_id,42,Vector3(0,0,-5))
	test.aiming.moving = func(id): return movement.is_moving(id)
	result = test.timeline.step_movement(movement,test.aiming)
	expected = test.unit.definition.speed_on(false)*(0.01*0.2+(GravityBallistics.STEP_SECONDS-0.01)*0.5)
	check(not test.timeline.halted and absf(test.unit.position.z+expected) < 0.00001,"recovery boundary accelerates only remaining movement interval")
	check(result.changed[test.unit.unit_id] == test.unit.position,"replicated endpoint equals resampled authoritative position")
	test.timeline.projectiles.collision.close()
	# Two actual impacts in one step must use the preceding event checkpoint.
	test = fixture(3)
	enable(test)
	test.weapon.enabled = false
	movement = MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	movement.initialize_navigation(PrototypeMapDefinition.new())
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	movement.request_move(test.unit.unit_id,42,Vector3(0,0,-5))
	test.aiming.moving = func(id): return movement.is_moving(id)
	incoming(test,1.0,0.0,1)
	incoming(test,4.0,0.0,2)
	for index: int in test.timeline.projectiles.active_slots:
		test.timeline.projectiles.slots[index].ammo_values.suppression = 120.0
	result = test.timeline.step_movement(movement,test.aiming)
	check(not test.timeline.halted and result.damage_results.size() == 2,"two chronological impacts survive motion invalidation")
	var first: float = result.damage_results[0].time_seconds
	var second: float = result.damage_results[1].time_seconds
	expected = test.unit.definition.speed_on(false)*(first+(second-first)*0.5+(GravityBallistics.STEP_SECONDS-second)*0.2)
	check(absf(test.unit.position.z+expected) < 0.00001 and test.unit.suppression.q == 240,"successive panic and disabled integrate each remaining segment once")
	test.timeline.projectiles.collision.close()
	print("06D INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
