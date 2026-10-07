extends "res://tests/db29_combat_timeline_test.gd"

func incoming(test: Dictionary,at_distance: float,damage: float = 100.0,order: int = 1) -> void:
	var ammo := data.ammunition("A_556")
	ammo.nominal_damage = damage # TEST ONLY incoming round, never formal DATA.
	ammo.ammo_id = "test_only:06b_incoming_round"
	var event := {"event_id":"test_only:06b_incoming:%s" % order,"emission_order":order,"time_seconds":0.0,
		"unit_id":test.target.unit_id,"owner_player_id":43,"weapon_instance_id":"test_only:06b_weapon",
		"position":Vector3(0,0,-at_distance),"velocity":Vector3(0,0,ammo.initial_speed_mps),"ammo":ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var motion := ProjectileUnitMotion.new()
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(0.0,snapshots,snapshots)
	var flight := OrderedProjectileStep.new()
	flight.begin(test.timeline.projectiles,motion)
	flight.spawn(event)
	test.timeline.fire.emission_order = order

func run() -> void:
	var formal := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var frozen := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var ammo := data.ammunition("A_556")
	var values := ProjectileSettlementInput.ammunition(ammo)
	for distance: float in [0.0,100.0,1000.0,100000.0]:
		check(is_equal_approx(ImpactDamageRules.penetration(values,distance),AmmoSelection.penetration(ammo,distance)),"cached confirmed kinetic curve and floor at "+str(distance))
	var chemical := {"damage_type":"chemical","anchor_penetration":5.0,"nominal_damage":10.0}
	check(ImpactDamageRules.damage(chemical,100.0,50.0,[],0.0).damage == 0,"chemical lower endpoint inclusive")
	check(ImpactDamageRules.damage(chemical,100.0,5.0,[],0.0).damage == 5,"chemical square ratio")
	chemical.anchor_penetration = 50.0
	check(ImpactDamageRules.damage(chemical,1000.0,5.0,[],0.0).damage == 10,"chemical upper endpoint inclusive and no distance decay")
	check(ImpactDamageRules.damage(values,0.0,5.0,[],0.0).damage == ammo.nominal_damage,"kinetic overpenetration never extra damage or triplet multiplication")
	var full: float = ImpactDamageRules.damage(values,0.0,5.0,[],0.0).damage
	check(is_equal_approx(ImpactDamageRules.damage(values,0.0,5.0,[0.2,0.5],0.2).damage,full*0.6),"maximum cover with ignore after armor")
	check(not ImpactDamageRules.damage(values,0.0,4.0,[],0.0).ok,"invalid armor rejected")
	check(not ImpactDamageRules.damage(values,0.0,5.0,[],NAN).ok,"unknown ignore rejected")
	check(not ImpactDamageRules.damage(values,0.0,5.0,[1.1],0.0).ok,"invalid cover rejected")
	var unknown := values.duplicate(true)
	unknown.confirmed_decay_coefficient = null
	check(not ImpactDamageRules.damage(unknown,0.0,5.0,[],0.0).ok,"missing curve never fallback temporary curve")
	check(ImpactDamageRules.face(Vector3(0,0,1),Vector3.FORWARD,0,false) == "front","front incoming direction")
	check(ImpactDamageRules.face(Vector3(0,0,-1),Vector3.BACK,0,false) == "rear","rear incoming direction")
	check(ImpactDamageRules.face(Vector3.RIGHT,Vector3.LEFT,0,false) == "side","side incoming direction")
	check(ImpactDamageRules.face(Vector3(0,0,-1),Vector3.UP,0,false) == "top","actual top before rear")
	check(ImpactDamageRules.face(Vector3(0,0,-1),Vector3.BACK,0,true) == "top","confirmed attack-top tag priority")
	check(ImpactDamageRules.face(Vector3(0,0,1),Vector3.FORWARD,PI,false) == "rear","actual hull orientation")
	var test := fixture(3)
	var unit: UnitState = test.unit
	var positions := {1:Vector3(-1,0,0),2:Vector3(1,0,0),3:Vector3(0,0,4)}
	check(ImpactDamageRules.nearest(unit,Vector3(0.9,0,0),positions) == 2,"nearest living logical member")
	check(ImpactDamageRules.nearest(unit,Vector3.ZERO,positions) == 1,"equal squared distance uses stable member ID")
	var carried_ammo: String = test.weapon.definition.ammo_definitions[0].ammo_id
	var stock: int = test.weapon.inventory[carried_ammo]
	var updates: int = unit.squad_channels.profile.events
	var result := unit.apply_member_damage(2,1.5)
	check(result.ok and unit.members[1].health == 3.5 and unit.health == 13.5,"single-member fractional damage and derived total")
	check(unit.squad_channels.profile.events == updates and test.weapon.operable_count == 3,"living residual health has no personnel efficiency event")
	check(not unit.apply_member_damage(999,5).ok and not unit.apply_member_damage(2,-1).ok and not unit.apply_member_damage(2,NAN).ok,"invalid explicit member input causes no damage")
	result = unit.apply_member_damage(2,100)
	check(result.member_died and result.damage_applied == 3.5 and unit.members[0].health == 5 and unit.members[2].health == 5,"excess never spills to survivors")
	check(unit.squad_channels.profile.events == updates+1 and test.weapon.configured_count == 3 and test.weapon.operable_count == 2,"death event updates operators without changing fixed N")
	check(test.weapon.inventory[carried_ammo] == stock-data.initial_inventory_for_weapon("W_M249").inventory[carried_ammo],"one dead carrier inventory removed once")
	check(not unit.apply_member_damage(2,100).ok and unit.squad_channels.profile.events == updates+1,"dead member cannot lose stock twice")
	check(ImpactDamageRules.nearest(unit,positions[2],positions) != 2,"dead nearest candidate excluded")
	test.timeline.projectiles.collision.close()
	for early: bool in [true,false]:
		test = fixture(1)
		test.unit.definition.protection_kinetic = 6 # TEST ONLY missing source protection.
		test.unit.definition.protection_chemical = 6
		test.weapon.fire_state.interval_remaining = 0.01
		test.timeline.direct_hit_enabled = true
		incoming(test,5.0 if early else 18.0)
		result = test.timeline.step(test.aiming)
		check(not test.timeline.halted,"real ordered damage step")
		check(result.damage_results.size() == 1 and result.damage_results[0].unit_died,"real projectile kills one-member unit")
		check(result.emissions.size() == (0 if early else 1),"early death forbids late emission; late death preserves earlier shot")
		check(test.unit.health == 0 and test.timeline.projectiles.time_seconds == test.timeline.fire.time_seconds,"death and clocks authoritative")
		check(result.damage_results[0].source_player_id == 43 and result.damage_results[0].member_id == 1,"server-only fixed attribution and actual member result")
		test.timeline.projectiles.collision.close()
	# Event-time sampling differs from step-end nearest, without hidden hit chance.
	test = fixture(3)
	test.unit.definition.protection_kinetic = 6
	test.unit.definition.protection_chemical = 6
	test.timeline.direct_hit_enabled = true
	incoming(test,5.0)
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and result.damage_results.size() >= 1 and result.damage_results[0].member_died and not result.damage_results[0].unit_died,"surviving squad casualty refreshes geometry rather than halting")
	check(test.unit.health == 10 and test.weapon.configured_count == 3 and test.weapon.operable_count == 2,"survivors and fixed channel count retained")
	check(test.unit.squad_channels.all_inventory_issues().is_empty(),"casualty and earlier shot preserve source/pending inventory accounting")
	test.timeline.projectiles.collision.close()
	# Actual vehicle impact uses event hull orientation and exactly one hull damage.
	test = fixture(3)
	test.unit.definition.protection_kinetic = 6
	test.unit.definition.protection_chemical = 6
	test.timeline.direct_hit_enabled = true
	test.weapon.enabled = false
	incoming(test,5.0,100.0,1)
	incoming(test,8.0,100.0,2)
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and result.damage_results.size() == 2,"two actual casualties share a step with refreshed collision geometry")
	check(result.damage_results[0].member_id != result.damage_results[1].member_id and test.unit.health == 5,"subsequent impact excludes already-dead nearest member")
	check(test.unit.squad_channels.profile.events == 2,"each actual death delivers one personnel event")
	check(not test.timeline.direct_hits.prepare(result.settlements[0].input).ok,"committed emission cannot prepare a second damage side effect")
	var saved_results: Array = result.damage_results
	test.timeline.step(test.aiming)
	check(saved_results.size() == 2 and test.timeline.direct_hits.records.size() == 2,"next step preserves previous returned results and internal actual-decision record")
	test.timeline.projectiles.collision.close()
	# Active shared movement/aim sample survives a partial casualty and next step.
	test = fixture(3)
	test.unit.definition.protection_kinetic = 6
	test.unit.definition.protection_chemical = 6
	test.timeline.direct_hit_enabled = true
	var movement := MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	check(movement.initialize_navigation(PrototypeMapDefinition.new()),"B isolated moving map initialized")
	movement.add_unit(test.unit)
	movement.add_unit(test.target)
	check(movement.request_move(test.unit.unit_id,42,Vector3(5,0,0)) == "","B source receives lawful movement")
	test.aiming.moving = func(id): return movement._targets.has(id)
	incoming(test,5.0)
	result = test.timeline.step_movement(movement,test.aiming)
	check(not test.timeline.halted and result.damage_results.size() == 1 and test.unit.health == 10,"moving squad casualty uses actual shared sample")
	check(result.motion.records[test.unit.unit_id].start_time > 0 and result.motion.ready,"remaining motion has explicit event-time origin")
	result = test.timeline.step_movement(movement,test.aiming)
	check(not test.timeline.halted and result.motion.ready,"next movement step remains consistent after casualty refresh")
	test.aiming.moving = Callable()
	test.timeline.projectiles.collision.close()
	# Actual vehicle impact uses event hull orientation and exactly one hull damage.
	test = fixture(1)
	test.weapon.enabled = false
	var vehicle_definition := UnitDefinition.new()
	vehicle_definition.configuration_source = "test_only:06b_vehicle"
	vehicle_definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	vehicle_definition.maximum_health = 10
	vehicle_definition.kinetic_armor_by_face = {"front":10.0,"side":20.0,"rear":30.0,"top":40.0}
	vehicle_definition.chemical_armor_by_face = {"front":10.0,"side":20.0,"rear":30.0,"top":40.0}
	test.target.configure(2,vehicle_definition)
	test.target.yaw = PI # Incoming from +Z becomes front after actual rotation.
	var motion := ProjectileUnitMotion.new()
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(0.0,snapshots,snapshots)
	var projectile := {"event_id":"test_only:06b_vehicle_shot","emission_order":1,"time_seconds":0.0,
		"unit_id":test.unit.unit_id,"owner_player_id":42,"weapon_instance_id":"test_only:06b_vehicle_weapon",
		"position":Vector3.ZERO,"velocity":Vector3(0,0,-ammo.initial_speed_mps),"ammo":ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var flight := OrderedProjectileStep.new()
	flight.begin(test.timeline.projectiles,motion)
	flight.spawn(projectile)
	test.timeline.fire.emission_order = 1
	test.timeline.direct_hit_enabled = true
	result = test.timeline.step(test.aiming,motion)
	check(not test.timeline.halted and result.damage_results.size() == 1,"real direct vehicle settlement")
	check(result.damage_results[0].face == "front" and result.damage_results[0].armor == 10,"impact-time face selects directional armor")
	check(result.damage_results[0].member_id == 0 and test.target.health < 10 and test.target.health > 0,"single hull HP update")
	check(ProjectileProjection.terminal(result.events.back()).size() == 4,"damage and weapon snapshots remain outside public terminal")
	test.timeline.projectiles.collision.close()
	# Event-time sampling differs from step-end nearest, without hidden hit chance.
	test = fixture(2)
	var frame := FiringFrame.new()
	frame.begin(0.0,test.aiming,true)
	test.unit.members[0].position = Vector3(100,0,0)
	test.unit.members[1].position = Vector3.ZERO
	frame.finish(test.aiming,null)
	check(frame.member_positions(test.unit.unit_id,0.0)[1] != frame.member_positions(test.unit.unit_id,GravityBallistics.STEP_SECONDS)[1],"member trajectory retains true start/end")
	var start_positions := frame.member_positions(test.unit.unit_id,0.0)
	check(ImpactDamageRules.nearest(test.unit,start_positions[1],start_positions) == 1 and ImpactDamageRules.nearest(test.unit,start_positions[1],frame.member_positions(test.unit.unit_id,GravityBallistics.STEP_SECONDS)) == 2,"member selected at impact rather than step end")
	test.timeline.projectiles.collision.close()
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == formal,"formal DATA unchanged")
	check(FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == frozen,"frozen v1 unchanged")
	print("Prototype 0.6B: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
