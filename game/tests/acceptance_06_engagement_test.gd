extends "res://tests/db29_combat_timeline_test.gd"

func run() -> void:
	var manager = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(manager)
	check(manager.configure_active_test_map() and manager.configure_acceptance_06c(true),"full opt-in ready")
	manager._initialize_rebels()
	manager.timeline.begin_tick()
	manager.timeline.enter_phase("session")
	manager._apply_peer_join(42)
	manager._apply_peer_join(43)
	manager.timeline.enter_phase("replication")
	manager.timeline.finish_tick()
	for tick: int in 2: manager._run_server_tick(PackedInt32Array([42,43]))
	var command := {"type":"acceptance_auto","unit_ids":[4],"peer_id":42,"player_id":1,"enabled":true,"mode":-1,"group":false}
	check(manager._execute_command(command).unit_ids == [4],"authorized auto enabled for owner")
	var weapon: RuntimeWeaponInstance = manager._authoritative_units[4].runtime_weapons[0]
	var candidate: AttackTarget = manager._acceptance_nearest_target(weapon)
	check(candidate != null and candidate.unit_id == 1,"nearest legal disclosed enemy selected")
	check(weapon.target == null,"candidate query preserves target state")
	command.unit_ids = [11]
	check(manager._execute_command(command).unit_ids.is_empty(),"another client's auto control denied")
	var emissions: Array[Dictionary] = []
	manager.weapon_fire_received.connect(func(event): emissions.append(event))
	for tick: int in 90: manager._run_server_tick(PackedInt32Array([42,43]))
	check(not emissions.is_empty() and not manager._combat_timeline.halted and manager._authoritative_units[1].health < 60,"real automatic emission and damage through actual timeline")
	command.unit_ids = [4]
	command.enabled = false
	manager._execute_command(command)
	check(weapon.target == null,"disable cancels only automatic target")
	var move := {"type":"move","unit_ids":[9],"peer_id":42,"player_id":1,"target":Vector3(30,0,125),"mode":MovementSimulation.MoveMode.FAST,"group":false,"facing":Vector3.ZERO}
	check(manager._execute_command(move).unit_ids == [9] and manager._movement._move_modes[9] == MovementSimulation.MoveMode.FAST,"FAST command and actual path installed")
	var initial: Vector3 = manager._authoritative_units[9].position
	for tick: int in 120: manager._run_server_tick(PackedInt32Array([42,43]))
	check(manager._authoritative_units[9].position.distance_to(initial) > 0.1,"FAST produces actual movement")
	command.unit_ids = [4]
	command.enabled = false
	manager._execute_command(command)
	move.unit_ids = [4]
	move.mode = MovementSimulation.MoveMode.ATTACK
	move.group = true # The actual client request uses formation/group movement.
	check(manager._execute_command(move).unit_ids == [4] and manager._acceptance_auto_units.has(4),"attack move enables its own engagement without separate toggle")
	check(manager._replication_arguments_for_peer("_receive_move_modes",[[4],[MovementSimulation.MoveMode.ATTACK]],42).size() == 2 and manager._replication_arguments_for_peer("_receive_move_modes",[[4],[MovementSimulation.MoveMode.ATTACK]],43).is_empty(),"accepted group mode visible only to command owner")
	var stale: UnitState = manager._authoritative_units[3]
	var stale_position := stale.position
	stale.position = Vector3(180,0.5,-180)
	weapon.bind_target(AttackTarget.unit(stale),false)
	manager._update_acceptance_engagement()
	check(weapon.target != null and weapon.target.unit_id == 1,"attack move replaces stale out-of-range automatic target with its stopping target")
	stale.position = stale_position
	initial = manager._authoritative_units[4].position
	for tick: int in 30: manager._run_server_tick(PackedInt32Array([42,43]))
	check(manager._movement._engaging.has(4) and manager._authoritative_units[4].position.is_equal_approx(initial),"attack move parks for real eligible weapon")
	check(weapon.target != null and weapon.target.unit_id == 1 and weapon.can_attack,"parked group has the actual eligible aiming target")
	var route_visual = load("res://scripts/core/movement_path_visual.gd").new()
	for mode: int in [MovementSimulation.MoveMode.BASIC,MovementSimulation.MoveMode.FAST,MovementSimulation.MoveMode.ATTACK]:
		route_visual.set_move_mode(mode)
		var expected: Color = Color.WHITE if mode == MovementSimulation.MoveMode.BASIC else (Color.BLUE if mode == MovementSimulation.MoveMode.FAST else Color.YELLOW)
		check(route_visual.material_override.albedo_color == expected,"movement route color mode %d" % mode)
	route_visual.update_route(PackedVector3Array([Vector3.ZERO,Vector3(1,0,1),Vector3(4,0,1)]))
	check(route_visual.mesh.get_surface_count() == 1,"colored dashed route preserves intermediate path points")
	route_visual.free()
	var structures: Array[Dictionary] = []
	for unit: UnitState in manager._authoritative_units.values(): structures.append(unit.structure_snapshot())
	var statuses: Array = manager._replication_arguments_for_peer("_receive_unit_statuses",[structures],43)
	check(statuses.size() == 1 and statuses[0].any(func(row): return row.unit_id == 4) and statuses[0].any(func(row): return row.unit_id == 1),"other player receives friendly and disclosed enemy status")
	check(statuses[0].all(func(row): return not row.has("members") and not row.has("weapons") and not row.has("ratio")),"private data excluded")
	manager._acceptance_known_enemies.erase(1)
	statuses = manager._replication_arguments_for_peer("_receive_unit_statuses",[structures],43)
	check(not statuses[0].any(func(row): return row.unit_id == 1),"undisclosed enemy status excluded")
	manager._acceptance_known_enemies.clear()
	for tick: int in 60: manager._run_server_tick(PackedInt32Array([42,43]))
	check(not manager._movement._engaging.has(4) and manager._authoritative_units[4].position.distance_to(initial) > 0.1,"attack route resumes without visible enemy")
	for name: String in ["manual","mechanical"]:
		var unit: UnitState = manager._authoritative_units[9 if name == "manual" else 10]
		check(unit.is_armed() and unit.runtime_weapons[0].node_kind == WeaponAllocation.NodeKind.HULL,"actual armed editor vehicle "+name)
		check(unit.runtime_weapons[0].definition.mechanical_loading == (name == "mechanical"),"explicit loading qualification "+name)
	var vehicle_ids: Array[int] = [9]
	manager._movement.request_stop(vehicle_ids,42)
	var probe: Dictionary = manager._execute_command({"type":"acceptance_module_probe","unit_ids":[9],"peer_id":42,"player_id":1,"mode":-1,"group":false})
	check(probe.unit_ids == [8],"probe requests actual owned module shooter, no state injection")
	for tick: int in 120: manager._run_server_tick(PackedInt32Array([42,43]))
	check(manager._authoritative_units[9].vehicle_modules.levels.reduce(func(sum,value): return sum+value,0) == 1 and manager._authoritative_units[9].health == 20,"real probe upgrades selected vehicle exactly once without life damage")
	var parked_ids: Array[int] = [4]
	manager._movement.request_stop(parked_ids,42) # Keep the resumed route out of the probe's physical line.
	for shot: int in 7:
		manager._execute_command({"type":"acceptance_module_probe","unit_ids":[9],"peer_id":42,"player_id":1,"mode":-1,"group":false})
		for tick: int in 45: manager._run_server_tick(PackedInt32Array([42,43]))
	check(manager._authoritative_units[9].vehicle_modules.levels == [2,2,2,2] and manager._authoritative_units[9].health == 20,"eight actual legal hits reach all heavy modules")
	var modifier: Dictionary = manager._aiming.inputs[9]
	check(modifier.aim_time_multiplier == 25 and modifier.personnel_load_multiplier == 5 and modifier.loading_module_multiplier == 5,"actual manual vehicle inputs reflect combined module factors")
	check(manager._authoritative_units[9].personnel_speed_multiplier == 0.2,"actual mobility input reflects heavy module")
	var controls = load("res://scripts/ui/acceptance_06c_controls.gd").new()
	controls.owned_selection = func():
		var selected: Array[int] = [9]
		return selected
	controls.structure_lookup = func(_id): return {}
	root.add_child(controls)
	var buttons: Array[Node] = controls.find_children("*","Button",true,false)
	check(buttons.size() >= 6 and buttons.all(func(button): return button.focus_mode == Control.FOCUS_NONE),"test command buttons leave F/Q keyboard ownership available")
	controls.free()
	manager._projectiles.collision.close()
	manager.free()
	print("06 ENGAGEMENT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
