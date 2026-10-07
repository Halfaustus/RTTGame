extends "res://tests/db29_combat_timeline_test.gd"

func blast(radius: float = 4.0,damage: float = 10.0) -> AmmoDefinition:
	var ammo := AmmoDefinition.new()
	ammo.ammo_id = "test_only:06c_blast"
	ammo.damage_type = "chemical"
	ammo.nominal_damage = damage
	ammo.anchor_penetration = 50.0
	ammo.explosion_radius_m = radius
	ammo.suppression = 7.0
	ammo.initial_speed_mps = 900.0
	ammo.configure_confirmed_curve()
	return ammo

func input_for(point: Vector3,ammo: AmmoDefinition,order: int = 1) -> Dictionary:
	return {"kind":"static_impact","point":[point.x,point.y,point.z],"normal":[0.0,1.0,0.0],"velocity":[0.0,-1.0,0.0],
		"time_seconds":0.0,"distance_m":100.0,"emission_order":order,"source_event_id":"test_only:06c:%s" % order,
		"source_unit_id":999,"source_player_id":42,"ammo_values":ProjectileSettlementInput.ammunition(ammo),
		"weapon_values":{"attack_top":false,"reduction_ignore":0.0}}

func consumer(test: Dictionary) -> DirectHitSettlement:
	var frame := FiringFrame.new()
	frame.begin(0.0,test.aiming,true)
	var motion := ProjectileUnitMotion.new()
	var snapshot := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(0.0,snapshot,snapshot)
	frame.finish(test.aiming,motion)
	var settlement := DirectHitSettlement.new()
	settlement.begin(test.aiming,frame)
	return settlement

func vehicle(test: Dictionary) -> UnitState:
	var definition := UnitDefinition.new()
	definition.configuration_source = "test_only:06c_vehicle"
	definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	definition.maximum_health = 100.0
	definition.kinetic_armor_by_face = {"front":10.0,"side":20.0,"rear":30.0,"top":40.0}
	definition.chemical_armor_by_face = definition.kinetic_armor_by_face.duplicate()
	var unit := UnitState.new(test.unit.unit_id+2,42,Vector3(8,0,0))
	unit.configure(1,definition)
	test.aiming.units[unit.unit_id] = unit
	return unit

func spawn(test: Dictionary,event: Dictionary) -> void:
	var motion := ProjectileUnitMotion.new()
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(0,snapshots,snapshots)
	var flight := OrderedProjectileStep.new()
	flight.begin(test.timeline.projectiles,motion)
	flight.spawn(event)
	test.timeline.fire.emission_order = event.emission_order

func run() -> void:
	var formal := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var frozen := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var ammo := blast()
	var fractions := [0.0,0.25,0.5,0.75,0.9,1.0,1.1]
	var expected := [1.0,0.87890625,0.5625,0.19140625,0.0361,0.0,0.0]
	for index: int in fractions.size():
		check(is_equal_approx(ExplosionGeometry.attenuation(pow(fractions[index]*4.0,2.0),ammo.explosion_radius_squared,ammo.inverse_explosion_radius_squared),expected[index]),"confirmed squared attenuation "+str(fractions[index]))
	check(ammo.explosion_radius_squared == 16 and ammo.inverse_explosion_radius_squared == 0.0625,"radius cache initialized before emission")
	check(is_nan(ExplosionGeometry.attenuation(1.0,NAN,NAN)),"unknown cache refused")
	var test := fixture(3)
	test.unit.definition.protection_chemical = 5
	test.unit.members[0].position = Vector3.ZERO
	test.unit.members[1].position = Vector3(2,0,0)
	test.unit.members[2].position = Vector3(4,0,0)
	var settle := consumer(test)
	var input := input_for(Vector3.ZERO,ammo)
	input.source_unit_id = test.unit.unit_id
	var plan := settle.prepare(input)
	check(plan.ok and plan.effects.size() == 2,"inside members affected; exact edge excluded")
	check(plan.suppression_inputs.size() == 1 and plan.suppression_inputs[0].amount == 7,"one full suppression input for two members")
	check(test.unit.health == 15,"prepare does not mutate health")
	var result := settle.commit(input)
	check(result.ok and test.unit.health == 5 and result.casualty_unit_ids.size() == 1,"self blast kills two members; one casualty refresh per squad")
	check(settle.results.size() == 2 and settle.results[1].calculated_damage == 5.625,"actual per-member attenuation before armor; no spill")
	check(not settle.prepare(input).ok and not settle.commit(input).ok and test.unit.health == 5,"duplicate blast cannot damage twice")
	check(settle.records[1].suppression_inputs.size() == 1,"internal retained actual suppression input")
	var old_results := settle.results
	settle.begin(test.aiming,settle.sample)
	check(old_results.size() == 2 and settle.suppression_inputs.is_empty() and settle.records.size() == 1,"step batches independent; match ledger persists")
	test.timeline.projectiles.collision.close()
	# Zero damage still produces an effective input; edge alone does not.
	for distance: float in [3.0,4.0,5.0]:
		test = fixture(1)
		test.unit.definition.protection_chemical = 500.0
		test.unit.members[0].position = Vector3(distance,0,0)
		settle = consumer(test)
		input = input_for(Vector3.ZERO,ammo)
		plan = settle.prepare(input)
		check(plan.ok,"edge case prepare")
		check(plan.suppression_inputs.size() == (1 if distance < 4 else 0),"only strictly inside refresh input")
		check(settle.commit(input).ok and test.unit.health == 5,"chemical lower endpoint leaves HP unchanged")
		test.timeline.projectiles.collision.close()
	# Explicitly confirmed explosive infantry hit: range only, no nearest extra hit.
	test = fixture(1)
	test.unit.definition.protection_chemical = 5
	test.unit.members[0].position = Vector3(2,0,0)
	settle = consumer(test)
	input = input_for(Vector3.ZERO,blast(4,2))
	input.kind = "unit_impact"
	input.hit_unit_id = test.unit.unit_id
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.size() == 1 and plan.effects[0].damage == 1.125,"infantry direct explosive hit only distance result")
	check(settle.commit(input).ok and test.unit.health == 3.875,"no additional direct damage")
	test.timeline.projectiles.collision.close()
	# All receivers are validated before the first health mutation.
	test = fixture(2)
	test.unit.definition.protection_chemical = 5
	test.unit.members[0].position = Vector3.ZERO
	test.unit.members[1].position = Vector3(1,0,0)
	test.target.position = Vector3(2,0,0)
	test.target.members[0].position = test.target.position
	test.target.definition.protection_chemical = -1
	settle = consumer(test)
	input = input_for(Vector3.ZERO,ammo)
	check(not settle.prepare(input).ok and test.unit.health == 10 and test.target.health == 5,"invalid later target refuses entire blast before mutation")
	input.ammo_values.suppression = null
	check(not settle.prepare(input).ok,"missing suppression not converted to zero")
	input = input_for(Vector3.ZERO,ammo)
	input.ammo_values.inverse_explosion_radius_squared = null
	check(not settle.prepare(input).ok,"missing radius cache rejected")
	input.kind = "battlefield_exit"
	check(settle.prepare(input).ok and settle.commit(input).ok and settle.results.is_empty(),"exit never explodes even missing cache")
	test.timeline.projectiles.collision.close()
	# OBB distance uses existing shape; event time and orientation are sampled.
	test = fixture(1)
	var hull := vehicle(test)
	settle = consumer(test)
	var geometry := ExplosionGeometry.closest(settle.sample.motion,hull.unit_id,Vector3(8,0,-2),0)
	check(geometry.ok and geometry.distance_squared == 2.25,"nearest existing hull surface not center distance")
	input = input_for(Vector3(8,0,-2),ammo)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.size() == 1 and plan.effects[0].face == "front","near blast center selects actual face")
	check(plan.effects[0].attenuation == pow(1.0-2.25/16.0,2),"near vehicle same curve")
	check(settle.commit(input).ok and settle.results.size() == 1,"one hull damage result")
	input = input_for(Vector3(8,0,-0.5),ammo,2)
	input.kind = "unit_impact"
	input.hit_unit_id = hull.unit_id
	input.velocity = [0.0,0.0,1.0]
	input.normal = [0.0,0.0,-1.0]
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.size() == 1 and plan.effects[0].attenuation == 1,"vehicle direct blast r0 once")
	check(settle.commit(input).ok and settle.records[2].damage_results.size() == 1,"no hull direct plus area double damage")
	input = input_for(Vector3(8,2,0),ammo,3)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects[0].face == "top","above hull top precedence")
	input = input_for(Vector3(8,0,-2),ammo,4)
	input.weapon_values.attack_top = true
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.size() == 1 and plan.effects[0].face == "top" and plan.effects[0].armor == 40,"near miss attack-top bypasses front direction")
	input = input_for(hull.position,ammo,4)
	input.weapon_values.attack_top = true
	plan = settle.prepare(input)
	check(plan.ok and plan.effects[0].face == "top" and plan.effects[0].attenuation == 1,"attack-top bypasses zero direction as well")
	settle.plans.erase(4)
	input = input_for(hull.position,ammo,4)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects[0].face == "top" and plan.effects[0].attenuation == 1,"confirmed zero direction takes top without tag")
	input = input_for(hull.position+Vector3.DOWN,ammo,4)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects[0].face == "top","zero horizontal direction takes top; no bottom armor invented")
	var row: Dictionary = settle.sample.motion.records[hull.unit_id]
	row.end = Vector3(18,0,0)
	geometry = ExplosionGeometry.closest(settle.sample.motion,hull.unit_id,Vector3(8,0,-2),GravityBallistics.STEP_SECONDS*0.5)
	check(is_equal_approx(geometry.distance_squared,22.5),"event-time translated closest shape")
	row.end = row.start
	row.extents = Vector3(2,0.5,0.5) # TEST ONLY existing shape interface, not a new dimension field.
	row.end_extents = row.extents
	row.end_basis = Basis(Vector3.UP,PI*0.5)
	check(ExplosionGeometry.closest(settle.sample.motion,hull.unit_id,Vector3(11,0,0),0).distance_squared == 1,"unrotated existing shape distance")
	check(is_equal_approx(ExplosionGeometry.closest(settle.sample.motion,hull.unit_id,Vector3(11,0,0),GravityBallistics.STEP_SECONDS).distance_squared,6.25),"rotated existing shape distance")
	input = input_for(Vector3(9.6,1,0),ammo,5)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects[0].face == "side","unmarked blast uses center direction rather than nearest surface normal")
	test.timeline.projectiles.collision.close()
	# A moving member is measured at the event, not at its future endpoint.
	test = fixture(1)
	test.unit.definition.protection_chemical = 5
	test.unit.members[0].position = Vector3.ZERO
	var frame := FiringFrame.new()
	frame.begin(0,test.aiming,true)
	var before := ProjectileUnitMotion.capture(test.aiming.units)
	test.unit.members[0].position = Vector3(100,0,0)
	var moving_motion := ProjectileUnitMotion.new()
	moving_motion.configure(0,before,ProjectileUnitMotion.capture(test.aiming.units))
	frame.finish(test.aiming,moving_motion)
	settle = DirectHitSettlement.new()
	settle.begin(test.aiming,frame)
	input = input_for(Vector3.ZERO,ammo)
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.size() == 1 and plan.effects[0].attenuation == 1,"member blast uses true event position")
	input.time_seconds = GravityBallistics.STEP_SECONDS
	plan = settle.prepare(input)
	check(plan.ok and plan.effects.is_empty() and plan.suppression_inputs.is_empty(),"future endpoint out of radius")
	test.timeline.projectiles.collision.close()
	# Real collision and timeline: friendly blocker, explosion kills source before late emission.
	test = fixture(1)
	test.unit.definition.protection_chemical = 5
	test.target.position = Vector3(0,0,-2)
	test.target.members[0].position = test.target.position
	test.target.team_id = test.unit.team_id
	test.weapon.fire_state.interval_remaining = 0.01
	test.timeline.direct_hit_enabled = true
	var event := {"event_id":"test_only:06c_real","emission_order":1,"time_seconds":0.0,"unit_id":test.unit.unit_id,"owner_player_id":42,
		"weapon_instance_id":"test_only:06c_launch","position":Vector3(0,0.2,0),"velocity":Vector3(0,0,-900),"ammo":blast(4,100),
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var flight := OrderedProjectileStep.new()
	var motion := ProjectileUnitMotion.new()
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(0,snapshots,snapshots)
	flight.begin(test.timeline.projectiles,motion)
	flight.spawn(event)
	test.timeline.fire.emission_order = 1
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted,"real friendly blast timeline completes")
	check(result.settlements.size() == 1 and result.settlements[0].input.get("hit_unit_id",0) == test.target.unit_id,"source excluded from collision; friendly actually blocks")
	check(test.unit.health == 0 and test.target.health == 0 and result.damage_results.size() == 2,"actual blast self damage and friendly damage")
	check(result.emissions.is_empty(),"early blast death cancels later source emission")
	check(result.suppression_inputs.size() == 2,"real explosion each reached squad once")
	check(result.damage_results[0].source_player_id == 42 and result.damage_results[1].source_unit_id == test.unit.unit_id,"fixed attribution remains internal")
	check(ProjectileSettlementInbox.values_only(test.timeline.direct_hits.records[1]),"actual blast result ledger entry contains values only")
	test.timeline.projectiles.collision.close()
	for exits: bool in [false,true]:
		test = fixture(1)
		test.unit.definition.protection_chemical = 5
		test.timeline.direct_hit_enabled = true
		test.weapon.fire_state.interval_remaining = 1.0
		event = {"event_id":"test_only:06c_static_or_exit","emission_order":1,"time_seconds":0.0,"unit_id":test.target.unit_id,"owner_player_id":43,
			"weapon_instance_id":"test_only:06c_launch","position":Vector3(0,1,0) if exits else Vector3(2,1,0),
			"velocity":Vector3(900,0,0) if exits else Vector3(0,-900,0),"ammo":blast(4,100),"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
		if exits: test.timeline.projectiles.configure_bounds(Rect2(-1,-1,2,2))
		else: test.timeline.projectiles.collision.box("test_only:06c_ground","terrain",Vector3(10,0.05,10),Transform3D(Basis.IDENTITY,Vector3(0,-0.05,0)))
		spawn(test,event)
		result = test.timeline.step(test.aiming)
		check(not test.timeline.halted and result.settlements.size() == 1,"real static or exit timeline completes")
		var terminal: Dictionary = result.settlements[0].input
		check(terminal.kind == ("battlefield_exit" if exits else "static_impact"),"actual static or exit classified")
		check(result.damage_results.size() == (0 if exits else 1),"only physical impact explodes")
		check(result.suppression_inputs.size() == (0 if exits else 1),"exit never generates effective suppression")
		check(test.unit.health == (5 if exits else 0),"static blast damage versus lawful exit")
		if not exits: check(absf(terminal.point[0]-2.0) < 0.00001 and absf(terminal.point[1]) < 0.00001,"explosion center is true collision point")
		test.timeline.projectiles.collision.close()
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == formal,"formal DATA unchanged")
	check(FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == frozen,"frozen v1 unchanged")
	print("Prototype 0.6C: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
