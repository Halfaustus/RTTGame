extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS 0.7B: ", label)
	else:
		failures += 1
		push_error("FAIL 0.7B: " + label)

func _run() -> void:
	var groups := BattleControlGroups.new()
	groups.save(1,[4,5])
	groups.save(2,[5,6])
	check(groups.groups[1] == [4,5] and groups.groups[2] == [5,6], "unit may belong to several groups")
	var result := groups.select_group(1,[9],[4,5,6,9],false,1)
	check(result.selection == [4,5] and not result.locate, "first press selects only group")
	result = groups.select_group(1,[4,5],[4,5,6],false,1.2)
	check(result.locate, "quick second press locates group")
	result = groups.select_group(1,[4,5],[4,5,6],false,2)
	check(not result.locate, "slow repeated press does not locate")
	result = groups.select_group(2,[4,5],[4,5,6],true,2.1)
	check(result.selection == [4,5,6] and not result.locate, "Shift merges without duplicate or locate")
	result = groups.select_group(0,[4,5],[4,5],false,3)
	check(not result.changed and result.selection == [4,5], "empty group preserves selection")
	groups.save(1,[6])
	check(groups.groups[1] == [6] and groups.groups[2] == [5,6], "save overwrites only target group")
	groups.remove_unit(6)
	check(groups.groups[1].is_empty() and groups.groups[2] == [5], "exit removes unit from all groups")
	result = groups.select_group(2,[],[5,10],false,4)
	check(result.selection == [5], "new purchase ID is not automatically added")
	result = groups.select_group(2,[10],[10],false,5)
	check(result.selection == [10] and not result.changed, "unavailable group fails without selection changes")
	groups.clear()
	check(groups.groups.is_empty(), "session reset clears groups")
	# Isolated world scene; no Bootstrap, no ENet connection or client launch.
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	root.add_child(world)
	var network := root.get_node("NetworkManager")
	var old_player: int = network.local_player_id
	network.local_player_id = 10
	world._on_unit_spawn_received(900,42,Vector3.ZERO)
	world._visual_units[900].owner_player_id = 10
	world._visual_units[900].health = 10
	world._on_unit_spawn_received(901,43,Vector3(10,0,0))
	world._visual_units[901].owner_player_id = 11
	world._visual_units[901].health = 10
	var mixed_ids: Array[int] = [900,901]
	world._control_groups.save(1,mixed_ids)
	var event := InputEventKey.new()
	event.keycode = KEY_1
	event.pressed = true
	check(world._handle_control_group_key(event), "real input route consumes digit")
	check(world._selected_units.keys() == [900], "real group input filters authenticated player")
	var peer: Node3D = world._visual_units[901]
	peer.owner_player_id = 10
	world._selection_collection[901] = peer
	world._focus_selection_unit(901)
	check(world._selected_units.keys() == [901] and world._selection_collection.size() == 2, "panel focus preserves original multi selection")
	world._cycle_marker_selection(true)
	check(world._selected_units.size() == 2, "Shift Tab restores focused panel collection")
	world._focus_selection_unit(900)
	world._fire_mode = "ground_fire"
	check(not world._handle_control_group_key(event), "target interaction owns digits before group selection")
	world._open_menu()
	check(world._menu.visible and world._camera.input_blocked, "menu shows modal layer and blocks camera")
	check(world._fire_mode == "ground_fire", "opening menu retains active interaction and never sends stop")
	world._handle_world_input(event)
	check(world._selected_units.keys() == [900], "menu prevents world selection input")
	world._on_hud_command("fast")
	check(not world._fast_move_armed, "menu prevents HUD command activation")
	var camera = world._camera
	var pan := InputEventKey.new()
	pan.keycode = KEY_W
	pan.pressed = true
	check(not camera._handle_camera_input(pan) and camera._movement_keys.is_empty(), "menu blocks camera key input")
	world._menu.find_child("ResumeGame",true,false).pressed.emit()
	check(not world._menu.visible and not camera.input_blocked, "return button releases modal ownership")
	world._fire_mode = ""
	world._on_visual_unit_removed(900)
	check(world._control_groups.groups[1].is_empty(), "real exit callback removes group membership")
	world._reset_replicated_units()
	check(world._control_groups.groups.is_empty(), "real reset callback clears groups")
	network.local_player_id = old_player
	world.free()
	await process_frame
	print("0.7B checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
