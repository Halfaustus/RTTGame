extends SceneTree

# Real ENet, production bootstrap and simulation, no reconnect or identity recovery.
var role := ""
var directory := ""
var network: Node
var world: Node3D
var shots := 0
var deaths: Array[int] = []
var elapsed := 0.0
var server_records: Array[Dictionary] = []
var completed_ticks := 0

func _initialize() -> void:
	_run.call_deferred()

func write(name: String, value: Dictionary) -> void:
	var path := directory.path_join(name + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func read(name: String) -> Dictionary:
	var path := directory.path_join(name + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary:
		return parser.data
	return {}

func wait_for(condition: Callable, label: String, timeout: float = 30) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL ENet 0.3B " + role + ": " + label)
			quit(1)
			return false
		await process_frame
	print("PASS ENet 0.3B ", role, ": ", label)
	return true

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--evidence="):
			directory = argument.trim_prefix("--evidence=")
	network = root.get_node("NetworkManager")
	if role == "server":
		root.add_child(load("res://scripts/core/bootstrap.gd").new())
		network.tick_completed.connect(func(_tick: int, rows: Array[Dictionary]):
			server_records.append_array(rows.duplicate(true))
			completed_ticks += 1)
		root.tree_exiting.connect(func(): write("server-final", {"checkpoint":network.capture_replay_checkpoint(),
			"header":network.replay_header(), "recording":network.replay_recorder.summary(),
			"records":server_records, "completed_ticks":completed_ticks}))
		return
	world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	network.combat_shot_received.connect(func(_start: Vector3, _end: Vector3): shots += 1)
	network.unit_death_received.connect(func(id: int): deaths.append(id))
	if not network.connect_to_server():
		quit(1)
		return
	if not await wait_for(func(): return world._visual_units.size() >= 9, "two players and original three enemies joined"):
		return
	var own: Array[int] = []
	for id: int in world._visual_units:
		if world._visual_units[id].owner_peer_id == network.multiplayer.get_unique_id():
			own.append(id)
	own.sort()
	write(role + "-ready", {"ids":own})
	if role == "observer":
		if not await wait_for(func(): return read("driver-done").get("pass", false), "driver commands complete", 90):
			return
		if not await wait_for(func(): return deaths.has(1) and shots > 0 and not world._visual_units.has(1), "damage and death visible on second client"):
			return
		write("observer-result", {"pass":true, "shots":shots, "deaths":deaths, "routes":world._route_points.keys()})
		print("PASS ENet 0.3B observer complete")
		quit(0)
		return
	if not await wait_for(func(): return FileAccess.file_exists(directory.path_join("observer-ready.json")), "second client ready"):
		return
	var vehicle: Array[int] = [own[0]]
	for mode: int in [0,1,3]:
		network.request_moves(vehicle, Vector3(-6,0,105), mode)
		if not await wait_for(func(): return world._route_points.has(own[0]), "mode %d delivered owner route" % mode):
			return
		await create_timer(0.25).timeout
		network.request_stops(vehicle)
		if not await wait_for(func(): return not world._route_points.has(own[0]), "mode %d stopped" % mode):
			return
	var armed: Array[int] = [own[0], own[1]]
	network.request_moves(armed, Vector3(-10,0,88), 2)
	if not await wait_for(func(): return deaths.has(1) and not world._visual_units.has(1) and shots > 0, "attack movement damage and enemy death", 45):
		return
	network.request_stops(armed)
	if not await wait_for(func(): return not world._route_points.has(own[0]) and not world._route_points.has(own[1]), "final stop"):
		return
	write("driver-done", {"pass":true, "shots":shots, "deaths":deaths})
	if not await wait_for(func(): return read("observer-result").get("pass",false), "second client verified death"):
		return
	print("PASS ENet 0.3B driver complete")
	quit(0)

func _process(delta: float) -> bool:
	if network == null or role != "server":
		return false
	elapsed += delta
	if elapsed < 0.2:
		return false
	elapsed = 0
	write("server-current", {"checkpoint":network.capture_replay_checkpoint(), "recording":network.replay_recorder.summary()})
	return false
