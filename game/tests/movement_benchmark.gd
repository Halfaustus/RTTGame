extends SceneTree

# Isolated authoritative simulation, never starts a server/client or renderer.
# Timings exclude setup and instrumentation; operation counts use a separate run.
const CONFIG = preload("res://data/prototype_movement.tres")
const INF = preload("res://data/unit_stationary.tres")
const VEH = preload("res://data/unit_mobile.tres")
const REPEATS := 3
const TICKS := 90
var output_path := ""
var profile_only := false
var profile_units := 8

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		if argument == "--profile-only": profile_only = true
		if argument.begins_with("--profile-units="): profile_units = int(argument.trim_prefix("--profile-units="))
	run.call_deferred()

func scenario(kind: String, count: int, instrument: bool) -> Dictionary:
	var simulation := MovementSimulation.new(CONFIG)
	assert(simulation.initialize_navigation())
	var counters := {"enabled": true} if instrument else {}
	simulation.profile = counters
	var units: Array[UnitState] = []
	for index: int in count:
		var vehicle := kind == "vehicle" or (kind == "mixed" and index % 2 == 0)
		var state := UnitState.new(index+1,42,Vector3(-16+(index%24)*2,0.5,98+(index/24)*4))
		state.configure(1,VEH if vehicle else INF)
		state.yaw = PI
		simulation.add_unit(state)
		state.profile = counters
		units.append(state)
	var idle: Array[float] = []
	for tick: int in 12:
		var began := Time.get_ticks_usec()
		simulation.advance(1.0/60.0)
		idle.append((Time.get_ticks_usec()-began)/1000.0)
	var began := Time.get_ticks_usec()
	var accepted := 0
	for state: UnitState in units:
		if simulation.request_move(state.unit_id,42,Vector3(state.position.x,0,state.position.z+12)).is_empty(): accepted += 1
	var command_ms := (Time.get_ticks_usec()-began)/1000.0
	var command_counts := counters.duplicate()
	if instrument:
		counters.clear()
		counters["enabled"] = true
	var moving: Array[float] = []
	for tick: int in TICKS:
		began = Time.get_ticks_usec()
		simulation.advance(1.0/60.0)
		moving.append((Time.get_ticks_usec()-began)/1000.0)
	var moving_counts := counters.duplicate()
	if instrument:
		counters.clear()
		counters["enabled"] = true
	var network := preload("res://scripts/networking/network_manager.gd").new()
	var feed := PresentationFeed.new()
	var building: Array[float] = []
	var wire: Array[float] = []
	var cache: Array[float] = []
	var payload_bytes := 0
	for sample: int in 15:
		began = Time.get_ticks_usec()
		var structures: Array[Dictionary] = []
		for state: UnitState in units: structures.append(state.structure_snapshot())
		network._queue_replication("_receive_unit_structures",[structures])
		building.append((Time.get_ticks_usec()-began)/1000.0)
		began = Time.get_ticks_usec()
		payload_bytes = var_to_bytes(network._replication_queue).size()
		wire.append((Time.get_ticks_usec()-began)/1000.0)
		began = Time.get_ticks_usec()
		for structure: Dictionary in structures: feed.apply_live_structure(structure)
		cache.append((Time.get_ticks_usec()-began)/1000.0)
		network._replication_queue.clear()
	if instrument: counters["payload_constructions"] = 15
	var replication_counts := counters.duplicate()
	network.free()
	return {"kind":kind,"units":count,"soldiers":units.reduce(func(total: int, state: UnitState): return total+state.members.size(),0),
		"accepted":accepted,"idle":summary(idle),"command_ms":command_ms,"moving":summary(moving),
		"replication_build":summary(building),"wire_encode":summary(wire),"client_cache":summary(cache),"payload_bytes":payload_bytes,
		"command_counts":command_counts,"moving_counts":moving_counts,"replication_counts":replication_counts}

func summary(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value: float in values: sum += value
	return {"mean_ms":sum/values.size(),"p95_ms":sorted[mini(sorted.size()-1,floori(sorted.size()*0.95))],"max_ms":sorted[-1]}

func run() -> void:
	if profile_only:
		print("PROFILE CASE ",scenario("vehicle",profile_units,false))
		quit(0)
		return
	var results: Array[Dictionary] = []
	# Warmup the same code paths; it is not included in reported measurements.
	scenario("mixed",4,false)
	for kind: String in ["infantry","vehicle","mixed"]:
		for count: int in [8,48]:
			var samples: Array[Dictionary] = []
			for repeat: int in REPEATS:
				var result := scenario(kind,count,false)
				samples.append(result)
				print("BENCH ",kind," ",count," repeat ",repeat,": command_ms=",result.command_ms," moving=",result.moving)
			var counts := scenario(kind,count,true)
			results.append({"kind":kind,"units":count,"samples":samples,"instrumented":counts})
	var report := {"repeats":REPEATS,"moving_ticks":TICKS,"tick_hz":60,"results":results,
		"method":"separate uninstrumented wall-clock timings and instrumented operation counts; setup excluded; network build/encode/cache only, no transport"}
	if not output_path.is_empty():
		var file := FileAccess.open(output_path,FileAccess.WRITE)
		if file == null:
			push_error("Cannot write benchmark output")
			quit(1)
			return
		file.store_string(JSON.stringify(report,"\t"))
	print("BENCHMARK COMPLETE")
	quit(0)
