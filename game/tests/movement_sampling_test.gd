extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL movement sample: "+label)

func config() -> MovementConfig:
	var value := MovementConfig.new()
	value.minimum_xz = Vector2.ZERO
	value.maximum_xz = Vector2(40,40)
	value.ground_height = 0.5
	value.navigation_cell_size = 1.0
	return value

func unit(id: int,vehicle: bool = false) -> UnitState:
	var definition := UnitDefinition.new()
	definition.configuration_source = "test_only:movement_sampling"
	definition.resource_name = "test_only_movement_sampling"
	definition.member_count = 1
	definition.protection_kinetic = 6.0
	definition.protection_chemical = 6.0
	definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE if vehicle else UnitDefinition.UnitType.INFANTRY
	definition.hardened_speed = 6.0
	definition.unhardened_speed = 6.0
	var value := UnitState.new(id,42,Vector3(10,0.5,10))
	value.configure(1,definition)
	return value

func movement(units: Array[UnitState]) -> MovementSimulation:
	var value := MovementSimulation.new(config())
	check(value.initialize_navigation(PrototypeMapDefinition.new()),"isolated test map initializes")
	for state: UnitState in units: value.add_unit(state)
	return value

func armed(unit_value: UnitState) -> RuntimeWeaponInstance:
	var definition := unit_value.definition
	var gun := ConfirmedGameData.new().weapon("W_M4A1")
	gun.required_operators = 1 # Missing-field test fixture only.
	gun.aim_min_seconds = 0.1
	gun.aim_max_seconds = 0.1
	gun.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY]
	gun.moving_aim_qualification = 0
	gun.reduction_ignore = 0.0
	gun.spread_radius_m = 0.0
	var allocation := WeaponAllocation.new()
	allocation.definition = gun
	allocation.member_id = 1
	allocation.retention_priority = 1
	allocation.initial_inventory = {"A_556":150}
	definition.weapon_allocations.append(allocation)
	unit_value.configure(1,definition)
	return unit_value.runtime_weapons[0]

func run() -> void:
	var h := GravityBallistics.STEP_SECONDS
	var soldier := unit(1)
	var sampled := movement([soldier])
	var legacy_unit := unit(1)
	var legacy := movement([legacy_unit])
	var destination := Vector3(10,0.5,2)
	check(sampled.request_move(1,42,destination) == "" and legacy.request_move(1,42,destination) == "","same actual movement command accepted")
	var old_position := soldier.position
	var old_member := soldier.members[0].position
	var result := sampled.advance_sampled(0.0)
	var expected := legacy.advance(h)
	check(result.reason == "" and result.motion.ready,"real movement creates valid shared motion frame")
	check(soldier.position == legacy_unit.position and soldier.members[0].position == legacy_unit.members[0].position,"adapter preserves legacy movement and member-follow results")
	check(result.changed == expected,"existing changed-position interface preserved")
	check(result.motion.records[1].start == old_member,"step start sampled before movement")
	check(result.motion.records[1].end == soldier.members[0].position,"step end sampled after actual member following")
	check(result.velocities[1].distance_to((soldier.position-old_position)/h) < 0.00001,"observed displacement velocity from same interval")
	var progressed := soldier.position
	check(sampled.advance_sampled(0.0).reason == "movement_sample_clock_mismatch" and soldier.position == progressed,"duplicate sample time cannot move twice")
	check(sampled.advance(1.0).is_empty() and soldier.position == progressed,"legacy update cannot mutate sampled authority")
	check(sampled.advance_sampled(h).reason == "" and soldier.position != progressed,"next sequential fixed step works after input rejection")
	check(sampled.advance_sampled(NAN).motion == null,"nonfinite sample time rejected")
	check(sampled.advance_sampled(h*10).reason == "movement_sample_clock_mismatch","large time gap not silently merged")
	var vehicle := unit(2,true)
	vehicle.yaw = -PI/2.0
	var moving_vehicle := movement([vehicle])
	check(moving_vehicle.request_move(2,42,Vector3(20,0.5,10)) == "","vehicle straight translation command accepted")
	result = moving_vehicle.advance_sampled(0.0)
	check(result.reason == "" and result.motion.records[2].start != result.motion.records[2].end,"constant-orientation vehicle gets translated box sample")
	var rotating := unit(3,true)
	var rotating_movement := movement([rotating])
	check(rotating_movement.request_move(3,42,Vector3(20,0.5,10)) == "","turning vehicle uses actual existing movement")
	result = rotating_movement.advance_sampled(0.0)
	check(result.reason == "" and result.motion.ready and result.motion.records[3].changing,"actual rotation sampled with changing orientation")
	var once_yaw := rotating.yaw
	check(rotating_movement.advance_sampled(h).motion.ready and rotating.yaw != once_yaw,"next sequential rotating movement advances once")
	var lagging := unit(4)
	var follow := movement([lagging])
	lagging.members[0].position -= Vector3(0,0,1)
	var anchor := lagging.position
	result = follow.advance_sampled(0.0)
	check(result.reason == "" and lagging.position == anchor,"parked anchor with member following sampled")
	check(result.motion.records[4].start != result.motion.records[4].end and result.velocities[4] != Vector3.ZERO,"member motion not misclassified as stationary source")
	var timeline := DB29CombatTimeline.new()
	var coordinated := unit(5)
	var coordinator_movement := movement([coordinated])
	var aiming := AimingSimulation.new()
	aiming.units = {5:coordinated}
	check(coordinator_movement.request_move(5,42,destination) == "","coordinator movement command accepted")
	result = timeline.step_movement(coordinator_movement,aiming)
	check(result.motion.ready and result.changed.has(5),"coordinator consumes actual movement sample")
	check(timeline.fire.time_seconds == h and timeline.projectiles.time_seconds == h,"movement and combat share fixed interval")
	check(aiming.target_velocities[5] != Vector3.ZERO,"observed translation shared with firing eligibility")
	result = timeline.step_movement(coordinator_movement,aiming)
	check(result.motion.time_seconds == h and timeline.fire.time_seconds == 2*h,"next frame uses combat time rather than caller dt")
	timeline.projectiles.collision.close()
	timeline = DB29CombatTimeline.new()
	var mismatch := AimingSimulation.new()
	var before := coordinated.position
	check(timeline.step_movement(coordinator_movement,mismatch).emissions.is_empty() and coordinated.position == before and timeline.failure_reason == "movement_combat_units_mismatch","mismatched authority rejected before movement")
	mismatch.units = {5:coordinated}
	# Align the new timeline to a fresh movement authority for retry verification.
	var fresh := unit(7)
	var fresh_movement := movement([fresh])
	mismatch.units = {7:fresh}
	check(timeline.step_movement(fresh_movement,mismatch).motion.ready and not timeline.halted and timeline.failure_reason == "","corrected authority does not retain stale error")
	timeline.projectiles.collision.close()
	var source := unit(8)
	var target := unit(9)
	var runtime := armed(source)
	source.position = Vector3(10,0.5,39)
	target.position = Vector3(10,0.5,1)
	target.team_id = 2
	target.yaw = -PI/2.0 # Align before the test interval to isolate translation.
	var real_movement := movement([source,target])
	aiming = AimingSimulation.new()
	aiming.units = {8:source,9:target}
	aiming.visibility = func(_s,_t): return true
	aiming.clear_path = func(_a,_b): return true
	aiming.moving = real_movement.is_moving
	runtime.bind_target(AttackTarget.unit(target))
	aiming.advance(3.0)
	timeline = DB29CombatTimeline.new()
	timeline.fire.fire_path_permission = func(_w,_a,_b,_i): return true
	result = timeline.step_movement(real_movement,aiming)
	check(result.emissions.size() == 1 and timeline.projectiles.active_slots.size() == 1,"real stationary sampled step emits into shared flight timeline")
	check(real_movement.request_move(9,42,Vector3(20,0.5,1)) == "","target moves through actual navigation on following step")
	result = timeline.step_movement(real_movement,aiming)
	var impacted := false
	for event: Dictionary in result.events:
		if event.reason == "impact" and event.hit_unit_id == 9: impacted = true
	check(impacted,"already-fired projectile hits target using actual sampled member motion")
	check(result.motion.records[9].start != result.motion.records[9].end,"collision frame records actual moving target")
	check(target.health == target.maximum_health,"movement sampling adds no damage settlement")
	timeline.projectiles.collision.close()
	source = unit(10)
	target = unit(11)
	runtime = armed(source)
	target.position = Vector3(10,0.5,2)
	target.team_id = 2
	real_movement = movement([source,target])
	aiming.units = {10:source,11:target}
	aiming.moving = real_movement.is_moving
	runtime.bind_target(AttackTarget.unit(target))
	aiming.advance(3.0)
	check(real_movement.request_move(10,42,Vector3(10,0.5,9.9)) == "","short source movement accepted")
	timeline = DB29CombatTimeline.new()
	timeline.fire.fire_path_permission = func(_w,_a,_b,_i): return true
	result = timeline.step_movement(real_movement,aiming)
	check(not real_movement.is_moving(10) and aiming.target_velocities[10] != Vector3.ZERO,"source finishes command but retains sampled step displacement")
	check(result.emissions.is_empty() and runtime.fire_state.reason == "moving_prohibited","sampled moving source with prohibited qualification cannot fire after step-end stop")
	timeline.projectiles.collision.close()
	timeline = DB29CombatTimeline.new()
	var bad := unit(6,true)
	var bad_movement := movement([bad])
	aiming.units = {6:bad}
	bad_movement.request_move(6,42,Vector3(20,0.5,10))
	result = timeline.step_movement(bad_movement,aiming)
	check(not timeline.halted and result.motion.ready and timeline.fire.time_seconds == h,"rotating sample advances coordinator under C authorization")
	# Invalid geometry still proves fail-stop behavior without treating rotation
	# as unsupported now that its approximation has explicit authorization.
	bad.definition.hitbox_half_extents = Vector3(-1,-1,-1)
	result = timeline.step_movement(bad_movement,aiming)
	check(timeline.halted and timeline.failure_reason == "invalid_unit_motion" and timeline.fire.time_seconds == h,"invalid geometry halts combat before firing or debit")
	before = bad.position
	once_yaw = bad.yaw
	check(timeline.step_movement(bad_movement,aiming).changed.is_empty() and bad.position == before and bad.yaw == once_yaw,"halted coordinator never advances movement again")
	timeline.projectiles.collision.close()
	var debt_unit := unit(40)
	var debt_movement := movement([debt_unit])
	aiming.units = {40:debt_unit}
	timeline = DB29CombatTimeline.new()
	check(timeline.advance(1.0,debt_movement,aiming).size() == 8,"coordinator callback advances at most eight whole steps")
	check(absf(timeline.fire.time_seconds-8.0*h) < 0.000001 and timeline.fire.time_seconds == timeline.projectiles.time_seconds,"movement/fire/projectiles share bounded callback progress")
	for i in range(3): timeline.advance(0.0,debt_movement,aiming)
	check(absf(timeline.fire.time_seconds-1.0) < 0.000001 and timeline.clock.completed_steps == 30,"coordinator drains all retained elapsed time")
	timeline.projectiles.collision.close()
	check(soldier.definition.configuration_source.begins_with("test_only:"),"generated configuration remains test-only")
	print("Movement sampling: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
