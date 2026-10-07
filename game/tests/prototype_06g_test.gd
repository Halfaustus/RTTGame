extends "res://tests/db29_combat_timeline_test.gd"

func setup(p: float,front: float = 100.0,damage: float = 10.0) -> Dictionary:
	var test := fixture(1)
	test.weapon.enabled = false
	test.timeline.direct_hit_enabled = true
	test.timeline.overpenetration_enabled = true
	test.timeline.suppression_enabled = true
	test.timeline.modules_enabled = true
	var units: Array[UnitState] = []
	for index: int in 4:
		var definition := UnitDefinition.new()
		definition.configuration_source = "test_only:06g_independent_boundary_fixture"
		definition.member_count = 1
		definition.protection_kinetic = 6
		definition.protection_chemical = 6
		if index == 2:
			definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
			definition.member_count = 0
			definition.maximum_health = 20
			definition.hitbox_half_extents = Vector3(0.5,0.5,0.5)
			definition.kinetic_armor_by_face = {"front":front,"side":10.0,"rear":10.0,"top":10.0}
			definition.chemical_armor_by_face = definition.kinetic_armor_by_face.duplicate()
		var unit := UnitState.new(test.unit.unit_id+index+2,43,Vector3(0,0,-2.0*(index+1)))
		unit.configure(2,definition)
		test.aiming.units[unit.unit_id] = unit
		units.append(unit)
	var ammo := AmmoDefinition.new()
	ammo.ammo_id = "test_only:06g_generated_kinetic"
	ammo.initial_speed_mps = 300
	ammo.damage_type = "kinetic"
	ammo.nominal_damage = damage
	ammo.penetration_upper = p
	ammo.anchor_penetration = p
	ammo.anchor_distance_m = 100
	ammo.explosion_radius_m = 0
	ammo.suppression = 30
	ammo.module_damage = 100
	ammo.configure_confirmed_curve()
	var motion := ProjectileUnitMotion.new()
	var poses := ProjectileUnitMotion.capture(test.aiming.units)
	check(motion.configure(0,poses,poses),"stationary shared motion ready")
	var flight := OrderedProjectileStep.new()
	flight.begin(test.timeline.projectiles,motion)
	var event := {"event_id":"test_only:06g:shot","emission_order":1,"unit_id":test.unit.unit_id,"owner_player_id":42,"weapon_instance_id":"test_only:06g:weapon","ammo":ammo,"position":Vector3.ZERO,"velocity":Vector3(0,0,-300),"time_seconds":0.0,"weapon_values":{"attack_top":false,"reduction_ignore":0.0}}
	check(not flight.spawn(event).is_empty(),"legal generated shot inserted")
	test.targets = units
	test.event = event
	test.ammo = ammo
	return test

func run() -> void:
	for p: float in [100.0,200.0]:
		var test := setup(p)
		var result: Dictionary = test.timeline.step(test.aiming)
		check(not test.timeline.halted,"ordered multihit timeline completes: "+test.timeline.failure_reason)
		if test.timeline.halted: quit(1); return
		check(test.targets[0].health == 4 and test.targets[1].health == 4,"two squads each take 10 percent once")
		check(test.targets[0].suppression.q == 30 and test.targets[1].suppression.q == 30,"suppression not reduced or duplicated across same shot")
		check(result.damage_results[0].impact_sequence == 0 and result.damage_results[1].impact_sequence == 1,"distinct internal hit identities")
		check(result.damage_results[0].time_seconds < result.damage_results[1].time_seconds,"hits retain actual chronological times")
		check(result.damage_results[2].face == "rear" and result.damage_results[2].exit_face == "front","rear entry checks actual front exit")
		check(test.targets[2].vehicle_modules.levels.count(1) == 1,"module damage unchanged and applied once")
		if p == 100:
			check(test.targets[2].health == 10 and test.targets[3].health == 5,"thick exit blocks and keeps normal damage")
			check(result.damage_results.size() == 3 and result.events.size() == 1 and result.events[0].hit_unit_id == test.targets[2].unit_id,"only final impact emits public terminal")
			check(test.timeline.projectiles.active_slots.is_empty(),"blocked projectile recycled")
		else:
			check(test.targets[2].health == 19 and test.targets[3].health == 4,"successful hull traversal deals 10 percent and reaches rearward squad")
			check(result.events.is_empty() and test.timeline.projectiles.active_slots.size() == 1,"intermediate impacts do not terminate public trajectory")
			check(result.damage_results[3].penetration == 78,"both armor faces and preceding squads accumulate loss")
			var state: Dictionary = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
			check(state.hit_units.size() == 4 and state.penetration_loss == 128,"one visit per unit and persistent total loss")
			var next: Dictionary = test.timeline.step(test.aiming)
			check(next.damage_results.is_empty(),"following step cannot hit those units again")
		check(test.timeline.settlement_inbox.accepted_count() == result.damage_results.size(),"inbox accepts all distinct hits of same shot")
		var input: Dictionary = result.settlements[0].input
		var duplicate_batch: Array[Dictionary] = [input]
		check(test.timeline.settlement_inbox.accept_batch(duplicate_batch) and test.timeline.settlement_inbox.take_pending().is_empty(),"duplicate delivery remains idempotent")
		check(not test.timeline.direct_hits.prepare(input).ok,"damage ledger rejects duplicate hit")
		if p == 100:
			var motion := ProjectileUnitMotion.new()
			var poses := ProjectileUnitMotion.capture(test.aiming.units)
			check(motion.configure(test.timeline.projectiles.time_seconds,poses,poses),"reuse motion ready")
			var flight := OrderedProjectileStep.new()
			flight.begin(test.timeline.projectiles,motion)
			var second: Dictionary = test.event.duplicate()
			second.event_id = "test_only:06g:second"
			second.emission_order = 2
			second.time_seconds = test.timeline.projectiles.time_seconds
			check(not flight.spawn(second).is_empty(),"recycled slot accepts next legal shot")
			var slot: Dictionary = test.timeline.projectiles.slots[test.timeline.projectiles.active_slots[0]]
			check(slot.generation == 2 and not slot.has("hit_units") and not slot.has("penetration_loss"),"slot reuse clears traversal and loss")
			var repeated: Dictionary = test.timeline.step(test.aiming)
			check(not test.timeline.halted and repeated.damage_results.size() == 3 and repeated.damage_results[0].penetration == 100,"new shot starts full penetration and visits units anew")
		test.timeline.projectiles.collision.close()
	for p: float in [11.999,12.0,12.001]:
		var test := setup(p)
		var result: Dictionary = test.timeline.step(test.aiming)
		check(not test.timeline.halted,"entry boundary has valid timeline")
		check(result.damage_results[0].overpenetrated == (p >= 12),"entry ratio equality boundary")
		test.timeline.projectiles.collision.close()
	for armor: float in [77.999,78.0,78.001]:
		var test := setup(100,armor)
		var result: Dictionary = test.timeline.step(test.aiming)
		check(not test.timeline.halted and result.damage_results[2].overpenetrated == (armor <= 78),"exit remaining penetration equality boundary")
		test.timeline.projectiles.collision.close()
	var geometry := setup(200)
	var motion := ProjectileUnitMotion.new()
	var poses := ProjectileUnitMotion.capture(geometry.aiming.units)
	motion.configure(0,poses,poses)
	var frame := FiringFrame.new()
	frame.begin(0,geometry.aiming,true)
	frame.finish(geometry.aiming,motion)
	var input := {"ammo_values":ProjectileSettlementInput.ammunition(geometry.ammo),"time_seconds":0.0,"point":[0.0,0.5,-6.0],"velocity":[0.0,-300.0,0.0],"normal":[0.0,1.0,0.0]}
	check(not KineticOverpenetration.decide(input,geometry.targets[2],frame,200,10).continues,"bottom exit cannot traverse")
	input.point = [0.0,0.0,-6.0]
	input.normal = [0.0,0.0,0.0]
	check(not KineticOverpenetration.decide(input,geometry.targets[2],frame,200,10).continues,"inside origin cannot traverse")
	input.point = [0.5,0.0,-6.0]
	input.normal = [1.0,0.0,0.0]
	input.velocity = [0.0,0.0,-300.0]
	check(not KineticOverpenetration.decide(input,geometry.targets[2],frame,200,10).continues,"tangent cannot traverse")
	input.point = [0.0,0.0,-5.5]
	input.normal = [0.0,0.0,1.0]
	geometry.targets[2].definition.kinetic_armor_by_face.erase("front")
	check(not KineticOverpenetration.decide(input,geometry.targets[2],frame,200,10).ok,"missing exit armor rejected before effects")
	geometry.timeline.projectiles.collision.close()
	var ammo_values := ProjectileSettlementInput.ammunition(geometry.ammo)
	ammo_values.confirmed_decay_coefficient = 2.0
	var decayed := ImpactDamageRules.damage(ammo_values,100,100,[],0,128)
	check(absf(decayed.penetration-(72-2*log(2.0))) < 0.000001,"loss stacks with cached distance curve")
	check(ImpactDamageRules.damage(ammo_values,100,100,[],0,300).damage == 0,"loss is not restored by minimum penetration floor")
	var friendly := setup(200)
	friendly.targets[0].team_id = 1
	var friendly_result: Dictionary = friendly.timeline.step(friendly.aiming)
	check(not friendly.timeline.halted and friendly.targets[0].health == 4 and friendly_result.damage_results.size() == 4,"friendly hit receives same traversal and damage")
	friendly.timeline.projectiles.collision.close()
	var vehicle: UnitState = friendly.targets[2]
	check(KineticOverpenetration.preview(vehicle,Vector3.ZERO,vehicle.position,0,200,10).continues,"nominal ammo scoring recognizes rear-to-front traversal")
	check(not KineticOverpenetration.preview(vehicle,Vector3.ZERO,vehicle.position,0,100,10).continues,"nominal ammo scoring respects thick exit")
	var blocked := setup(200)
	blocked.timeline.projectiles.collision.box("test_only:06g:wall","obstacle",Vector3(0.5,2,0.1),Transform3D(Basis.IDENTITY,Vector3(0,0,-7)))
	var blocked_result: Dictionary = blocked.timeline.step(blocked.aiming)
	check(not blocked.timeline.halted and blocked_result.damage_results.size() == 3 and blocked.targets[3].health == 5,"static obstacle blocks after hull traversal")
	check(blocked_result.events.size() == 1 and blocked_result.events[0].object_id == "test_only:06g:wall","static final terminal remains public")
	blocked.timeline.projectiles.collision.close()
	var fatal := setup(200,100,100)
	var fatal_result: Dictionary = fatal.timeline.step(fatal.aiming)
	check(not fatal.timeline.halted and fatal_result.damage_results.size() == 4,"fatal entry resamples shared motion before subsequent impacts")
	check(fatal.targets[0].health == 0 and fatal.targets[1].health == 0 and fatal.targets[3].health == 0,"overpenetration applies real casualties once")
	fatal.timeline.projectiles.collision.close()
	var orphan := setup(200)
	orphan.unit.health = 0
	var orphan_result: Dictionary = orphan.timeline.step(orphan.aiming)
	check(not orphan.timeline.halted and orphan_result.damage_results.size() == 4,"already legal shot traverses after source death")
	orphan.timeline.projectiles.collision.close()
	var ranking := setup(200)
	var low := AmmoDefinition.new()
	low.ammo_id = "test_only:06g_low_penetration"
	low.damage_type = "kinetic"
	low.nominal_damage = 2
	low.penetration_upper = 10
	low.anchor_penetration = 10
	low.anchor_distance_m = 100
	low.explosion_radius_m = 0
	low.configure_confirmed_curve()
	# Both are independently generated same-type ammunition; pure ranking only.
	ranking.weapon.definition = ranking.weapon.definition.duplicate(true)
	ranking.weapon.definition.ammo_definitions.assign([ranking.ammo,low])
	ranking.weapon.inventory = {ranking.ammo.ammo_id:80,low.ammo_id:80}
	ranking.weapon.bind_target(AttackTarget.unit(ranking.targets[0]))
	var scoring := {"overpenetration_enabled":true,"position":Vector3.ZERO,"target":ranking.targets[0].position}
	var selection := AmmoSelection.select(ranking.weapon,{},scoring)
	check(selection.reason == "eligible" and selection.ammo == low and selection.preview_damage == 2,"existing max-damage ammo strategy includes ten percent overpenetration score")
	ranking.timeline.projectiles.collision.close()
	check(KineticOverpenetration.exit_surface(Vector3(0,0,0.5),Vector3.FORWARD,Vector3.ONE*0.5).face == "front","tangent follows actual exit face")
	check(KineticOverpenetration.exit_surface(Vector3(0,0.5,0),Vector3.DOWN,Vector3.ONE*0.5).face == "bottom","bottom exit identified for rejection")
	check(KineticOverpenetration.exit_surface(Vector3(0.5,0,0),Vector3.RIGHT,Vector3.ONE*0.5).is_empty(),"zero-length grazing rejected")
	print("06G overpenetration: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
