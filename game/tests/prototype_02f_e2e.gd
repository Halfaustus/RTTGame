extends SceneTree

var network: Node
var world: Node3D
var role := ""
var evidence := ""
var port := 18888
var elapsed := 0.0
var shots := 0
var target_messages: Array[int] = []
var own: Array[int] = []
var record_cache: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func write_record(name: String, value: Variant) -> void:
	var path := evidence.path_join(name + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func read_record(name: String) -> Dictionary:
	var path := evidence.path_join(name + ".json")
	if not FileAccess.file_exists(path):
		return record_cache.get(name,{})
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary:
		record_cache[name] = parser.data
	return record_cache.get(name,{})

func wait_until(condition: Callable, label: String, seconds: float = 20) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL E2E " + role + ": " + label)
			quit(1)
			return false
		await process_frame
	print("PASS E2E ", role, ": ", label)
	return true

func unit_record(id: int) -> Dictionary:
	return read_record("server").get("units", {}).get(str(id), {})

func _process(delta: float) -> bool:
	if network == null or evidence.is_empty():
		return false
	elapsed += delta
	if elapsed < 0.1:
		return false
	elapsed = 0
	var units := {}
	if role == "server":
		for unit: UnitState in network._authoritative_units.values():
			var ids: Array[int] = [unit.unit_id]
			units[str(unit.unit_id)] = {"owner":unit.owner_peer_id,"team":unit.team_id,"health":unit.health,
				"position":[unit.position.x,unit.position.y,unit.position.z],"yaw":unit.yaw,
				"moving":network._movement.is_moving(unit.unit_id),"attack":network._movement._attack_moves.has(unit.unit_id),
				"reverse":network._movement._reverse_moves.has(unit.unit_id),"engaging":network._movement._engaging.has(unit.unit_id),
				"path":path_array(network._movement.move_paths(ids)[0]) if network._movement._targets.has(unit.unit_id) else []}
	else:
		for id: int in world._visual_units:
			var unit: Node3D = world._visual_units[id]
			units[str(id)] = {"owner":unit.owner_peer_id,"team":unit.team_id,"health":unit.health,
				"position":[unit.position.x,unit.position.y,unit.position.z],"yaw":unit.get_node("MeshInstance3D").rotation.y}
	write_record(role, {"units":units,"shots":shots,"routes":world._route_points.keys() if world != null else [],
		"targets":target_messages,"peer":network.multiplayer.get_unique_id() if network.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED else 0})
	return false

func path_array(path: PackedVector3Array) -> Array:
	var points := []
	for point: Vector3 in path:
		points.append([point.x,point.y,point.z])
	return points

func point(data: Array) -> Vector3:
	return Vector3(data[0], data[1], data[2])

func synchronized(id: int) -> bool:
	var server := unit_record(id)
	var other: Dictionary = read_record("observer").get("units", {}).get(str(id), {})
	if server.is_empty() or other.is_empty() or not world._visual_units.has(id):
		return false
	var visual: Node3D = world._visual_units[id]
	return visual.position.distance_to(point(server.position)) < 0.001 \
		and point(other.position).distance_to(point(server.position)) < 0.001 \
		and absf(wrapf(visual.get_node("MeshInstance3D").rotation.y - server.yaw, -PI, PI)) < 0.001 \
		and absf(wrapf(other.yaw - server.yaw, -PI, PI)) < 0.001

func select(ids: Array[int]) -> void:
	var selection: Dictionary[int, Node3D] = {}
	for id: int in ids:
		selection[id] = world._visual_units[id]
	world._replace_selection(selection)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	world._unhandled_input(event)

func command(target: Vector3, code: Key = KEY_NONE) -> void:
	if code != KEY_NONE:
		key(code)
	var camera := root.get_camera_3d()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = camera.unproject_position(target)
	world._unhandled_input(event)
	event.pressed = false
	world._unhandled_input(event)

func _run() -> void:
	network = root.get_node("NetworkManager")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-role="):
			role = argument.get_slice("=",1)
		elif argument.begins_with("--evidence="):
			evidence = argument.trim_prefix("--evidence=")
		elif argument.begins_with("--test-port="):
			port = int(argument.get_slice("=",1))
	if role == "server":
		if not network.start_server(port):
			quit(1)
		return
	world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	network.combat_shot_received.connect(func(_a: Vector3,_b: Vector3): shots += 1)
	network.unit_move_targets_received.connect(func(ids: Array[int],_positions: Array[Vector3]): target_messages.append_array(ids))
	if not network.connect_to_server("127.0.0.1",port):
		quit(1)
		return
	if not await wait_until(func(): return world._visual_units.size() >= (6 if role == "driver" else 9), "live spawn snapshots"):
		return
	for id: int in world._visual_units:
		if world._visual_units[id].owner_peer_id == network.multiplayer.get_unique_id():
			own.append(id)
	own.sort()
	write_record(role + "-ready", {"own":own})
	if role == "late":
		if not await wait_until(rejoin_matches, "fresh late client live IDs position health yaw"):
			return
		print("PASS E2E late complete")
		quit(0)
	elif role == "observer":
		await observer_run()
	else:
		await driver_run()

func observer_run() -> void:
	if not await wait_until(func(): return read_record("driver-control").get("phase","") == "disconnect", "disconnect phase",60):
		return
	var old_peer := network.multiplayer.get_unique_id()
	network.multiplayer.multiplayer_peer.close()
	write_record("observer-offline", {"peer":old_peer})
	if not await wait_until(func(): return read_record("driver-control").get("phase","") == "reconnect", "reconnect phase",30):
		return
	network.connect_to_server("127.0.0.1",port)
	if not await wait_until(func(): return network.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and network.multiplayer.get_unique_id() != old_peer, "new peer connected"):
		return
	await create_timer(0.5).timeout
	if not await wait_until(rejoin_matches, "reconnect exact live IDs and current position health yaw"):
		return
	write_record("observer-reconnected", {"pass":true})
	if not await wait_until(func(): return read_record("driver-control").get("phase","") == "done", "completion",30):
		return
	print("PASS E2E observer complete")
	quit(0)

func rejoin_matches() -> bool:
	var server_units: Dictionary = read_record("server").get("units",{})
	if server_units.is_empty() or world._visual_units.size() != server_units.size():
		return false
	for id_text: String in server_units:
		var id := int(id_text)
		if not world._visual_units.has(id):
			return false
		var data: Dictionary = server_units[id_text]
		var visual: Node3D = world._visual_units[id]
		if visual.position.distance_to(point(data.position)) > 0.001 \
			or visual.health != data.health \
			or absf(wrapf(visual.get_node("MeshInstance3D").rotation.y - data.yaw,-PI,PI)) > 0.001:
			return false
	return true

func driver_run() -> void:
	if not await wait_until(func(): return read_record("observer-ready").has("own"), "second client ready"):
		return
	var other_ids: Array[int] = []
	other_ids.assign(read_record("observer-ready").own)
	var vehicle := own[0]
	var vehicle_ids: Array[int] = [vehicle]
	if not await wait_until(func(): return unit_record(1).get("owner",-1) == 0 and unit_record(2).get("owner",-1) == 0 and unit_record(3).get("owner",-1) == 0 and read_record("server").units.size() == 9, "two joins retain exactly three server enemies"):
		return
	# 0.2G: actual right-drag input crosses ENet; both displays receive final yaw.
	select([own[0], own[2]])
	var camera := root.get_camera_3d()
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.position = camera.unproject_position(Vector3(4,0,108))
	drag.pressed = true
	world._unhandled_input(drag)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(Vector3(8,0,108))
	world._unhandled_input(motion)
	if not await wait_until(func(): return world._right_dragging and world._formation_preview.get_child_count() == 2 and not unit_record(vehicle).get("moving",true), "0.2G preview is local and no command before release"):
		return
	drag.position = motion.position
	drag.pressed = false
	world._unhandled_input(drag)
	if not await wait_until(func(): return not unit_record(vehicle).get("moving",true) and not unit_record(own[2]).get("moving",true) and synchronized(vehicle) and synchronized(own[2]) and absf(wrapf(unit_record(vehicle).get("yaw",0.0) + PI / 2,-PI,PI)) < 0.001 and world._visual_units[vehicle].position.distance_to(Vector3(4,0.5,107.25)) < 0.001 and world._visual_units[own[2]].position.distance_to(Vector3(4,0.5,108.75)) < 0.001, "0.2G rotated slots and final facing synchronize",30):
		return
	network.request_moves(vehicle_ids,Vector3(4,0,108),0,Vector3(NAN,0,1))
	await create_timer(0.3).timeout
	if not await wait_until(func(): return not unit_record(vehicle).get("moving",true), "0.2G invalid facing rejected over ENet"):
		return
	select([vehicle])
	command(Vector3(-8,0,102))
	if not await wait_until(func(): return world._visual_units[vehicle].position.distance_to(Vector3(-8,0.5,102)) < 0.001, "basic reaches A"):
		return
	command(Vector3(8,0,102),KEY_F)
	if not await wait_until(func(): return world._route_points.has(vehicle) and world._route_points[vehicle].size() > 2, "fast road route"):
		return
	if not await wait_until(func(): return world._visual_units[vehicle].position.distance_to(Vector3(8,0.5,102)) < 0.001 and synchronized(vehicle), "two-client fast position yaw sync"):
		return
	command(Vector3(8,0,110),KEY_R)
	if not await wait_until(func(): return unit_record(vehicle).get("reverse",false) and world._route_points.has(vehicle), "reverse command and owner route"):
		return
	if not await wait_until(func(): return world._visual_units[vehicle].position.z > 103, "reverse advances"):
		return
	command(Vector3(8,0,110),KEY_F)
	if not await wait_until(func(): return not unit_record(vehicle).get("reverse",true) and unit_record(vehicle).get("moving",false), "fast replaces reverse"):
		return
	command(Vector3(8,0,110),KEY_Q)
	if not await wait_until(func(): return unit_record(vehicle).get("attack",false), "attack replaces fast"):
		return
	command(Vector3(8,0,110),KEY_R)
	if not await wait_until(func(): return unit_record(vehicle).get("reverse",false) and not unit_record(vehicle).get("attack",true), "reverse replaces attack"):
		return
	command(Vector3(8,0,110))
	if not await wait_until(func(): return not unit_record(vehicle).get("reverse",true) and unit_record(vehicle).get("moving",false), "basic replaces reverse after mode consumed"):
		return
	command(Vector3(8,0,110),KEY_R)
	if not await wait_until(func(): return unit_record(vehicle).get("reverse",false), "reverse before stop"):
		return
	key(KEY_E)
	if not await wait_until(func(): return not unit_record(vehicle).get("reverse",true) and not world._route_points.has(vehicle) and synchronized(vehicle), "stop clears route and syncs current yaw"):
		return
	var foreign_before := unit_record(other_ids[0])
	network.request_moves(other_ids,Vector3(20,0,110),3)
	network.request_stops(other_ids)
	network.request_moves(vehicle_ids,Vector3(NAN,0,110),0)
	network.request_moves(vehicle_ids,Vector3(8,0,110),99)
	await create_timer(0.5).timeout
	if not await wait_until(func(): return unit_record(other_ids[0]).get("position",[]) == foreign_before.position and not unit_record(other_ids[0]).get("moving",true), "foreign commands and invalid payload rejected"):
		return
	if not await wait_until(func(): return read_record("observer").routes.is_empty() and read_record("observer").targets.is_empty(), "route RPC only owner"):
		return
	key(KEY_E)
	key(KEY_E)
	select([own[2]])
	command(Vector3(3,0,110))
	if not await wait_until(func(): return unit_record(own[2]).get("moving",false), "unarmed basic order"):
		return
	select([own[0],own[1]])
	command(Vector3(-8,0,100))
	if not await wait_until(func(): return not unit_record(own[0]).get("moving", true) and not unit_record(own[1]).get("moving", true) and absf(world._visual_units[own[0]].position.distance_to(world._visual_units[own[1]].position) - 1.5) < 0.001, "armed group staging and horizontal slots"):
		return
	select([own[0],own[1],own[2]])
	command(Vector3(-10,0,88),KEY_Q)
	if not await wait_until(func(): return unit_record(own[0]).get("attack",false) and unit_record(own[1]).get("attack",false) and not unit_record(own[2]).get("attack",true), "mixed attack weapon filter"):
		return
	if not await wait_until(func(): return unit_record(own[0]).get("engaging",false) and unit_record(own[1]).get("engaging",false), "attack encounter parks",30):
		return
	if not await wait_until(func(): return world._route_points.has(own[0]) and not read_record("observer").routes.has(float(own[0])) and shots > 0 and read_record("observer").shots > 0 and world._visual_units.has(1) and world._visual_units[1].health < 100 and read_record("observer").get("units",{}).get("1",{}).get("health",100) == world._visual_units[1].health, "both clients damage shots and paused owner route"):
		return
	select([own[0],own[1]])
	key(KEY_E)
	write_record("driver-control", {"phase":"disconnect"})
	if not await wait_until(func(): return read_record("observer-offline").has("peer"), "observer disconnected"):
		return
	if not await wait_until(func(): return not world._visual_units.has(1) and not read_record("server").units.has("1"), "enemy dies while observer offline",20):
		return
	select([vehicle])
	command(Vector3(-10,0,105))
	if not await wait_until(func(): return unit_record(vehicle).get("moving",false), "move after stopped combat"):
		return
	if not await wait_until(func(): return world._visual_units[vehicle].position.distance_to(Vector3(-10,0.5,105)) < 0.001, "changed position before rejoin"):
		return
	write_record("driver-control", {"phase":"reconnect"})
	if not await wait_until(func(): return read_record("observer-reconnected").get("pass",false), "late/reconnect live snapshots",30):
		return
	var rebels: Array[int] = []
	for id_text: String in read_record("server").units:
		if read_record("server").units[id_text].owner == 0:
			rebels.append(int(id_text))
	if not await wait_until(func(): return rebels.size() <= 2 and not rebels.has(1) and rebels.all(func(id: int): return id in [2,3]) and not world._visual_units.has(1) and not read_record("observer").units.has("1"), "no enemy respawn on reconnect"):
		return
	# A real death message while both clients are connected, after the snapshot check.
	var remaining_enemy := 3
	if read_record("server").units.has(str(remaining_enemy)):
		var combat_ids: Array[int] = [vehicle]
		if world._visual_units.has(own[1]):
			combat_ids.append(own[1])
		select(combat_ids)
		command(Vector3(14,0,90),KEY_Q)
		if not await wait_until(func(): return not read_record("server").units.has("3") and not world._visual_units.has(3) and not read_record("observer").units.has("3"), "enemy death event removes both client visuals",30):
			return
	write_record("driver-control", {"phase":"done"})
	print("PASS E2E driver complete")
	quit(0)
