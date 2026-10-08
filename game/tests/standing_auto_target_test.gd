extends "res://tests/db29_combat_timeline_test.gd"

# Explicit TEST ONLY discovery. Production discovery and detection values are
# intentionally absent; no acceptance fixture flag or Q command enables auto.
func place(unit: UnitState,point: Vector3) -> void:
	var offset := point-unit.position
	unit.position = point
	for member: SoldierState in unit.members: member.position += offset

func normal_fixture(visible: bool = true) -> Dictionary:
	var test := fixture(1,"W_M4A1")
	test.timeline.projectiles.collision.close()
	var manager = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(manager)
	check(manager.configure_active_test_map(),"normal test navigation initialized")
	place(test.unit,Vector3(-18,0.5,108))
	place(test.target,Vector3(-18,0.5,96))
	test.weapon.clear_target() # Begin with zero aim and no command target.
	test.weapon.definition.moving_aim_qualification = 0 # TEST ONLY standing policy.
	for unit: UnitState in [test.unit,test.target]:
		manager._authoritative_units[unit.unit_id] = unit
		manager._movement.add_unit(unit)
		manager._combat.add_unit(unit)
		manager._register_combat_unit(unit)
	var known := {test.target.unit_id:true} if visible else {}
	if visible: manager.authoritative_visibility_provider = func(_owner,target): return known.has(target.unit_id)
	manager._aiming.units = manager._authoritative_units
	manager._aiming.visibility = manager._authoritative_target_visible
	manager._aiming.clear_path = manager._combat.has_line_of_sight
	manager._aiming.moving = manager._movement.is_moving
	manager._aiming.automatic_target_provider = manager._automatic_target
	test.manager = manager
	test.known = known
	test.aiming = manager._aiming
	return test

func enemy(test: Dictionary,id: int,point: Vector3,team: int = 2) -> UnitState:
	var unit := UnitState.new(id,43,point)
	unit.configure(team,test.target.definition)
	test.manager._authoritative_units[id] = unit
	test.manager._movement.add_unit(unit)
	test.manager._combat.add_unit(unit)
	test.known[id] = true
	return unit

func close_fixture(test: Dictionary) -> void:
	if test.manager._projectiles != null: test.manager._projectiles.collision.close()
	test.manager.free()

func selected(test: Dictionary) -> int:
	var candidate: AttackTarget = test.manager._automatic_target(test.weapon)
	return candidate.unit_id if candidate != null else 0

func hull_attack_move() -> void:
	var test := normal_fixture()
	var manager = test.manager
	var source: UnitState = test.unit
	source.configure(1,load("res://data/units/acceptance_06c_mechanical.tres"))
	var weapon: RuntimeWeaponInstance = source.runtime_weapons[0]
	place(test.target,source.position+Vector3(12,0,0)) # Side target requires Hull rotation.
	var initial := source.position
	var initial_yaw := source.yaw
	check(not manager.acceptance_full_06 and weapon.node_kind == WeaponAllocation.NodeKind.HULL,"normal armed vehicle probe uses real Hull weapon")
	check(manager._movement.request_move(source.unit_id,42,Vector3(-18,0,125),MovementSimulation.MoveMode.ATTACK).is_empty(),"Hull attack move route accepted")
	var route: PackedVector3Array = manager._movement._paths[source.unit_id].duplicate()
	var emissions: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	manager.weapon_fire_received.connect(func(event): emissions.append(event))
	manager.projectile_spawn_received.connect(func(event): spawns.append(event))
	var parked := true
	for tick: int in 90:
		manager._run_server_tick(PackedInt32Array())
		parked = parked and source.position == initial and manager._movement._engaging.has(source.unit_id)
		if not emissions.is_empty(): break
	print("HULL ATTACK MOVE PROBE: yaw=%s initial=%s target=%s aimed=%s emissions=%s spawns=%s parked=%s" % [source.yaw,initial_yaw,weapon.target.unit_id if weapon.target != null else 0,weapon.is_aimed,emissions.size(),spawns.size(),parked])
	check(parked and manager._movement._paths[source.unit_id] == route,"engaged Hull rotates without route deletion or translation")
	check(not is_equal_approx(source.yaw,initial_yaw) and weapon.aim_timer_complete and not emissions.is_empty() and not spawns.is_empty(),"normal parked Hull actually turns, aims and fires a real projectile")
	# Losing visibility releases the same route and movement owns facing again.
	test.known.clear()
	for tick: int in 90: manager._run_server_tick(PackedInt32Array())
	check(not manager._combat_timeline.halted and not manager._movement._engaging.has(source.unit_id) and source.position.distance_to(initial) > 0.1,"parked Hull resumes its route after target hidden")
	var ids: Array[int] = [source.unit_id]
	manager._movement.request_stop(ids,42)
	source.yaw = 0 # TEST ONLY isolate route-facing priority from previous turn.
	initial = source.position
	check(manager._movement.request_move(source.unit_id,42,Vector3(initial.x,0,initial.z-10),MovementSimulation.MoveMode.BASIC).is_empty(),"ordinary Hull movement route accepted")
	manager._movement.attack_facing_requests = {source.unit_id:-PI/2}
	var priority: Dictionary = manager._movement.advance_sampled(manager._combat_timeline.fire.time_seconds)
	check(priority.reason.is_empty() and is_equal_approx(source.yaw,0) and source.position.z < initial.z,"active ordinary movement preserves route-facing priority over weapon request")
	close_fixture(test)

func run() -> void:
	var test := normal_fixture()
	var manager = test.manager
	var weapon: RuntimeWeaponInstance = test.weapon
	check(not manager.acceptance_06c and not manager.acceptance_full_06 and manager._acceptance_auto_units.is_empty(),"ordinary mode has no fixture/Q enable gate")
	var initial: Vector3 = test.unit.position
	var health: float = test.target.health
	var emissions: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	manager.weapon_fire_received.connect(func(event): emissions.append(event))
	manager.projectile_spawn_received.connect(func(event): spawns.append(event))
	for tick: int in 90: manager._run_server_tick(PackedInt32Array())
	check(not emissions.is_empty() and not spawns.is_empty() and test.target.health < health,"ordinary auto target aims, fires real projectile and commits damage")
	check(not manager._combat_timeline.halted and test.unit.position == initial and manager._movement.active_command_ids().is_empty(),"standing fire does not install chase movement")
	close_fixture(test)

	test = normal_fixture(false)
	manager = test.manager
	weapon = test.weapon
	health = test.target.health
	for tick: int in 90: manager._run_server_tick(PackedInt32Array())
	check(weapon.target == null and weapon.fire_state.emission_count == 0 and manager._projectiles.profile.get("spawned",0) == 0 and test.target.health == health,"absent discovery provider never acquires/fires hidden enemies")
	check(manager._authoritative_target_visible(test.unit,AttackTarget.ground(Vector3.ZERO)),"forced ground visibility remains permitted")
	close_fixture(test)

	test = normal_fixture()
	manager = test.manager
	weapon = test.weapon
	# Pure query preserves binding, aim, fire, inventory and pending rounds.
	weapon.bind_target(AttackTarget.unit(test.target),false)
	weapon.aim_progress = 0.37
	weapon.sampled_aim_seconds = 0.8
	var snapshot := weapon.snapshot()
	check(selected(test) == test.target.unit_id and weapon.snapshot() == snapshot,"candidate scan is a pure weapon query")
	var second := enemy(test,test.target.unit_id+2,test.target.position+Vector3(0,0,-5))
	var nearer := enemy(test,test.target.unit_id+3,test.target.position+Vector3(0,0,5))
	check(selected(test) == nearer.unit_id,"nearest eligible candidate selected")
	manager._aiming._prepare()
	check(weapon.target.unit_id == test.target.unit_id and weapon.aim_progress == 0.37,"valid automatic target retained when closer enemy arrives")
	var tie_point := weapon.world_position()+Vector3(0,0,-10)
	place(second,tie_point)
	place(nearer,tie_point)
	check(selected(test) == second.unit_id,"equal-distance ties use stable unit ID")
	place(second,test.target.position+Vector3(0,0,-5))
	place(nearer,test.target.position+Vector3(0,0,5))
	for reason: String in ["death","hidden","range","path","type","friendly"]:
		weapon.bind_target(AttackTarget.unit(test.target),false)
		var old_position: Vector3 = test.target.position
		var old_types: Array[int] = weapon.definition.allowed_target_types.duplicate()
		if reason == "death": test.target.health = 0
		if reason == "hidden": test.known.erase(test.target.unit_id)
		if reason == "range": place(test.target,initial+Vector3(0,0,-weapon.definition.range_m-10))
		if reason == "path": manager._aiming.clear_path = func(_a,b): return b != test.target.position
		if reason == "type":
			test.target.definition = test.target.definition.duplicate()
			test.target.definition.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
		if reason == "friendly": test.target.team_id = test.unit.team_id
		manager._aiming._prepare()
		check(weapon.target != null and weapon.target.unit_id == nearer.unit_id,"automatic target reselected after "+reason)
		test.target.health = health
		test.known[test.target.unit_id] = true
		place(test.target,old_position)
		test.target.definition.unit_type = UnitDefinition.UnitType.INFANTRY
		test.target.team_id = 2
		weapon.definition.allowed_target_types = old_types
		manager._aiming.clear_path = manager._combat.has_line_of_sight

	weapon.clear_target()
	weapon.enabled = false
	check(selected(test) == 0,"disabled channel cannot acquire")
	weapon.enabled = true
	var stock := weapon.inventory.duplicate()
	weapon.inventory.clear()
	check(selected(test) == 0,"empty stock cannot acquire")
	weapon.inventory = stock.duplicate()
	var old_node: WeakRef = weapon.node
	weapon.node = weakref(RefCounted.new())
	check(selected(test) == 0,"expired node rejected before spatial lookup")
	weapon.node = old_node
	var source_health: float = test.unit.health
	test.unit.health = 0
	check(selected(test) == 0,"dead owner cannot acquire")
	test.unit.health = source_health
	var indirect: AmmoDefinition = weapon.definition.ammo_definitions[0]
	indirect.distance_selected_launch = true
	check(selected(test) == 0,"indirect class has no automatic acquisition")
	indirect.distance_selected_launch = false
	weapon.bind_target(AttackTarget.unit(second),true)
	place(second,initial+Vector3(0,0,-weapon.definition.range_m-10))
	manager._aiming._prepare()
	check(weapon.target.unit_id == second.unit_id and weapon.manual_target and weapon.eligibility_reason == "out_of_range","manual target priority persists out of range")
	place(second,test.target.position+Vector3(0,0,-5))
	manager._aiming.clear_path = func(_a,_b): return false
	manager._aiming._prepare()
	check(weapon.target.unit_id == second.unit_id and weapon.manual_target and weapon.eligibility_reason == "path_blocked","manual target priority persists blocked path")
	manager._aiming.clear_path = manager._combat.has_line_of_sight
	weapon.bind_target(AttackTarget.unit(test.target),false)
	weapon.aim_progress = 0.37
	weapon.sampled_aim_seconds = 0.8
	weapon.enabled = false
	manager._aiming.advance(0.1)
	check(weapon.target.unit_id == test.target.unit_id and weapon.aim_progress == 0.37 and weapon.sampled_aim_seconds == 0.8,"disabled automatic channel pauses aim without reset")
	weapon.enabled = true
	weapon.inventory.clear()
	manager._aiming.advance(0.1)
	check(weapon.target.unit_id == test.target.unit_id and weapon.aim_progress == 0.37,"no ammo pauses automatic target and aim")
	weapon.inventory = stock.duplicate()
	var ids: Array[int] = [test.unit.unit_id]
	check(manager._movement.request_move(test.unit.unit_id,42,Vector3(-18,0,125),MovementSimulation.MoveMode.BASIC).is_empty(),"ordinary move command accepted")
	manager._aiming.advance(0.1)
	check(weapon.target.unit_id == test.target.unit_id and weapon.aim_progress == 0.37,"moving channel preserves target/aim without chasing")
	weapon.clear_target()
	check(selected(test) == 0,"stationary-only channel cannot acquire while moving")
	manager._movement.request_stop(ids,42)
	check(manager._movement.request_move(test.unit.unit_id,42,Vector3(-18,0,125),MovementSimulation.MoveMode.ATTACK).is_empty(),"ordinary attack move command accepted")
	manager._update_automatic_engagement()
	check(manager._movement._engaging.has(test.unit.unit_id) and weapon.target != null,"ordinary attack move parks using common selector")
	initial = test.unit.position
	manager._movement.advance(0.1)
	check(test.unit.position == initial,"eligible attack mover remains parked")
	test.known.clear()
	manager._update_automatic_engagement()
	manager._aiming._prepare()
	manager._movement.advance(1.0)
	check(not manager._movement._engaging.has(test.unit.unit_id) and weapon.target == null and test.unit.position.distance_to(initial) > 0.1,"attack route resumes when disclosed targets disappear")
	close_fixture(test)

	# Two different model channels share an owner but select independently by
	# their own range. No channel binds or resets the other channel's state.
	test = normal_fixture()
	manager = test.manager
	var second_model := fixture(1,"W_M249")
	second_model.timeline.projectiles.collision.close()
	var definition: UnitDefinition = test.unit.definition.duplicate()
	definition.member_count = 2
	definition.weapon_allocations = []
	var rifle: WeaponAllocation = test.unit.definition.weapon_allocations[0].duplicate()
	var support: WeaponAllocation = second_model.unit.definition.weapon_allocations[0].duplicate()
	support.member_id = 2
	definition.weapon_allocations.assign([rifle,support])
	test.unit.configure(1,definition)
	check(test.unit.runtime_weapons.size() == 2,"different weapon models have independent runtime channels")
	if test.unit.runtime_weapons.size() == 2:
		var a: RuntimeWeaponInstance = test.unit.runtime_weapons[0]
		var b: RuntimeWeaponInstance = test.unit.runtime_weapons[1]
		a.definition.range_m = 5 # TEST ONLY per-channel qualification probes.
		b.definition.range_m = 40
		manager._aiming._prepare()
		check(a.target == null and b.target != null and b.target.unit_id == test.target.unit_id,"channels independently acquire according to range")
		a.definition.range_m = 40
		b.aim_progress = 0.37
		manager._aiming._prepare()
		check(a.target != null and a.target.unit_id == test.target.unit_id and b.target.unit_id == test.target.unit_id and b.aim_progress == 0.37,"second channel acquisition preserves first target and aim")
	close_fixture(test)
	hull_attack_move()
	print("STANDING AUTO TARGET: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
