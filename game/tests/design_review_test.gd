extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
func run() -> void:
	var catalog := Prototype05DCatalog.new()
	var geometry := UnitDefinition.new()
	geometry.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	geometry.movement_radius = 3
	geometry.hitbox_half_extents = Vector3(0.2,0.3,0.4)
	var hull := UnitState.new(90,42,Vector3.ZERO)
	hull.configure(1,geometry)
	check(hull.movement_radius() == 3 and hull.hitbox_extents() == geometry.hitbox_half_extents,"movement radius and hit geometry are independent")
	check(not hull.intersects_hit_segment(Vector3(1,0,-1),Vector3(1,0,1)),"movement occupancy never supplies hit dimensions")
	for amount: int in [150,12,0]:
		var definition := catalog.squad(true)
		definition.weapon_allocations.clear()
		catalog.allocate(definition,"rifle",WeaponAllocation.NodeKind.SOLDIER,"1","primary",{"standard":amount})
		var unit := UnitState.new(1,42,Vector3(0,0.5,100))
		unit.configure(1,definition)
		var weapon := unit.runtime_weapons[0]
		check(weapon.pending_rounds == (30 if amount >= 30 else amount),"first magazine is maximum legally ready")
		check(weapon.inventory.standard == amount,"initialization never creates or consumes stock")
		check(weapon.inventory.standard-weapon.pending_rounds+weapon.pending_rounds == amount,"ready is counted within total, not added")
		check(weapon.pending_rounds >= 0 and weapon.pending_rounds <= weapon.definition.capacity,"ready within capacity")
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	check(network._ensure_deployment_ready(),"active deployment initializes")
	check(not network.deployment._catalog.has("test.armored") and not network.deployment._catalog.has("test.unarmed"),"no retired vehicles or legacy fallback catalog")
	check(WeaponMountDefinition.Kind.keys() == ["MAIN_TURRET","WEAPON_STATION"],"removed OTHER has no active enum or replacement")
	var invalid_mount_definition := UnitDefinition.new()
	var invalid_mount := WeaponMountDefinition.new()
	invalid_mount.kind = 2
	invalid_mount_definition.mounts.append(invalid_mount)
	check(not invalid_mount_definition.spatial_valid(),"removed mount value cannot validate as an active unit")
	check(network.deployment.export_player(1).is_empty(),"unknown owner still receives no catalog")
	for entry: Dictionary in network.deployment._catalog.values():
		check(not entry.has("category"),"active purchase config has no retired category")
	for point: Dictionary in network.deployment._points.values():
		check(not point.has("allowed_categories"),"active entry point has no retired category mapping")
	check(network._weapon_presets.all(func(definition): return definition.unit_type == UnitDefinition.UnitType.INFANTRY and definition.turn_speed_degrees == 360),"active infantry uses DB22 facing")
	check(not FileAccess.file_exists("res://data/05d/vehicle_a.tres") and not FileAccess.file_exists("res://data/05d/vehicle_b.tres") and not FileAccess.file_exists("res://data/05d/vehicle_c.tres"),"retired resources removed")
	var own := UnitState.new(10,42,Vector3(0,0.5,100))
	own.configure(1,catalog.squad(true))
	own.owner_player_id = 1
	var friend := UnitState.new(11,77,Vector3(1,0.5,100))
	friend.configure(1,catalog.squad(false))
	friend.owner_player_id = 2
	var enemy := UnitState.new(12,0,Vector3(2,0.5,100))
	enemy.configure(2,catalog.squad(true))
	network._peer_players[42] = 1
	network._peer_players[77] = 2
	network._authoritative_units[10] = own
	network._authoritative_units[11] = friend
	network._authoritative_units[12] = enemy
	network._movement.initialize_navigation()
	for unit: UnitState in [own,friend,enemy]: network._movement.add_unit(unit)
	var rows: Array = network._replication_arguments_for_peer("_receive_unit_structures",[[own.structure_snapshot(),friend.structure_snapshot(),enemy.structure_snapshot()]],42)
	check(rows.size() == 1 and rows[0].size() == 1 and rows[0][0].unit_id == 10,"internal stock/targets remain owner-only")
	check(network._replication_arguments_for_peer("_receive_unit_snapshot",[enemy.snapshot()],42).is_empty(),"unobserved enemy snapshot withheld")
	var ids: Array[int] = [10,11,12]
	var positions: Array[Vector3] = [own.position,friend.position,enemy.position]
	rows = network._replication_arguments_for_peer("_receive_unit_positions",[ids,positions],42)
	check(rows[0] == [10,11] and rows[1].size() == 2,"same-team positions only; no enemy location leakage")
	check(rows[1].is_typed(),"filtered replication preserves typed payload arrays")
	check(network._replication_arguments_for_peer("_receive_unit_structures",[[own.structure_snapshot()]],99).is_empty(),"unknown peer receives no internals")
	check(network._replication_arguments_for_peer("_receive_projectile_events",[[{"target_id":12}],[]],42).is_empty(),"frozen event projection cannot leak enemy identity")
	own.runtime_weapons[0].bind_target(AttackTarget.unit(enemy))
	var airborne := ProjectileState.new({"event_id":"existing","position":own.position,"direction":Vector3.FORWARD,"projectile":own.runtime_weapons[0].definition.projectile.snapshot()})
	network._projectiles = ProjectileSimulation.new()
	network._projectiles.active[airborne.id] = airborne
	own.runtime_weapons[0].enabled = false
	network._aiming.inputs[10] = {"return_fire_locked":true}
	network._movement.attack_facing_requests[10] = PI
	network._movement.request_move(10,42,Vector3(10,0.5,100),MovementSimulation.MoveMode.ATTACK)
	network._pending_commands.assign([{"peer_id":42,"unit_ids":[10],"type":"move"},{"peer_id":77,"unit_ids":[11],"type":"move"}])
	var stop_ids: Array[int] = [10]
	network._apply_stop(stop_ids,42)
	check(not network._movement.has_active_moves() and own.runtime_weapons[0].target == null,"E cancels existing movement/attack intent")
	check(not network._movement.attack_facing_requests.has(10),"canceled attack facing cannot reappear")
	check(network._pending_commands.size() == 1 and network._pending_commands[0].peer_id == 77,"queued same-owner commands cleared without affecting others")
	check(not own.runtime_weapons[0].enabled and network._aiming.inputs[10].return_fire_locked,"E preserves disabled and only-return-fire states")
	check(network._projectiles.active.get(airborne.id) == airborne and not airborne.terminal,"E leaves already launched projectile intact")
	own.runtime_weapons[0].bind_target(AttackTarget.ground(Vector3(10,0,100)))
	network._apply_stop(stop_ids,42)
	check(own.runtime_weapons[0].target == null,"E also cancels existing persistent ground attack intent")
	var before := own.position
	network._movement.advance(1)
	check(own.position == before,"canceled movement does not resume")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	for mode: Key in [KEY_Q,KEY_R,KEY_F]:
		world._handle_world_input(key(mode))
		world._handle_world_input(key(KEY_ESCAPE))
		check(world._current_move_mode() != MovementSimulation.MoveMode.BASIC and world._pending_actions.is_empty(),"Esc opens menu without cancel or command")
		check(world._selection_rectangle.get_parent().get_node("GameMenu").visible,"Esc opens menu")
		world._selection_rectangle.get_parent().get_node("GameMenu").hide()
		world._handle_world_input(key(KEY_E))
		check(world._current_move_mode() == MovementSimulation.MoveMode.BASIC and world._pending_actions.is_empty(),"interactive E exits only")
	world._pending_actions.append({"type":"move"})
	world._left_pressed = true
	world._handle_world_input(key(KEY_E))
	check(not world._left_pressed and world._pending_actions.size() == 1 and world._pending_actions[0].type == "move","E exits selection drag without stopping tasks")
	world._handle_world_input(key(KEY_E))
	check(world._pending_actions.size() == 1 and world._pending_actions[0].type == "stop","noninteractive E clears buffered tasks and requests cancellation")
	world.queue_free()
	network.queue_free()
	await process_frame
	print("DESIGN_REVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
