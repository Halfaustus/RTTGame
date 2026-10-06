extends SceneTree

var checks := 0
var failures := 0
var data := ConfirmedGameData.new()
var serial := 5000

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL fixed combat: "+label)

func fixture(count: int,id: String = "W_M249") -> Dictionary:
	serial += 10
	var definition := UnitDefinition.new()
	definition.configuration_source = "test_only:fixed_combat_generated"
	definition.resource_name = "test_only_fixed_combat_generated"
	definition.member_count = count
	var weapon := data.weapon(id)
	# Missing eligibility only, formal performance never overridden.
	if weapon.required_operators < 0: weapon.required_operators = 1
	if not is_finite(weapon.aim_min_seconds):
		weapon.aim_min_seconds = 0.1
		weapon.aim_max_seconds = 0.1
	if weapon.moving_aim_qualification < 0: weapon.moving_aim_qualification = 0
	weapon.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY]
	weapon.reduction_ignore = 0.0
	weapon.spread_radius_m = 0.0 # TEST ONLY exact-path fixture; not DATA spread.
	weapon.temporary_fields.assign(["test_only:aim","test_only:operators_if_missing","test_only:moving_eligibility","test_only:target_type","test_only:ignore","test_only:spread"])
	for index in range(count):
		var allocation := WeaponAllocation.new()
		allocation.definition = weapon
		allocation.member_id = index+1
		allocation.retention_priority = 0 if weapon.squad_weapon else 1
		for ammo: AmmoDefinition in weapon.ammo_definitions:
			allocation.initial_inventory[ammo.ammo_id] = int(data.number(data.record("Ammo",ammo.ammo_id),"Initial_Inventory_rounds"))
		definition.weapon_allocations.append(allocation)
	var unit := UnitState.new(serial,42,Vector3.ZERO)
	unit.owner_player_id = 42
	unit.configure(1,definition)
	var target_definition := UnitDefinition.new()
	target_definition.configuration_source = "test_only:stationary_target"
	target_definition.member_count = 1
	target_definition.protection_kinetic = 6
	target_definition.protection_chemical = 6
	var target := UnitState.new(serial+1,43,Vector3(0,0,-30))
	target.configure(2,target_definition)
	var aiming := AimingSimulation.new()
	aiming.units = {unit.unit_id:unit,target.unit_id:target}
	aiming.visibility = func(_owner,_target): return true
	aiming.clear_path = func(_a,_b): return true
	aiming.moving = func(_id): return false
	var runtime: RuntimeWeaponInstance = unit.runtime_weapons[0]
	runtime.bind_target(AttackTarget.unit(target))
	aiming.advance(3.0) # Existing 05D establishes readiness before fixed chain.
	var timeline := DB29CombatTimeline.new()
	timeline.fire.fire_path_permission = func(_weapon,_a,_b,_inputs): return true # Explicit TEST ONLY friendly-path permission.
	return {"unit":unit,"target":target,"weapon":runtime,"aiming":aiming,"timeline":timeline}

func run() -> void:
	var digest := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var test := fixture(400)
	var timeline: DB29CombatTimeline = test.timeline
	var weapon: RuntimeWeaponInstance = test.weapon
	var before: int = weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id]
	var result := timeline.step(test.aiming)
	var emissions: Array = result.emissions
	check(emissions.size() == 6,"formal 2.4/400 interval allows six shots in one 30Hz step")
	check(test.unit.runtime_weapons.size() == 1 and weapon.configured_count == 400,"one fixed-N channel not 400 independent timers")
	for index in range(emissions.size()):
		check(absf(emissions[index].time_seconds-index*0.006) < 0.0000001,"actual due time "+str(index))
	check(weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id] == before-18,"atomic triplet stock debit per actual emission")
	check(weapon.pending_rounds == weapon.definition.capacity-18,"pending rounds debited once")
	check(timeline.projectiles.profile.spawned == 6,"real scheduler feeds real DB29 consumer")
	check(timeline.fire.time_seconds == timeline.projectiles.time_seconds,"shared fixed-step clock")
	check(absf(weapon.fire_state.interval_remaining-(0.036-GravityBallistics.STEP_SECONDS)) < 0.0000001,"interval residual retains next absolute due time")
	var late: Dictionary = timeline.projectiles.slots[timeline.projectiles.active_ids[emissions.back().event_id]]
	var expected := GravityBallistics.segment(emissions.back().position,emissions.back().velocity,GravityBallistics.STEP_SECONDS-0.03)
	check(late.position.distance_to(expected.position) < 0.00001,"actual late emission only residual flight")
	check(emissions[0].ammo == weapon.definition.ammo_definitions[0],"selected cached formal ammo reference")
	check(absf(emissions[0].velocity.length()-900.0) < 0.001,"confirmed speed used by actual firing solver")
	check(timeline.fire.profile.ballistic_solves == 6 and timeline.fire.profile.spread_samples == 6,"solve and dispersion once per actual stationary emission")
	var old_clock := timeline.fire.time_seconds
	check(timeline.fire.advance(1.0,100,test.aiming).is_empty() and timeline.fire.time_seconds == old_clock,"legacy timing cannot mutate fixed chain")
	timeline.projectiles.collision.close()
	test = fixture(1,"W_M4A1")
	timeline = test.timeline
	weapon = test.weapon
	weapon.fire_state.interval_remaining = 0.01
	result = timeline.step(test.aiming)
	check(result.emissions.size() == 1 and absf(result.emissions[0].time_seconds-0.01) < 0.000001,"N1 formal rifle fires at interval completion inside step")
	check(absf(weapon.fire_state.interval_remaining-(7.2-(GravityBallistics.STEP_SECONDS-0.01))) < 0.000001,"N applied once and post-emission residual removed")
	check(timeline.step(test.aiming).emissions.is_empty(),"formal rifle cannot fire again next step")
	check(weapon.fire_state.reason == "interval" and weapon.fire_state.phase == WeaponFireState.Phase.INTERVAL,"blocked countdown reports authoritative interval phase")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.fire_state.loading = true
	var duration := weapon.loading_seconds()
	weapon.fire_state.loading_progress = 1.0-0.012/duration
	weapon.pending_rounds = 0
	result = timeline.step(test.aiming)
	check(result.emissions.size() == 1 and absf(result.emissions[0].time_seconds-0.012) < 0.000001,"existing preparation completes at actual substep time")
	check(weapon.pending_rounds == weapon.definition.capacity-3,"loading readiness does not add or double-debit inventory")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	before = weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id]
	timeline.fire.fire_path_permission = func(_w,_a,_b,_i): return false
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "friendly_blocked","friendly refusal before commit")
	check(weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id] == before and weapon.fire_state.emission_count == 0,"failed firing never consumes rounds")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.is_aimed = false
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "not_aimed","05D readiness remains authoritative")
	weapon.is_aimed = true
	test.aiming.target_velocities[test.target.unit_id] = Vector3(1,0,0)
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "motion_timeline_not_integrated","moving snapshot not mistaken for firing-time state")
	test.aiming.target_velocities.clear()
	weapon.definition.ammo_definitions[0].initial_speed_mps = NAN
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "projectile_configuration_missing","unconfigured speed explicit refusal")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.definition.spread_radius_m = NAN
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "spread_configuration_missing","no old spread fallback")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.definition.game_projectile_interval = 0.0
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "fire_configuration_missing","zero interval without per-shot preparation refuses")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.fire_state.interval_remaining = GravityBallistics.STEP_SECONDS
	result = timeline.step(test.aiming)
	check(result.emissions.size() == 1 and result.events.size() == 1,"step-end due event emitted exactly once")
	if result.emissions.size() == 1:
		var edge: Dictionary = timeline.projectiles.slots[0]
		check(edge.position == result.emissions[0].position,"step-end shot has no pre-emission movement")
	check(timeline.step(test.aiming).emissions.is_empty(),"step endpoint not repeated in following step")
	timeline.projectiles.collision.close()
	var other := fixture(1,"W_M4A1")
	test = fixture(1)
	timeline = test.timeline
	var first_weapon: RuntimeWeaponInstance = other.weapon
	var second_weapon: RuntimeWeaponInstance = test.weapon
	first_weapon.fire_state.interval_remaining = 0.02
	second_weapon.fire_state.interval_remaining = 0.01
	# Deliberately reversed due order in storage. Shared heap must sort events.
	other.aiming.units.merge(test.aiming.units)
	result = timeline.step(other.aiming)
	check(result.emissions.size() == 2 and result.emissions[0].weapon_instance_id == second_weapon.instance_id,"global chronological order across independent channels")
	check(result.emissions[1].emission_order == result.emissions[0].emission_order+1,"ordered consumer stream retains monotonic emission identity")
	timeline.projectiles.collision.close()
	other.timeline.projectiles.collision.close()
	other = fixture(1)
	test = fixture(1)
	timeline = test.timeline
	other.aiming.units.merge(test.aiming.units)
	result = timeline.step(other.aiming)
	check(result.emissions.size() == 2 and result.emissions[0].weapon_instance_id < result.emissions[1].weapon_instance_id,"equal-time channel tie uses stable identity")
	timeline.projectiles.collision.close()
	other.timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	timeline.projectiles.collision.box("test_wall","obstacle",Vector3(3,3,0.01),Transform3D(Basis.IDENTITY,Vector3(0,0,-5)))
	result = timeline.step(test.aiming)
	check(result.emissions.size() == 1 and result.events.size() == 2 and result.events[1].reason == "impact","actual firing event consumed and collides in same physical step")
	check(result.events[1].time_seconds > result.events[0].time_seconds and result.events[1].time_seconds < GravityBallistics.STEP_SECONDS,"fire and impact share one time axis")
	check(test.target.health == test.target.maximum_health,"new timeline never applies damage")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	weapon = test.weapon
	weapon.definition.range_m = 1000000.0 # TEST ONLY range, not formal weapon change.
	test.target.position = Vector3(0,0,-100000)
	before = weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id]
	check(timeline.step(test.aiming).emissions.is_empty() and weapon.fire_state.reason == "intercept_unreachable","unreachable low arc refuses without high fallback")
	check(weapon.inventory[weapon.definition.ammo_definitions[0].ammo_id] == before,"unreachable shot not debited")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	var snapshots := ProjectileUnitMotion.capture(test.aiming.units)
	var motion := ProjectileUnitMotion.new()
	check(motion.configure(0.0,snapshots,snapshots),"real generated units share valid step snapshots")
	result = timeline.step(test.aiming,motion)
	check(result.emissions.size() == 1 and result.events.size() == 2 and result.events[1].hit_unit_id == test.target.unit_id,"real fixed firing chain hits unit through motion frame")
	check(test.target.health == test.target.maximum_health,"relative unit collision does not apply damage")
	var completed_time := timeline.fire.time_seconds
	check(timeline.step(test.aiming,motion).emissions.is_empty() and timeline.fire.time_seconds == completed_time,"stale unit frame cannot advance firing or debit")
	timeline.projectiles.collision.close()
	test = fixture(1)
	timeline = test.timeline
	snapshots = ProjectileUnitMotion.capture(test.aiming.units)
	var ending := snapshots.duplicate(true)
	snapshots[9999] = {"center":Vector3(10,0,-15),"extents":Vector3.ONE*0.5,"basis":Basis.IDENTITY,"team_id":1,"unit_type":UnitDefinition.UnitType.ARMORED_VEHICLE}
	ending[9999] = snapshots[9999].duplicate(true)
	ending[9999].center = Vector3(-10,0,-15)
	motion = ProjectileUnitMotion.new()
	check(motion.configure(0.0,snapshots,ending),"crossing friendly unit frame builds once")
	result = timeline.step(test.aiming,motion)
	check(result.emissions.size() == 1 and result.events.size() == 2 and result.events[1].hit_unit_id == 9999,"post-emission crossing friend blocks actual fired projectile")
	timeline.projectiles.collision.close()
	test = fixture(4)
	timeline = test.timeline
	var debt_ammo_id: String = test.weapon.definition.ammo_definitions[0].ammo_id
	var debt_stock: int = test.weapon.inventory[debt_ammo_id]
	var clock := FixedStepClock.new()
	var debt_emissions: Array[Dictionary] = []
	var callback := func() -> bool:
		debt_emissions.append_array(timeline.step(test.aiming).emissions)
		return not timeline.halted
	check(clock.advance(1.0,callback) == 8 and debt_emissions.size() == 1,"bounded callback emits only shots in completed steps")
	for i in range(3): clock.advance(0.0,callback)
	check(clock.completed_steps == 30 and debt_emissions.size() == 2,"backlog emits every due shot without one-per-callback rule")
	check(absf(debt_emissions[1].time_seconds-0.6) < 0.000001 and debt_emissions[1].emission_order == 2,"retained shot preserves actual time and emission order")
	check(test.weapon.inventory[debt_ammo_id] == debt_stock-2*test.weapon.definition.consumption_per_projectile,"retained emissions debit formal consumption exactly once")
	timeline.projectiles.collision.close()
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == digest,"generated configuration never modifies formal DATA")
	print("DB29 fixed combat: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
