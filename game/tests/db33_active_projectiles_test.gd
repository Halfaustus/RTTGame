extends "res://tests/db29_combat_timeline_test.gd"

func movement_for(registered: Dictionary) -> MovementSimulation:
	var config := MovementConfig.new()
	config.minimum_xz = Vector2(-200,-200)
	config.maximum_xz = Vector2(200,200)
	config.ground_height = 0.0
	config.navigation_cell_size = 5.0 # Local coarse map, not production geometry.
	var movement := MovementSimulation.new(config)
	check(movement.initialize_navigation(PrototypeMapDefinition.new()),"generated isolated map initialized")
	for unit: UnitState in registered.values(): movement.add_unit(unit)
	return movement

func run() -> void:
	var test := fixture(4)
	var movement := movement_for(test.aiming.units)
	test.aiming.moving = movement.is_moving
	test.aiming.inputs[test.unit.unit_id] = {"moving_spread_multiplier":1.5}
	test.weapon.definition.moving_aim_qualification = 1 # Local fixture; formal M249 already permits this.
	test.weapon.fire_state.interval_remaining = 0.016
	var start_position: Vector3 = test.weapon.world_position()
	check(movement.request_move(test.unit.unit_id,42,Vector3(20,0,0)) == "","moving source test command accepted")
	check(movement.request_move(test.target.unit_id,43,Vector3(0,0,-50)) == "","moving target test command accepted")
	var result: Dictionary = test.timeline.step_movement(movement,test.aiming)
	check(result.emissions.size() == 1,"moving source and target can emit at actual due time")
	if not result.emissions.is_empty():
		var event: Dictionary = result.emissions[0]
		check(absf(event.time_seconds-0.016) < 0.000001,"emission not moved to step boundary")
		var expected := start_position.lerp(test.weapon.world_position(),0.016/GravityBallistics.STEP_SECONDS)
		var yaw := atan2(-(test.target.position-test.unit.position).x,-(test.target.position-test.unit.position).z)
		check(event.position.distance_to(expected+Prototype05FConfig.SOLDIER_MUZZLE.rotated(Vector3.UP,yaw)) < 0.005,"muzzle sampled within physical step")
		check(test.timeline.fire.profile.ballistic_solves == 3 and test.timeline.fire.profile.spread_samples == 1,"moving intercept performs three solves and one scatter sample: "+str(test.timeline.fire.profile))
	test.timeline.projectiles.collision.close()
	test = fixture(1)
	movement = movement_for(test.aiming.units)
	test.aiming.moving = movement.is_moving
	test.weapon.aim_progress = 0.9
	test.weapon.is_aimed = false
	test.weapon.aim_timer_complete = false
	result = test.timeline.step_movement(movement,test.aiming)
	check(result.emissions.size() == 1 and absf(result.emissions[0].time_seconds-0.01) < 0.000001,"aim completion schedules within-step shot without backdating")
	test.timeline.projectiles.collision.close()
	# Explicit ground-selection decision, independent of target armor.
	test = fixture(1)
	var friend_definition := UnitDefinition.new()
	friend_definition.configuration_source = "test_only:crossing_friend"
	friend_definition.member_count = 1
	var friend := UnitState.new(7777,42,Vector3(5,0,-15))
	friend.configure(1,friend_definition)
	test.aiming.units[7777] = friend
	var frame := FiringFrame.new()
	frame.begin(0,test.aiming)
	var before := ProjectileUnitMotion.capture(test.aiming.units)
	friend.position.x = -5
	friend.members[0].position.x -= 10
	var motion := ProjectileUnitMotion.new()
	check(motion.configure(0,before,ProjectileUnitMotion.capture(test.aiming.units)),"crossing-friendly shared frame built")
	frame.finish(test.aiming,motion)
	var origin := DirectBallistics.muzzle(test.weapon)
	check(frame.friendly_clear(test.weapon,origin,test.target.position,0),"friend clear at step start")
	check(not frame.friendly_clear(test.weapon,origin,test.target.position,GravityBallistics.STEP_SECONDS/2),"friend blocks at actual mid-step emission time")
	check(frame.friendly_clear(test.weapon,origin,test.target.position,GravityBallistics.STEP_SECONDS),"friend clear at step end cannot override mid-step block")
	test.weapon.bind_target(AttackTarget.ground(test.target.position))
	check(frame.friendly_clear(test.weapon,origin,test.target.position,GravityBallistics.STEP_SECONDS/2),"G skips friendly pre-fire check while physical collision remains separate")
	test.timeline.projectiles.collision.close()
	# Explicit ground-selection decision, independent of target armor.
	test = fixture(1)
	test.weapon.definition.ammo_definitions = data.weapon("W_M242").ammo_definitions
	test.weapon.bind_target(AttackTarget.ground(Vector3(0,0,-30)))
	for ammo: AmmoDefinition in test.weapon.definition.ammo_definitions: test.weapon.inventory[ammo.ammo_id] = 12
	var selection := AmmoSelection.select(test.weapon,{})
	check(selection.reason == "eligible" and selection.ammo.explosion_radius_m > 0,"ground fire prefers stocked HE")
	test.weapon.inventory[selection.ammo.ammo_id] = 0
	selection = AmmoSelection.select(test.weapon,{})
	check(selection.reason == "eligible" and selection.ammo == test.weapon.definition.ammo_definitions[0],"ground fire falls back to configured stocked order")
	test.timeline.projectiles.collision.close()
	# Generated M252 crew; only missing configuration filled locally.
	test = fixture(3,"W_M252")
	test.weapon.definition.capacity = 1 # Missing DATA capacity, test only.
	test.weapon.definition.preparation_seconds = 4 # Missing reload, test only.
	test.weapon.pending_rounds = 1
	test.target.position = Vector3(0,0,-100)
	test.weapon.bind_target(AttackTarget.ground(test.target.position))
	test.aiming.advance(3)
	check(test.timeline.step(test.aiming).emissions.is_empty() and test.weapon.fire_state.reason == "artillery_requires_t","G or ordinary targeting cannot fire mortar")
	movement = movement_for(test.aiming.units)
	var artillery := ArtillerySimulation.new()
	check(artillery.submit(test.unit,Vector3(0,0,-50),1,test.aiming,movement) == "below_minimum_range","formal M252 minimum range retained")
	check(artillery.submit(test.unit,Vector3(0,0,-150),1,test.aiming,movement) == "","T single-point task accepted")
	test.aiming.advance(3)
	result = test.timeline.step(test.aiming)
	check(result.emissions.size() == 1,"T produces one authorized mortar projectile: "+test.weapon.fire_state.reason)
	if not result.emissions.is_empty():
		var shot: Dictionary = result.emissions[0]
		check(shot.velocity.y > 200 and absf(shot.velocity.length()-225) < 0.001,"formal 225m/s mortar uses high branch")
		artillery.after_emissions(result.emissions,test.aiming.units)
		check(artillery.tasks.is_empty() and test.weapon.target == null,"one-shot T task completes after exact count")
		check(test.timeline.projectiles.active_slots.size() == 1,"task completion retains in-flight shell")
	test.timeline.projectiles.collision.close()
	# Actual production server path, no client window/connection/detection grant.
	var flight := DB29ProjectileSimulation.new()
	flight.configure_bounds(Rect2(-1000,-1000,2000,2000))
	flight.collision.box("test_only:ground","terrain",Vector3(1000,0.05,1000),Transform3D(Basis.IDENTITY,Vector3(0,-0.05,0)))
	var mortar_ammo := data.ammunition("A_M252_HE")
	var solution := GravityBallistics.high(Vector3(0,0.5,0),Vector3(0,0,-150),mortar_ammo.initial_speed_mps)
	var shot_batch: Array[Dictionary] = [{"event_id":"test_only:long_mortar","emission_order":1,"time_seconds":0.0,"position":Vector3(0,0.5,0),"velocity":solution.velocity,"ammo":mortar_ammo,"unit_id":1,"owner_player_id":42,"weapon_instance_id":"test_only:mortar"}]
	flight.step(shot_batch)
	var ground_hit := {}
	for i in range(1500):
		var rows := flight.step()
		for row: Dictionary in rows:
			if row.reason == "impact": ground_hit = row
		if not ground_hit.is_empty(): break
	check(not ground_hit.is_empty() and ground_hit.time_seconds > 40 and ground_hit.object_id == "test_only:ground","high mortar remains alive beyond old lifetime and hits actual ground")
	check(flight.active_slots.is_empty() and not flight.halted,"long high flight completes through ordinary point consumer")
	flight.collision.close()
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	check(network.configure_active_test_map(),"actual active battlefield initialized")
	check(network._ensure_deployment_ready() and network.timeline.tick_hz == 30,"active deployment and timeline initialized at 30Hz")
	check(network._movement._config == preload("res://data/db33_active_test_movement.tres"),"active simulation uses saved test map")
	check(network.deployment._movement.minimum_xz == network._movement._config.minimum_xz and network.deployment._movement.maximum_xz == network._movement._config.maximum_xz and network.deployment._movement.navigation_cell_size == network._movement._config.navigation_cell_size,"deployment snapshot agrees with actual active map configuration")
	check(not network.configure_active_test_map(),"cannot replace battlefield after economy initialization")
	var recording_model = load("res://scripts/networking/network_manager.gd").new()
	check(recording_model.configure_active_test_map(),"recording boundary model selects active map")
	check(not recording_model.replay_recorder.start(recording_model,"res://../tmp/db33-active-map/unsupported.json") and recording_model.replay_recorder.error.contains("unsupported"),"active map cannot masquerade as frozen Replay v1")
	recording_model.free()
	var source := UnitState.new(8000,42,Vector3(20,0.5,100))
	source.configure(1,network._weapon_presets[0])
	source.owner_player_id = 1
	network._authoritative_units[source.unit_id] = source
	network._movement.add_unit(source)
	network._combat.add_unit(source)
	network._peer_players[42] = 1
	check(source.definition.configuration_source.begins_with("test_only:") and source.members.size() == 4,"active units generated and clearly test-only")
	var accepted: Dictionary = network._execute_command({"type":"ground_fire","unit_ids":[8000],"target":Vector3(20,0,90),"peer_id":42,"player_id":1})
	check(accepted.unit_ids == [8000],"owned G command binds legal ground targets")
	var spawns: Array[Dictionary] = []
	var emissions: Array[Dictionary] = []
	network.projectile_spawn_received.connect(func(row): spawns.append(row))
	network.weapon_fire_received.connect(func(row): emissions.append(row))
	for i in range(10): network._run_server_tick(PackedInt32Array())
	check(not spawns.is_empty() and not network._combat_timeline.halted,"active chain emits and consumes real ground shots")
	check(absf(network._fire.time_seconds-10.0/30.0) < 0.000001 and network._projectiles.time_seconds == network._fire.time_seconds,"active movement/fire/projectiles share 30Hz clock")
	check(emissions.all(func(row): return not row.has("ammo") and not row.has("target_id")),"presentation emissions contain no Resource or target identity")
	var rejected: Dictionary = network._execute_command({"type":"ground_fire","unit_ids":[8000],"target":Vector3.ZERO,"peer_id":99,"player_id":2})
	check(rejected.unit_ids.is_empty(),"foreign player cannot issue fire for owned unit")
	rejected = network._execute_command({"type":"ground_fire","unit_ids":[8000],"target":Vector3(NAN,0,0),"peer_id":42,"player_id":1})
	check(rejected.unit_ids.is_empty(),"invalid fire location rejected before target mutation")
	var cannon := UnitState.new(8001,42,Vector3(20,0.5,100))
	cannon.configure(1,preload("res://data/units/db33_active_test_mortar.tres"))
	cannon.owner_player_id = 1
	network._authoritative_units[8001] = cannon
	network._movement.add_unit(cannon)
	network._combat.add_unit(cannon)
	check(cannon.runtime_weapons.size() == 1 and cannon.runtime_weapons[0].configured_count == 1 and cannon.runtime_weapons[0].operable_count == 1,"generated three-person mortar has one configured weapon and sufficient crew")
	accepted = network._execute_command({"type":"artillery","unit_ids":[8001],"target":Vector3(20,0,-50),"count":1,"peer_id":42,"player_id":1})
	check(accepted.unit_ids == [8001],"authenticated T request reaches activity task system")
	for i in range(5): network._run_server_tick(PackedInt32Array())
	check(emissions.any(func(row): return row.unit_id == 8001 and row.velocity.y > 200),"active T task fires formal mortar high trajectory")
	check(network._artillery.tasks.is_empty() and cannon.runtime_weapons[0].target == null,"active T count completion clears task only")
	rejected = network._execute_command({"type":"ground_fire","unit_ids":[8001],"target":Vector3(20,0,-50),"peer_id":42,"player_id":1})
	check(rejected.unit_ids.is_empty() and rejected.rejection == "artillery_requires_t","G request cannot silently authorize T-only mortar")
	rejected = network._execute_command({"type":"artillery","unit_ids":[8001],"target":Vector3(20,1000,-50),"count":1,"peer_id":42,"player_id":1})
	check(rejected.unit_ids.is_empty(),"T reuses actual map ground eligibility")
	var first_event_count := emissions.size()
	for i in range(5): network._run_server_tick(PackedInt32Array())
	check(emissions.size() == first_event_count,"finished one-shot task cannot repeat on subsequent ticks")
	var before_tick: int = network.timeline.tick
	network._physics_process(1.0)
	check(network.timeline.tick == before_tick+8 and network._server_clock.pending_seconds > 0.7,"actual server callback respects eight-step budget and retains debt")
	for i in range(3): network._physics_process(0.0)
	check(network.timeline.tick == before_tick+30 and network._server_clock.pending_seconds < 0.000001,"actual server drains all retained steps in order")
	check(not network.timeline.records.any(func(row): return row.type == "shot"),"new events never become frozen damage shot")
	var feed := PresentationFeed.new()
	feed.apply_projectile_spawn({"projectile_id":"test_only:visual","emission_order":1,"time_seconds":0.0,"position":Vector3.ZERO,"velocity":Vector3(10,10,0),"acceleration":GravityBallistics.GRAVITY})
	check(feed.projectile_position("test_only:visual",1) == Vector3(10,5,0),"gravity display interpolation has no invented lifetime")
	# Offline input dispatch only, no client startup.
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	root.add_child(world)
	check(world.movement_config == network._movement._config and world.get_node("StaticMap").movement_config == world.movement_config,"input geometry and authoritative battlefield agree")
	var camera = world.get_node("Units/Camera3D")
	camera._center = Vector3(-999,0,999)
	camera._apply_view()
	check(camera._center == Vector3(-200,0,200),"camera clamps ground focus to active battlefield")
	check(world.get_node("StaticMap/Ground").position == Vector3(0,-0.05,0),"actual activity ground covers enlarged map")
	var frozen_world = load("res://scenes/maps/test_world.tscn").instantiate()
	check(frozen_world.movement_config.minimum_xz == Vector2(-20,80) and frozen_world.get_node("Units/Camera3D").battlefield_config == null,"frozen map and camera behavior preserved")
	frozen_world.free()
	var event := InputEventKey.new()
	event.keycode = KEY_T
	event.pressed = true
	world._handle_world_input(event)
	check(world._fire_mode == "artillery","T opens minimal single-point interaction")
	event.keycode = KEY_ESCAPE
	world._handle_world_input(event)
	check(world._fire_mode == "artillery","Esc menu preserves T interaction")
	event.keycode = KEY_E
	world._handle_world_input(event)
	check(world._fire_mode.is_empty() and world._pending_actions.is_empty(),"E exits T only without clearing tasks")
	world._fire_mode = "artillery"
	world._arm_attack_move()
	check(world._fire_mode.is_empty(),"Q replaces T interaction without issuing artillery")
	world._fire_mode = "artillery"
	world._cancel_reverse_move()
	check(world._fire_mode.is_empty(),"focus and deployment cancellation clear T interaction")
	world.queue_free()
	network._projectiles.collision.close()
	network.queue_free()
	print("DB33 active projectiles: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
