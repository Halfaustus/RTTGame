extends "res://tests/db29_combat_timeline_test.gd"

# Reuse the explicit TEST ONLY generated fixture, not formal unit configuration.
func context(id: String = "test_only:06a_match") -> Dictionary:
	return {"match_id":id,"map_id":"test_only:06a_geometry","rules_id":ConfirmedDataValidator.RULES_ID,
		"data_version":ConfirmedDataValidator.DATA_VERSION,"data_sha256":FileAccess.get_sha256(ConfirmedGameData.PATH)}

func wall(test: Dictionary,id: String,distance: float) -> void:
	var origin: Vector3 = test.weapon.world_position()
	var direction: Vector3 = (test.target.position-origin).normalized()
	test.timeline.projectiles.collision.box(id,"obstacle",Vector3(100,100,0.01),
		Transform3D(Basis.looking_at(direction),origin+direction*distance))

func run() -> void:
	var formal_hash := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var fixture_hash := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var test := fixture(400) # Existing TEST ONLY fixture: 400 real allocated members.
	var timeline: DB29CombatTimeline = test.timeline
	check(timeline.configure_settlement_context(context()),"explicit isolated match context")
	wall(test,"test_only:wall",5.0)
	var stock: int = test.weapon.inventory[test.weapon.definition.ammo_definitions[0].ammo_id]
	var observed: Array[float] = []
	timeline.settlement_prepare = func(_input): return {"ok":true,"affected_unit_ids":[test.unit.unit_id]}
	timeline.settlement_commit = func(input):
		observed.append(input.time_seconds)
		test.weapon.enabled = false # Eligibility consumer only: no damage formula.
		return {"ok":true}
	var result := timeline.step(test.aiming)
	check(not timeline.halted,"ordered consumer does not halt")
	check(result.emissions.size() == 1,"early terminal disables subsequent due emissions")
	check(result.events.size() == 2 and result.get("settlements",[]).size() == 1,"same-step spawn terminal and private settlement input")
	check(test.weapon.inventory[test.weapon.definition.ammo_definitions[0].ammo_id] == stock-3,"no speculative late stock debit")
	check(observed.size() == 1 and observed[0] < 0.006,"consumer runs at actual time before second due event")
	check(test.target.health == test.target.maximum_health,"A never damages target")
	if not result.get("settlements",[]).is_empty():
		var envelope: Dictionary = result.settlements[0]
		var input: Dictionary = envelope.input
		check(envelope.context == context(),"context includes independent match map rules DATA identities")
		check(input.kind == "static_impact" and input.source_player_id == 42,"classification and fixed domain attribution")
		check(ProjectileSettlementInbox.values_only(envelope) and JSON.parse_string(JSON.stringify(envelope)) is Dictionary,"finite JSON values only")
		check(input.ammo_values.nominal_damage == test.weapon.definition.ammo_definitions[0].nominal_damage,"selected ammo value retained after slot clear")
		check(timeline.projectiles.slots[0].is_empty(),"terminal slot source ammo and ignore state cleared")
		var inbox := ProjectileSettlementInbox.new()
		check(inbox.configure(context()),"inbox context setup")
		check(inbox.accept_batch([input,input]) and inbox.accepted_count() == 1,"intra-batch duplicate accepted once")
		check(inbox.take_pending().size() == 1 and inbox.accept_batch([input]) and inbox.take_pending().is_empty(),"delayed duplicate has no second delivery")
		var alias := input.duplicate(true)
		alias.emission_order += 100
		check(not inbox.accept_batch([alias]) and inbox.failure_reason == "settlement_source_identity_conflict","source identity alias rejected after delivery drain")
		var altered := input.duplicate(true)
		altered.distance_m += 1.0
		check(not inbox.accept_batch([altered]) and inbox.failure_reason == "settlement_identity_conflict","conflicting duplicate rejected")
		var fresh := input.duplicate(true)
		fresh.emission_order += 1
		fresh.projectile_id += ":fresh"
		fresh.source_event_id += ":fresh"
		var bad := input.duplicate(true)
		bad.position[0] = NAN
		check(not inbox.accept_batch([fresh,bad]) and inbox.accepted_count() == 1,"batch rejection publishes no partial input")
		var pending_count := inbox.accepted_count()
		var resource_bad := input.duplicate(true)
		resource_bad.ammo_values.injected = AmmoDefinition.new()
		check(not inbox.accept_batch([resource_bad]) and inbox.accepted_count() == pending_count,"Resource injection refused")
		check(inbox.accept_batch([fresh]) and inbox.accepted_count() == 2,"same generation on another identity remains legal")
		var delivered := inbox.take_pending()
		delivered[0].input.ammo_values.nominal_damage = -100.0
		check(inbox.accept_batch([fresh]) and inbox.take_pending().is_empty(),"consumer mutation cannot corrupt duplicate ledger")
		check(not inbox.configure(context("test_only:other")),"context cannot switch during live match")
		inbox.reset()
		check(inbox.configure(context("test_only:other")) and inbox.accept_batch([input]),"explicit match teardown resets identity namespace")
		var public: Dictionary = ProjectileProjection.terminal(result.events[1])
		check(public.size() == 4 and not public.has("input") and not public.has("ammo_values"),"public terminal remains exact four-field whitelist")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# A later terminal preserves all lawful earlier emissions and stock debits.
	test = fixture(400)
	timeline = test.timeline
	wall(test,"test_only:late_wall",9.0)
	stock = test.weapon.inventory[test.weapon.definition.ammo_definitions[0].ammo_id]
	timeline.settlement_prepare = func(_input): return {"ok":true,"affected_unit_ids":[test.unit.unit_id]}
	timeline.settlement_commit = func(_input):
		test.weapon.enabled = false
		return {"ok":true}
	result = timeline.step(test.aiming)
	check(not timeline.halted and result.emissions.size() == 2,"later impact preserves two lawful earlier shots")
	check(test.weapon.inventory[test.weapon.definition.ammo_definitions[0].ammo_id] == stock-6,"lawful earlier stock debit is never rolled back")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# Rejected pure preparation cannot recycle a predicted terminal slot.
	test = fixture(1)
	timeline = test.timeline
	timeline.projectiles.collision.box("test_only:prepare_wall","obstacle",Vector3(3,3,0.01),Transform3D(Basis.IDENTITY,Vector3(0,0,-5)))
	timeline.settlement_prepare = func(_input): return {"ok":false}
	timeline.settlement_commit = func(_input): return {"ok":true}
	result = timeline.step(test.aiming)
	check(timeline.halted and timeline.failure_reason == "settlement_prepare_failed","preparation rejection halts explicitly")
	check(timeline.projectiles.active_slots.size() == 1 and result.events.size() == 1 and timeline.settlement_inbox.accepted_count() == 0,"prediction rejection retains flight and publishes no terminal input")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# Existing source state is never consulted to settle an in-flight projectile.
	test = fixture(1)
	timeline = test.timeline
	test.target.position = Vector3(0,0,-50)
	test.target.initialize_spatial()
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	var motion := ProjectileUnitMotion.new()
	check(motion.configure(0.0,snapshots,snapshots),"source-exit motion frame")
	result = timeline.step(test.aiming,motion)
	check(result.emissions.size() == 1 and result.settlements.is_empty(),"first step remains in flight")
	var source_id: int = test.unit.unit_id
	test.aiming.units.erase(source_id)
	var original_damage: float = test.weapon.definition.ammo_definitions[0].nominal_damage
	var original_ammo_id: String = test.weapon.definition.ammo_definitions[0].ammo_id
	test.weapon.definition.ammo_definitions[0].nominal_damage = -999.0 # Mutated test Resource, never DATA.
	test.weapon.definition.ammo_definitions[0].ammo_id = "test_only:mutated_resource"
	snapshots = ProjectileUnitMotion.capture(test.aiming.units)
	motion = ProjectileUnitMotion.new()
	check(motion.configure(timeline.fire.time_seconds,snapshots,snapshots),"next step excludes removed source")
	result = timeline.step(test.aiming,motion)
	check(not timeline.halted and result.settlements.size() == 1,"flight settles after source removal")
	if not result.settlements.is_empty():
		check(result.settlements[0].input.kind == "unit_impact" and result.settlements[0].input.hit_unit_id == test.target.unit_id,"unit classification")
		check(result.settlements[0].input.source_unit_id == source_id and result.settlements[0].input.ammo_values.nominal_damage == original_damage and result.settlements[0].input.ammo_definition_id == original_ammo_id,"source and emission-time ammo identity/values survive mutation")
	timeline.projectiles.collision.close()
	# Simultaneous existing collisions: removal revalidates remaining candidates.
	test = fixture(400)
	timeline = test.timeline
	test.weapon.enabled = false
	snapshots = ProjectileUnitMotion.capture(test.aiming.units)
	motion = ProjectileUnitMotion.new()
	check(motion.configure(0.0,snapshots,snapshots),"candidate revalidation frame")
	var ammo: AmmoDefinition = data.ammunition("A_556")
	var emissions: Array[Dictionary] = []
	for n in range(2):
		emissions.append({"event_id":"test_only:incoming:%s" % n,"emission_order":n+1,"time_seconds":0.0,
			"unit_id":test.unit.unit_id,"owner_player_id":77,"weapon_instance_id":"test_only:incoming",
			"position":Vector3(0,0,0),"velocity":Vector3(0,0,-ammo.initial_speed_mps),"ammo":ammo})
	# Spawn-only boundary avoids advancing the projectiles before the coordinator.
	var flight := OrderedProjectileStep.new()
	flight.begin(timeline.projectiles,motion)
	for event: Dictionary in emissions: flight.spawn(event)
	timeline.fire.emission_order = 2
	var targets: Array[int] = []
	timeline.settlement_prepare = func(input): return {"ok":true,"affected_unit_ids":[input.get("hit_unit_id",test.target.unit_id)]}
	timeline.settlement_commit = func(input):
		targets.append(input.hit_unit_id)
		test.aiming.units.erase(input.hit_unit_id)
		return {"ok":true}
	result = timeline.step(test.aiming,motion)
	check(not timeline.halted and targets.size() == 1,"second stale collision does not settle removed target")
	check(timeline.projectiles.active_slots.size() == 1,"second projectile continues after stale candidate rejected")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# A deliberately failed commit is permanently halted, never retried.
	test = fixture(1)
	timeline = test.timeline
	timeline.projectiles.collision.box("test_only:failure_wall","obstacle",Vector3(3,3,0.01),Transform3D(Basis.IDENTITY,Vector3(0,0,-5)))
	var calls := [0]
	timeline.settlement_prepare = func(_input): return {"ok":true,"affected_unit_ids":[]}
	timeline.settlement_commit = func(_input):
		calls[0] += 1
		return {"ok":false}
	result = timeline.step(test.aiming)
	check(timeline.halted and timeline.failure_reason == "settlement_commit_failed","partial commit failure halts timeline")
	timeline.step(test.aiming)
	check(calls[0] == 1,"halted partial consumer cannot duplicate side effect")
	check(result.settlements.is_empty() and result.failed_settlement_inputs.size() == 1,"failed consumer input quarantined separately from successful receipts")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# A must refuse stale pre-sampled movement/aim integration requested by B/D.
	test = fixture(1)
	timeline = test.timeline
	timeline.projectiles.collision.box("test_only:resample_wall","obstacle",Vector3(3,3,0.01),Transform3D(Basis.IDENTITY,Vector3(0,0,-5)))
	timeline.settlement_prepare = func(_input): return {"ok":true,"affected_unit_ids":[]}
	timeline.settlement_commit = func(_input): return {"ok":true,"requires_resampling":true}
	result = timeline.step(test.aiming)
	check(timeline.halted and timeline.failure_reason == "settlement_motion_resampling_required","unsupported remaining movement/aim resampling never silently continues")
	timeline.projectiles.collision.close()
	timeline.settlement_prepare = Callable()
	timeline.settlement_commit = Callable()
	# Real cross-domain ties: source identity, never a global fire/impact priority.
	for lower_source: bool in [true,false]:
		test = fixture(1)
		timeline = test.timeline
		snapshots = ProjectileUnitMotion.capture(test.aiming.units)
		motion = ProjectileUnitMotion.new()
		motion.configure(0.0,snapshots,snapshots)
		var source: int = 1 if lower_source else test.unit.unit_id+1000
		var tie := {"event_id":"test_only:tie:%s" % source,"emission_order":1,"time_seconds":0.0,
			"unit_id":source,"owner_player_id":77,"weapon_instance_id":"test_only:tie_weapon",
			"position":motion.records[test.target.unit_id].start,"velocity":Vector3(0,0,-ammo.initial_speed_mps),"ammo":ammo}
		flight = OrderedProjectileStep.new()
		flight.begin(timeline.projectiles,motion)
		flight.spawn(tie)
		timeline.fire.emission_order = 1
		timeline.settlement_prepare = func(_input): return {"ok":true,"affected_unit_ids":[test.unit.unit_id]}
		timeline.settlement_commit = func(_input):
			test.weapon.enabled = false
			return {"ok":true}
		result = timeline.step(test.aiming,motion)
		check(not timeline.halted and result.settlements[0].input.time_seconds == 0.0,"real fire/impact exact-time tie")
		check(result.emissions.size() == (0 if lower_source else 1),"stable source ID decides fire/impact tie before debit")
		timeline.projectiles.collision.close()
		timeline.settlement_prepare = Callable()
		timeline.settlement_commit = Callable()
	# Direct raw-simulation handoff retains zero-valued fields and missing values.
	var sim := DB29ProjectileSimulation.new()
	check(sim.configure_bounds(Rect2(-1,-1,2,2)),"exit bounds configured")
	var exit_event := {"event_id":"test_only:exit","emission_order":1,"time_seconds":0.0,
		"unit_id":123,"owner_player_id":0,"weapon_instance_id":"test_only:exit_weapon",
		"position":Vector3(0,2,0),"velocity":Vector3(ammo.initial_speed_mps,0,0),"ammo":ammo}
	sim.step([exit_event])
	var inputs := sim.take_settlement_inputs()
	check(inputs.size() == 1 and inputs[0].kind == "battlefield_exit" and not inputs[0].has("hit_unit_id"),"battlefield exit distinct from damage-capable impact")
	check(sim.take_settlement_inputs().is_empty(),"raw terminal handoff drains once")
	var missing_ammo := AmmoDefinition.new()
	missing_ammo.ammo_id = "test_only:missing"
	var values := ProjectileSettlementInput.ammunition(missing_ammo)
	check(values.nominal_damage == null and values.initial_speed_mps == null,"unconfigured numeric fields remain null not zero")
	check(ProjectileSettlementInbox.values_only(values),"missing fields serialize without NaN")
	sim.collision.close()
	var a := {"time_seconds":1.0,"unit_id":2,"weapon_instance_id":"w","source_event_id":"e","terminal":false}
	var b := a.duplicate()
	b.terminal = true
	check(CombatEventOrder.before(a,b) and not CombatEventOrder.before(b,a),"same lifecycle emission before terminal")
	b.unit_id = 1
	check(CombatEventOrder.before(b,a),"stable source identity can place terminal before another emission")
	b.time_seconds += 0.0000000001
	check(CombatEventOrder.before(a,b),"actual time wins without added time-merge tolerance")
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == formal_hash,"formal DATA preserved")
	check(FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == fixture_hash,"frozen fixture preserved")
	print("Prototype 0.6A: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
