extends "res://tests/db29_combat_timeline_test.gd"

func run() -> void:
	# Generated high-N fixture permits several legal emissions within one step;
	# the command budget must still stop after one, without changing formal RPM.
	var sample := fixture(64)
	sample.weapon.bind_single_ground_target(Vector3(0,0,-30))
	sample.aiming.advance(3)
	var rows: Dictionary = sample.timeline.step(sample.aiming)
	check(rows.emissions.size() == 1,"G budget is consumed at actual emission even when multiple shots fit in a step")
	check(sample.weapon.target == null and sample.weapon.snapshot().forced_emissions_remaining == -1,"completed one-shot task has serializable cleared state")
	for tick in range(60):
		check(sample.timeline.step(sample.aiming).emissions.is_empty(),"one-shot does not repeat at later tick %d" % tick)
	sample.timeline.projectiles.collision.close()
	# Real activity server: every enabled model channel gets one emission.
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	check(model.configure_active_test_map() and model._ensure_deployment_ready(),"actual activity map and economy ready")
	var unit := UnitState.new(9000,42,Vector3(20,0.5,100))
	unit.configure(1,model._weapon_presets[0])
	unit.owner_player_id = 10
	model._peer_players[42] = 10
	model._authoritative_units[9000] = unit
	model._movement.add_unit(unit)
	model._combat.add_unit(unit)
	var emissions: Array[Dictionary] = []
	model.weapon_fire_received.connect(func(row): emissions.append(row))
	var accepted: Dictionary = model._execute_command({"type":"ground_fire","unit_ids":[9000],"target":Vector3(20,0,90),"peer_id":42,"player_id":10})
	check(accepted.unit_ids == [9000],"real G binds finite one-shot budget")
	check(model._replication_queue.any(func(row): return row.method == "_receive_unit_stops" and row.arguments[0] == [9000]),"accepted G publishes existing stop notification to clear client movement route")
	for tick in range(90): model._run_server_tick(PackedInt32Array())
	check(emissions.size() == 2 and emissions[0].weapon_instance_id != emissions[1].weapon_instance_id,"mixed rifle/LMG squad fires each channel once, rather than continuous fire")
	var count := emissions.size()
	model._execute_command({"type":"ground_fire","unit_ids":[9000],"target":Vector3(20,0,90),"peer_id":42,"player_id":10})
	accepted = model._execute_command({"type":"move","unit_ids":[9000],"target":Vector3(25,0,100),"peer_id":42,"player_id":10,"group":false,"mode":MovementSimulation.MoveMode.BASIC,"facing":Vector3.ZERO})
	check(accepted.unit_ids == [9000] and unit.runtime_weapons.all(func(weapon): return weapon.target == null),"accepted movement cancels pending G across channels")
	for tick in range(30): model._run_server_tick(PackedInt32Array())
	check(emissions.size() == count,"cancelled G cannot emit during movement")
	model._replication_queue.clear()
	model._execute_command({"type":"ground_fire","unit_ids":[9000],"target":Vector3(20,0,90),"peer_id":42,"player_id":10})
	check(not model._movement.is_moving(9000) and model._replication_queue.any(func(row): return row.method == "_receive_unit_stops"),"fire interrupts actual moving unit and replicates route cancellation")
	check(not model._projectiles.halted,"one-shot changes leave authoritative flight chain valid")
	# The rendered mesh, not just a helper, must be short for a 900m/s shot.
	var feed := PresentationFeed.new()
	var visual := ProjectileVisuals.new()
	visual.setup(feed)
	root.add_child(visual)
	var shot := {"projectile_id":"test_only:short","emission_order":1,"time_seconds":0.0,"position":Vector3(0,1,0),"velocity":Vector3(900,0,0),"acceleration":GravityBallistics.GRAVITY}
	feed.apply_projectile_spawn(shot)
	feed.synchronize_projectile_time(GravityBallistics.STEP_SECONDS)
	visual._process(0)
	check(visual.mesh.get_surface_count() == 0,"spawn frame has no history and no tail behind muzzle")
	var flight_state := shot.duplicate()
	flight_state.time_seconds = GravityBallistics.STEP_SECONDS
	flight_state.position = Vector3(30,1-5*pow(GravityBallistics.STEP_SECONDS,2),0)
	flight_state.velocity = Vector3(900,-10*GravityBallistics.STEP_SECONDS,0)
	feed.apply_projectile_spawn(flight_state)
	visual._process(0.05)
	check(visual.mesh.get_surface_count() == 1 and visual.mesh.get_aabb().size.length() < 21.61,"900m/s live projectile mesh uses an independent fading 21.6m profile")
	feed.apply_projectile_terminal({"projectile_id":shot.projectile_id,"time_seconds":0.04,"position":Vector3(36,0.992,0),"reason":"impact"})
	visual._process(0)
	check(visual.mesh.get_aabb().size.length() < 21.61,"impact flash uses the same cosmetic length cap")
	# Preview reads only an owning player's ordinary value snapshot.
	var mortar := UnitState.new(9001,42,Vector3(0,0.5,100))
	mortar.configure(1,preload("res://data/units/db33_active_test_mortar.tres"))
	mortar.owner_player_id = 10
	var structure := mortar.structure_snapshot()
	var before: Dictionary = mortar.runtime_weapons[0].inventory.duplicate()
	var preview := ArtilleryPreview.new()
	var direct_structure := unit.structure_snapshot()
	var direct_point := Vector3(20,0,90)
	var direct_result := preview.describe(direct_structure.weapons[0],direct_point,false)
	check(direct_result.valid and direct_result.origin.distance_to(direct_point) > 0,"G nominal direct solution uses private owning weapon snapshot")
	var direct_end: Vector3 = direct_result.origin+direct_result.velocity*direct_result.seconds+GravityBallistics.GRAVITY*(0.5*direct_result.seconds*direct_result.seconds)
	check(direct_end.distance_to(direct_point) < 0.001,"G nominal red trajectory reaches selected ground point")
	var direct_structures: Array[Dictionary] = [direct_structure]
	check(preview.show_targets(direct_structures,direct_point,false).contains("距离") and preview.mesh.get_surface_count() == 1,"G renders red solid preview with distance")
	var point := Vector3(0,0,-50)
	var description := preview.describe(structure.weapons[0],point)
	check(description.valid and absf(description.distance-structure.weapons[0].weapon_position.distance_to(point)) < 0.0001 and description.minimum == 100 and description.maximum == 1800,"preview uses actual weapon position and formal mortar range")
	var endpoint: Vector3 = description.origin+description.velocity*description.seconds+GravityBallistics.GRAVITY*(0.5*description.seconds*description.seconds)
	check(endpoint.distance_to(point) < 0.001 and description.seconds <= 20 and description.velocity.y > Vector2(description.velocity.x,description.velocity.z).length(),"red trajectory uses distance-selected high branch ending at chosen point")
	var structures: Array[Dictionary] = [structure]
	var text := preview.show_targets(structures,point)
	check(text.contains("距离 %.1f 米" % description.distance) and preview.mesh.get_surface_count() == 1 and preview.material_override.albedo_color == Color.RED,"local red solid mesh and metric range text are produced")
	check(mortar.runtime_weapons[0].inventory == before and mortar.runtime_weapons[0].target == null,"preview does not consume ammo or issue authoritative task")
	description = preview.describe(structure.weapons[0],Vector3(0,0,80))
	check(not description.valid and description.reason == "below_minimum_range","too-near target is labelled rather than displaying a legal firing path")
	preview.show_targets(structures,Vector3(0,0,80))
	check(preview.mesh.get_surface_count() == 0,"invalid range clears valid trajectory")
	preview.free()
	# In-memory TEST ONLY short range exercises approach without changing DATA.
	mortar.runtime_weapons[0].definition = mortar.runtime_weapons[0].definition.duplicate()
	mortar.runtime_weapons[0].definition.range_m = 120
	model._authoritative_units[9001] = mortar
	model._movement.add_unit(mortar)
	model._combat.add_unit(mortar)
	model._replication_queue.clear()
	var approach: Dictionary = model._execute_command({"type":"artillery","unit_ids":[9001],"target":point,"count":1,"peer_id":42,"player_id":10})
	check(approach.unit_ids == [9001] and model._movement.is_moving(9001),"out-of-range T retains authoritative approach")
	var movement_messages: Array = model._replication_queue.filter(func(row): return row.method in ["_receive_unit_stops","_receive_move_targets","_receive_move_paths"])
	check(movement_messages.size() == 3 and movement_messages[0].method == "_receive_unit_stops" and movement_messages[1].method == "_receive_move_targets" and movement_messages[2].method == "_receive_move_paths","approach clears old route before publishing new route in reliable order")
	model._replication_queue.clear()
	var rejected: Dictionary = model._execute_command({"type":"artillery","unit_ids":[9001],"target":Vector3(0,0,90),"count":1,"peer_id":42,"player_id":10})
	check(rejected.unit_ids.is_empty() and model._movement.is_moving(9001) and model._replication_queue.is_empty(),"rejected too-near fire preserves current movement and sends no stop")
	# Domain viewer identity, independent of connection IDs and total player count.
	var style := UnitMarkerStyle.new()
	check(style.color_for(10,10) == style.own_player_color and style.color_for(10,20) == style.other_player_color,"same unit is blue for its owner and green for another viewer")
	check(style.color_for(20,20) == style.own_player_color and style.color_for(20,10) == style.other_player_color,"second player also sees own units as blue")
	check(style.color_for(999,10) == style.other_player_color,"higher player ID has relation-based color rather than white fallback")
	check(style.color_for(0,10) == style.player_colors[0],"unowned enemy remains enemy color")
	var local_network := root.get_node("NetworkManager")
	var previous_player: int = local_network.local_player_id
	local_network.local_player_id = 10
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	world.presentation_source = feed
	root.add_child(world)
	world._on_unit_spawn_received(9001,42,mortar.position)
	world._on_unit_identity_received(9001,10,"test_only:mortar")
	world._on_unit_combat_state_received(9001,1,15,15)
	check(world._visual_units[9001].get_node("MeshInstance3D").material_override.albedo_color == style.own_player_color and world._unit_markers[9001].viewer_player_id == 10,"unit mesh and marker consume local domain palette")
	local_network.local_player_id = 20
	world._refresh_player_colors()
	check(world._visual_units[9001].get_node("MeshInstance3D").material_override.albedo_color == style.other_player_color,"another viewer maps the same unit mesh to green")
	local_network.local_player_id = 10
	world._refresh_player_colors()
	world._visual_units[9001].owner_peer_id = world._view_owner_id()
	var route := PackedVector3Array([mortar.position,Vector3(0,0.5,70)])
	var route_ids: Array[int] = [9001]
	var route_targets: Array[Vector3] = [route[1]]
	var route_paths: Array[PackedVector3Array] = [route]
	world._on_unit_move_targets_received(route_ids,route_targets)
	world._on_unit_move_paths_received(route_ids,route_paths)
	var path: MeshInstance3D = world._movement_paths[9001]
	var colors: Array[Color] = [Color.WHITE,Color.BLUE,Color.YELLOW]
	for mode: int in 3:
		var modes: Array[int] = [mode]
		feed.unit_move_modes_received.emit(route_ids,modes)
		check(path.material_override.albedo_color == colors[mode] and world._route_points[9001] == route,"owner mode reception colors existing path without erasing route")
	var route_stops: Array[Vector3] = [mortar.position]
	world._on_unit_stops_received(route_ids,route_stops)
	check(not path.visible and not world._movement_paths.has(9001) and not world._move_targets.has(9001) and not world._route_points.has(9001) and not world._route_progress.has(9001),"existing stop reception immediately hides indicator and clears every route cache")
	world._selected_units[9001] = world._visual_units[9001]
	feed.apply_live_structure(structure)
	var camera = world.get_node("Units/Camera3D")
	camera._center = Vector3(0,0,-50)
	camera._apply_view()
	world._fire_mode = "artillery"
	world._update_artillery_preview(camera.unproject_position(point))
	check(world._artillery_distance.visible and world._artillery_preview.descriptions.size() == 1,"T input mode connects own snapshot to live local preview")
	local_network.local_player_id = 20
	world._update_artillery_preview(camera.unproject_position(point))
	check(world._artillery_preview.descriptions.is_empty(),"foreign snapshot cannot feed local artillery preview")
	local_network.local_player_id = 10
	world._cancel_reverse_move()
	check(not world._artillery_distance.visible and world._artillery_preview.mesh.get_surface_count() == 0,"focus/mode cancellation clears distance and red arc")
	# Rotation enters through _input before GUI/unhandled event consumption.
	var alt := InputEventKey.new()
	alt.keycode = KEY_ALT
	alt.pressed = true
	camera._input(alt)
	check(camera.is_rotating(),"Alt starts rotation through early input ownership")
	var field := LineEdit.new()
	world.add_child(field)
	field.grab_focus()
	camera._process(0)
	check(camera.is_rotating() and not camera._gui_blocked(),"captured rotation survives stale GUI focus/hover state")
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(40,0)
	var yaw: float = camera._yaw
	camera._input(motion)
	check(camera._yaw != yaw,"captured mouse motion changes camera yaw")
	field.release_focus()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	camera._input(middle)
	alt.pressed = false
	camera._input(alt)
	check(camera.is_rotating(),"release of Alt while middle held retains rotation")
	middle.pressed = false
	camera._input(middle)
	check(not camera.is_rotating(),"last activator release restores camera controls")
	middle.pressed = true
	camera._input(middle)
	check(camera.is_rotating(),"middle independently starts rotation")
	camera.cancel_controls()
	check(not camera.is_rotating() and not camera._alt_held and not camera._middle_held,"focus loss cancels activators without stuck rotation")
	local_network.local_player_id = previous_player
	world.free()
	visual.free()
	model._projectiles.collision.close()
	model.free()
	print("Client acceptance fixes: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
