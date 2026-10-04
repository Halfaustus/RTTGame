extends SceneTree

var checks := 0
var failures := 0
var catalog := Prototype05DCatalog.new()
var aim := AimingSimulation.new()
var visible := true
var clear := true
var moving := false
var next_id := 1
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL 0.5D: "+label)
func unit(definition: UnitDefinition, position: Vector3 = Vector3.ZERO) -> UnitState:
	var state := UnitState.new(next_id,42,position)
	next_id += 1
	state.configure(1,definition)
	aim.units[state.unit_id] = state
	return state
func tick(seconds: float) -> void:
	for index: int in ceili(seconds*60): aim.advance(minf(1.0/60,seconds-index/60.0))
func fixture(id: String) -> UnitState:
	var definition := UnitDefinition.new()
	definition.member_count = 1
	var inventory: Dictionary = catalog.default_inventory.get(id,{})
	if id == "recoilless": inventory = {"recoilless_ap":4,"recoilless_he":4}
	if id == "rocket": inventory = {"rocket_ap":1} # One launcher only in isolated fixture.
	catalog.allocate(definition,id,WeaponAllocation.NodeKind.SOLDIER,"1","primary",inventory)
	return unit(definition)
func run() -> void:
	aim.visibility = func(_owner,_target): return visible
	aim.clear_path = func(_a,_b): return clear
	aim.moving = func(_id): return moving
	var target := unit(UnitDefinition.new(),Vector3(0,0,-10))
	target.team_id = 2
	for id: String in ["pdw","rifle","lmg","recoilless","rocket"]:
		var shooter := fixture(id)
		var weapon := shooter.runtime_weapons[0]
		weapon.bind_target(AttackTarget.unit(target))
		for offset: float in [-0.01,0.0,0.01]:
			target.position = weapon.world_position()+Vector3(0,0,-(weapon.definition.range_m+offset))
			check((aim.eligibility(weapon) == "eligible") == (offset <= 0),id+" range "+str(offset))
	check(catalog.weapons.rifle.ammo_definitions[0] == catalog.weapons.lmg.ammo_definitions[0],"shared standard ammo")
	check(catalog.weapons.lmg.range_m == 600 and catalog.weapons.lmg.ammo_definitions[0].anchor_distance_m == 400,"independent range and decay endpoint")
	var lmg := fixture("lmg").runtime_weapons[0]
	target.position = lmg.world_position()+Vector3(0,0,-500)
	lmg.bind_target(AttackTarget.unit(target))
	check(aim.eligibility(lmg) == "eligible","LMG five hundred meters beyond ammo anchor")
	check(WeaponDefinition.new().range_m == -1 and WeaponDefinition.new().aim_min_seconds == -1,"unknown not eight meters or zero seconds")
	var assault := unit(catalog.squad(true))
	var defense := unit(catalog.squad(false))
	check(assault.members.size() == 8 and assault.health == 40 and defense.health == 40,"eight people five health")
	check(assault.runtime_weapons.size() == 8 and defense.runtime_weapons.size() == 8,"no extra rifle or inferred five launchers")
	check(assault.weapon_summary()[0].count == 2 and assault.weapon_summary()[0].ammunition.recoilless_ap == 8 and assault.weapon_summary()[0].ammunition.recoilless_he == 8,"two guns sixteen total rounds")
	check(assault.weapon_summary()[1].count == 6 and assault.weapon_summary()[1].ammunition.standard == 900,"six rifles 900 rounds")
	check(defense.weapon_summary()[0].ammunition.standard == 1500 and defense.weapon_summary()[1].ammunition.standard == 900,"defense ammo totals")
	check(defense.unassigned_inventory.rocket_ap == 5,"unassigned squad stock")
	check(defense.unassigned_weapon_stock()[0].count == null and defense.unassigned_weapon_stock()[0].assignment_pending,"rocket count not inferred from five stock")
	check(catalog.weapons.shotgun.capacity == 10 and catalog.default_inventory.shotgun.shotgun == 50 and catalog.weapons.shotgun.game_projectile_interval == 1 and catalog.weapons.shotgun.range_m == -1,"confirmed shotgun data preserved with unknown range")
	check(assault.definition.weapon_allocations[0].occupied_slots.size() == 2,"gun reserves primary secondary")
	var invalid := catalog.squad(true)
	catalog.allocate(invalid,"rifle",WeaponAllocation.NodeKind.SOLDIER,"1","secondary",{"standard":150})
	check(not invalid.weapon_allocations_valid(),"reserved operator secondary rejects overlapping weapon")
	var another := unit(assault.definition)
	check(another.runtime_weapons[0] != assault.runtime_weapons[0] and another.runtime_weapons[0].definition == assault.runtime_weapons[0].definition and another.runtime_weapons[0].instance_id != assault.runtime_weapons[0].instance_id,"unique runtime shared definition")
	another.runtime_weapons[0].inventory.recoilless_ap = 0
	check(assault.runtime_weapons[0].inventory.recoilless_ap == 4,"independent inventory")
	for model: String in ["a","b","c"]:
		var vehicle := unit(catalog.weapon_slot_fixture(model))
		check(vehicle.mounts.size() == 2 and vehicle.runtime_weapons.size() == (4 if model == "c" else 3),model+" weapon mount counts")
		check(vehicle.runtime_weapons[1].definition.capacity == 450 and vehicle.runtime_weapons[1].inventory.standard == 2250,model+" vehicle MG stock")
		check(vehicle.runtime_weapons[0].spatial_node() == vehicle.mounts[0] and vehicle.runtime_weapons[2].spatial_node() == vehicle.mounts[1],model+" spatial ownership")
		check(vehicle.definition.resource_name == "isolated_weapon_slot_fixture", "independent weapon fixture, no retired vehicle identity")
	var vehicle := unit(catalog.weapon_slot_fixture("c"))
	var main := vehicle.runtime_weapons[0]
	var coax := vehicle.runtime_weapons[1]
	var commander := vehicle.runtime_weapons[2]
	target.position = Vector3(0,0,100)
	main.bind_target(AttackTarget.unit(target))
	aim.advance(0.5)
	check(is_equal_approx(absf(vehicle.mounts[0].world_yaw),deg_to_rad(60)),"main 120 degrees per second")
	aim.advance(1)
	check(is_equal_approx(absf(vehicle.mounts[0].world_yaw),PI),"180 degrees 1.5 seconds")
	var sample := main.sampled_aim_seconds
	check(sample >= 2 and sample <= 3,"sample two to three seconds")
	moving = true
	target.position.x = 5
	tick(1)
	check(sample == main.sampled_aim_seconds and main.aim_progress > 0,"moving cannon no re-sample")
	moving = false
	tick(3)
	check(main.is_aimed,"full aim timer and actual orientation")
	var other := unit(UnitDefinition.new(),Vector3(0,0,-100))
	other.team_id = 2
	coax.bind_target(AttackTarget.unit(other))
	commander.bind_target(AttackTarget.unit(other))
	tick(2)
	check(main.is_aimed and not coax.orientation_ready and commander.is_aimed,"independent readiness shared node conflict")
	var relative := vehicle.mounts[0].relative_aim_yaw
	vehicle.yaw += 0.3
	check(is_equal_approx(wrapf(vehicle.mounts[0].world_yaw-vehicle.yaw,-PI,PI),relative),"relative composition")
	tick(1)
	check(main.orientation_ready,"world aim recovers from hull rotation")
	var gun := assault.runtime_weapons[0]
	target.position = Vector3(0,0,-100)
	gun.bind_target(AttackTarget.unit(target))
	tick(1)
	check(gun.aim_progress > 0 and not gun.aim_timer_complete,"two seconds gun timer")
	moving = true
	aim.advance(0.1)
	check(gun.eligibility_reason == "moving_prohibited" and gun.aim_progress == 0,"prohibited movement clears aim")
	moving = false
	var rocket := fixture("rocket").runtime_weapons[0]
	rocket.bind_target(AttackTarget.unit(target))
	tick(1.01)
	check(rocket.is_aimed,"rocket one second timer")
	aim.inputs[rocket.owner_state().unit_id] = {"indoors":true}
	check(aim.eligibility(rocket) == "indoor_prohibited","rocket indoor denied")
	aim.inputs[assault.unit_id] = {"indoors":true}
	check(aim.eligibility(gun) == "eligible","gun indoor allowed")
	aim.inputs.clear()
	for condition: String in ["sprinting","return_fire_locked"]:
		aim.inputs[vehicle.unit_id] = {condition:true}
		aim.advance(0.1)
		check(not main.is_aimed and main.eligibility_reason == condition,"qualification "+condition)
		aim.inputs.clear()
	main.enabled = false
	aim.advance(0.1)
	check(main.aim_progress == 0 and main.eligibility_reason == "disabled","disabled reset")
	main.enabled = true
	main.bind_target(AttackTarget.unit(target))
	aim.advance(0.1)
	var progress := main.aim_progress
	aim.inputs[vehicle.unit_id] = {"aim_time_multiplier":5.0}
	aim.advance(0.1)
	check(main.aim_progress > progress and main.aim_progress-progress < 0.02,"incapacity keeps percentage")
	aim.inputs.clear()
	clear = false
	aim.advance(0.1)
	check(main.eligibility_reason == "path_blocked" and not main.is_aimed,"path check")
	clear = true
	visible = false
	aim.advance(0.1)
	check(main.target == null and main.aim_progress == 0,"lost visibility reset")
	visible = true
	main.bind_target(AttackTarget.unit(target))
	target.position = Vector3(0,0,-1100)
	aim.advance(0.1)
	check(main.eligibility_reason == "out_of_range" and not main.is_aimed,"range invalid")
	target.position = Vector3(0,0,-100)
	target.team_id = vehicle.team_id
	check(aim.eligibility(main) == "friendly_target","existing enemy team rule")
	target.team_id = 2
	main.definition.allowed_target_types.assign([WeaponDefinition.TargetType.GROUND_VEHICLE])
	check(aim.eligibility(main) == "type_not_allowed","explicit types")
	main.definition.allowed_target_types.append(WeaponDefinition.TargetType.INFANTRY)
	main.inventory.clear()
	check(aim.eligibility(main) == "ammunition_insufficient","ammo qualification")
	main.inventory = {"cannon_bc_ap":30,"cannon_bc_he":120}
	main.bind_target(AttackTarget.unit(other))
	check(main.aim_progress == 0 and main.sampled_aim_seconds == -1,"new target full sample")
	var hp := other.health
	var inventory := main.inventory.duplicate()
	var pending := main.pending_rounds
	tick(30)
	check(other.health == hp and main.inventory == inventory and main.pending_rounds == pending,"long wait never fires or consumes ammo")
	other.health = 0
	aim.advance(0.1)
	check(main.target == null and not main.is_aimed,"dead target removed")
	check(vehicle.structure_snapshot().weapons.size() == 4 and not vehicle.snapshot().has("weapons"),"10 Hz internal state separate from v1")
	additional_checks()
	await integration()
	benchmark()
	print("0.5D: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func integration() -> void:
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	network._movement.initialize_navigation()
	network._ensure_deployment_ready()
	network._initialize_rebels()
	check(network._authoritative_units[1].runtime_weapons.size() == 8,"enemy initialized")
	network._peer_players[42] = 1
	network.deployment.register_player(1,1,0)
	var armed_entry := false
	for row: Dictionary in network.deployment.export_player(1).catalog:
		if row.config_id == "test.rifle": armed_entry = row.armed
	check(armed_entry,"new loadout advertises armed command eligibility")
	var purchase: Dictionary = network.deployment.buy_order(1,"test.rifle","ground.west")
	network.deployment.place_order(1,purchase.order_id,Vector3(10,0,110))
	for frame: int in 180: network._run_server_tick(PackedInt32Array([42]))
	var order: Dictionary = network.deployment._orders[purchase.order_id]
	check(order.status == "generated" and network._authoritative_units[order.unit_id].runtime_weapons.size() == 8,"purchased initialized")
	network.timeline.begin_tick()
	network.timeline.enter_phase("session")
	network._apply_peer_join(77)
	var valid := true
	for state: UnitState in network._authoritative_units.values():
		if state.owner_peer_id == 77: valid = valid and not state.runtime_weapons.is_empty()
	check(valid,"free initialized")
	network.timeline.enter_phase("replication")
	network.timeline.finish_tick()
	check(not network.bind_weapon_target(99,order.unit_id,network._authoritative_units[order.unit_id].runtime_weapons[0].instance_id,1),"owner validation")
	check(not network.bind_weapon_target(42,order.unit_id,network._authoritative_units[order.unit_id].runtime_weapons[0].instance_id,1),"owner cannot bind an unobserved enemy")
	var hp: float = network._authoritative_units[1].health
	for frame: int in 240: network._run_server_tick(PackedInt32Array([42]))
	check(network._authoritative_units[1].health == hp,"no production legacy firing")
	var stop_ids: Array[int] = [int(order.unit_id)]
	network._apply_stop(stop_ids,42)
	check(network._authoritative_units[order.unit_id].runtime_weapons[0].target == null,"existing stop cancels bound weapon target")
	network.free()
	await process_frame

func benchmark() -> void:
	for count: int in [8,64,128]:
		var scene := AimingSimulation.new()
		scene.visibility = func(_a,_b): return true # Explicit benchmark stubs.
		scene.clear_path = func(_a,_b): return true
		scene.moving = func(_id): return false
		var victim := UnitState.new(9999,0,Vector3(0,0,-100))
		victim.configure(2,UnitDefinition.new())
		scene.units[9999] = victim
		var weapons := 0
		for id: int in count:
			var state := UnitState.new(id+1,42,Vector3(id,0,0))
			state.configure(1,catalog.squad(true) if id%2 == 0 else catalog.weapon_slot_fixture("c"))
			scene.units[state.unit_id] = state
			weapons += state.runtime_weapons.size()
			for instance: RuntimeWeaponInstance in state.runtime_weapons: instance.bind_target(AttackTarget.unit(victim))
		var start := Time.get_ticks_usec()
		for frame: int in 120: scene.advance(1.0/60)
		var elapsed := Time.get_ticks_usec()-start
		check(scene.profile.eligibility_checks == weapons*120,"linear checks "+str(count))
		check(scene.profile.node_rotations == count/2*10*120,"shared node single rotation "+str(count))
		print("AIM_BENCH units=%d weapons=%d avg_us=%.2f checks_tick=%d rotations_tick=%d path_queries=0" % [count,weapons,elapsed/120.0,weapons,count/2*10])
		var serialization_start := Time.get_ticks_usec()
		var payload: Array[Dictionary] = []
		for state: UnitState in scene.units.values(): payload.append(state.structure_snapshot())
		var encoded := var_to_bytes(payload)
		print("AIM_REPLICATION units=%d bytes=%d build_encode_us=%d hz=10" % [count,encoded.size(),Time.get_ticks_usec()-serialization_start])

func additional_checks() -> void:
	var simulation := AimingSimulation.new()
	simulation.visibility = func(_a,_b): return true
	simulation.clear_path = func(_a,_b): return true
	simulation.moving = func(_id): return false
	var vehicle := UnitState.new(5000,42,Vector3(10,0.5,100))
	vehicle.configure(1,catalog.weapon_slot_fixture("c"))
	var target := UnitState.new(5001,0,Vector3(10,0.5,90))
	target.configure(2,UnitDefinition.new())
	simulation.units = {5000:vehicle,5001:target}
	var hull := vehicle.runtime_weapons[3]
	hull.bind_target(AttackTarget.unit(target))
	vehicle.yaw = PI/2
	simulation.advance(2)
	check(hull.aim_timer_complete and not hull.orientation_ready and not hull.is_aimed,"Hull timer alone cannot complete aim")
	var movement := MovementSimulation.new(preload("res://data/prototype_movement.tres"))
	movement.initialize_navigation()
	movement.add_unit(vehicle)
	movement.attack_facing_requests = simulation.hull_requests()
	var start_yaw := vehicle.yaw
	movement.advance(0.1)
	check(is_equal_approx(absf(wrapf(vehicle.yaw-start_yaw,-PI,PI)),deg_to_rad(vehicle.definition.turn_speed_degrees*0.1)),"isolated fixture Hull rotation follows explicit definition")
	check(movement.request_move(5000,42,Vector3(10,0,110)).is_empty(),"normal move accepted")
	var position := vehicle.position
	vehicle.yaw = 0
	movement.attack_facing_requests = {5000:0.0}
	movement.advance(0.1)
	check(vehicle.position == position and absf(vehicle.yaw) > 0,"movement turn priority and turn before translation")
	movement.request_stop([5000],42)
	vehicle.yaw = 0.3
	check(movement.request_move(5000,42,Vector3(10,0,110),MovementSimulation.MoveMode.REVERSE).is_empty(),"reverse accepted")
	movement.advance(0.1)
	check(is_equal_approx(vehicle.yaw,0.3),"reverse retains Hull facing")
	var squad := UnitState.new(5002,42,Vector3(15,0.5,100))
	squad.configure(1,catalog.squad(false))
	movement.add_unit(squad)
	simulation.units[5002] = squad
	var soldier_weapon := squad.runtime_weapons[2]
	soldier_weapon.bind_target(AttackTarget.unit(target))
	var member_position := squad.members[2].position
	simulation.advance(0.1)
	check(squad.members[2].aim_yaw != 0 and squad.members[2].position == member_position,"Soldier actual aim does not displace formation")
	movement.request_move(5002,42,Vector3(20,0,100))
	for frame: int in 120: movement.advance(1.0/60)
	check(squad.members[2].position != member_position and not squad.blocks_movement(),"real Soldier follow and overlap retained")
	check(squad.hit_members(squad.members[2].position-Vector3.UP,squad.members[2].position+Vector3.UP).has(3),"member hitbox retained")
	var cannon := vehicle.runtime_weapons[0]
	cannon.bind_target(AttackTarget.unit(target))
	var random_state := simulation.random.state
	simulation.advance(0.1)
	var sampled := cannon.sampled_aim_seconds
	cannon.bind_target(AttackTarget.unit(target))
	simulation.advance(0.1)
	check(cannon.sampled_aim_seconds == sampled,"same target binding never resamples")
	var replay_random := RandomNumberGenerator.new()
	replay_random.seed = Prototype05DCatalog.RANDOM_SEED
	replay_random.state = random_state
	check(is_equal_approx(sampled,replay_random.randf_range(2,3)),"fixed seed reproducible complete-aim sample")
	simulation.units.erase(5001)
	simulation.advance(0.1)
	check(cannon.target == null and cannon.eligibility_reason == "target_invalid","registry removal invalidates stable reference")
	squad.members[2].health = 0
	check(simulation.eligibility(soldier_weapon) == "owner_invalid","dead Soldier cannot retain aiming authority")
	var feed := PresentationFeed.new()
	var structure := vehicle.structure_snapshot()
	feed.apply_live_structure(structure)
	structure.weapons[0].aim_progress = 0.123
	check(feed.live_structures[vehicle.unit_id].weapons[0].aim_progress != 0.123,"presentation structure copied")
	var combat := CombatSimulation.new(PrototypeMapDefinition.new())
	vehicle.weapon = preload("res://data/weapon_mobile.tres") # Explicit old fixture, never formal default.
	combat.add_unit(vehicle)
	combat.add_unit(target)
	check(combat.advance(1,movement).shots.is_empty(),"new runtime blocked from old prototype firing")
	var unknown := WeaponDefinition.new()
	var slot_definition := WeaponSlotDefinition.new()
	slot_definition.weapon = unknown
	var configured := UnitDefinition.new()
	configured.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	configured.hull_weapon_slots = [slot_definition]
	var explicit := UnitState.new(5003,42,Vector3.ZERO)
	explicit.configure(1,configured)
	simulation.units[5003] = explicit
	check(explicit.runtime_weapons.size() == 1,"all explicit old slots join common runtime factory")
	explicit.runtime_weapons[0].bind_target(AttackTarget.unit(vehicle))
	check(simulation.eligibility(explicit.runtime_weapons[0]) == "configuration_missing","unknown aim never completes as zero seconds")
	check(catalog.weapon_slot_fixture("a").ability_tags.is_empty(),"slot fixture has no removed vehicle capabilities")
	var normal := catalog.squad(true)
	check(normal.protection_kinetic == 6 and normal.protection_chemical == 6,"uniform motorized squad protection")
	simulation.units[5001] = target
	var opposing := UnitState.new(5004,0,Vector3(10,0.5,110))
	opposing.configure(2,UnitDefinition.new())
	simulation.units[5004] = opposing
	var coax := vehicle.runtime_weapons[1]
	cannon.bind_target(AttackTarget.unit(target),false)
	coax.bind_target(AttackTarget.unit(opposing),true)
	simulation.advance(1.5)
	check(coax.orientation_ready and not cannon.orientation_ready,"manual coax target controls shared turret before automatic main")
	coax.bind_target(AttackTarget.unit(opposing),false)
	simulation.advance(1.5)
	check(cannon.orientation_ready and not coax.orientation_ready,"automatic main controls shared turret before coax")
	var requests := simulation.hull_requests()
	check(requests.has(5000) and is_equal_approx(requests[5000],cannon.desired_yaw),"automatic main priority for Hull attack facing")
	var commander := vehicle.runtime_weapons[2]
	commander.bind_target(AttackTarget.unit(target))
	vehicle.mounts[1].world_yaw = deg_to_rad(90)
	simulation.advance(0.1)
	check(is_equal_approx(vehicle.mounts[1].world_yaw,deg_to_rad(54)),"commander formal 360 degrees per second")
	vehicle.mounts[1].world_yaw = deg_to_rad(179)
	target.position = vehicle.position+Vector3(-sin(deg_to_rad(-179))*100,0,-cos(deg_to_rad(-179))*100)
	simulation.advance(1.0/360)
	check(is_equal_approx(absf(wrapf(vehicle.mounts[1].world_yaw-deg_to_rad(179),-PI,PI)),deg_to_rad(1)),"shortest wrap around 180 degrees")
