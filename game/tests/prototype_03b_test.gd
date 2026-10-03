extends SceneTree

var failures := 0
var directory := "res://../tmp/03b/unit-" + str(Time.get_ticks_usec())

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		print("PASS 0.3B: ", label)
	else:
		failures += 1
		push_error("FAIL 0.3B: " + label)

func model() -> Node:
	var result = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(result)
	check(result._movement.initialize_navigation(), "navigation ready")
	result._initialize_rebels()
	result.initial_replay_checkpoint = result.capture_replay_checkpoint()
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var network := model()
	var recorder := network.replay_recorder as ReplayRecorder
	var output := directory.path_join("complete.json")
	check(recorder.start(network, output, 3), "record tick zero before joins")
	network.tick_completed.connect(func(_tick: int, rows: Array[Dictionary]): rows.clear())
	network._on_peer_connected(42)
	network._run_server_tick(PackedInt32Array([42]))
	var ids: Array[int] = [4]
	network._queue_command({"type":"move", "group":true, "unit_ids":ids, "mode":0,
		"target":Vector3(4,0,105), "facing":Vector3.ZERO},42)
	network._run_server_tick(PackedInt32Array([42]))
	network._queue_command({"type":"stop", "unit_ids":ids, "mode":-1, "target":null, "facing":null},42)
	network._run_server_tick(PackedInt32Array([42]))
	network._on_peer_disconnected(42)
	network._run_server_tick(PackedInt32Array())
	for tick: int in 3:
		network._run_server_tick(PackedInt32Array())
	check(recorder.last_tick == 7 and recorder.batch_writes == 1, "empty ticks advance without per-tick flush")
	check(not FileAccess.file_exists(output), "no complete file before finish")
	check(not ReplayFormat.read_file(recorder.journal_path).error.is_empty(), "journal rejected as replay")
	check(recorder.finish().status == "complete", "validated atomic publication")
	var decoded := ReplayFormat.read_file(output)
	check(decoded.error.is_empty(), "published file validates")
	if decoded.error.is_empty():
		var data: Dictionary = decoded.document
		check(data.last_tick == 7 and data.snapshots.size() == 3 and data.snapshots.back().through.sequence == -1, "periodic and empty final boundaries")
		check(data.header.players.size() == 1 and data.snapshots.back().connected_player_ids.is_empty(), "historical offline players retained")
		check(data.record_count > 0 and data.records.any(func(row: Dictionary): return row.type == "move") and data.records.any(func(row: Dictionary): return row.type == "stop"), "deep copies survived signal mutation")
	check(recorder.finish().status == "complete", "finish idempotent")
	var empty := model()
	check(empty.replay_recorder.start(empty, directory.path_join("zero.json"), 2), "zero tick start")
	check(empty.replay_recorder.finish().status == "complete", "zero tick ending")
	var boundary := model()
	check(boundary.replay_recorder.start(boundary, directory.path_join("boundary.json"), 2), "exact snapshot boundary starts")
	for i: int in 2:
		boundary._run_server_tick(PackedInt32Array())
	check(boundary.replay_recorder.finish().status == "complete" and ReplayFormat.read_file(directory.path_join("boundary.json")).document.snapshots.size() == 1, "periodic final snapshot emitted once")
	var overwrite := model()
	check(not overwrite.replay_recorder.start(overwrite, output), "existing replay never overwritten")
	var failed := model()
	var blocked := directory.path_join("blocked")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	check(not failed.replay_recorder.start(failed, blocked.path_join("replay.json")), "output failure explicit")
	failed._run_server_tick(PackedInt32Array())
	check(failed.timeline.tick == 1 and failed.replay_recorder.status == "failed", "match continues after recorder failure")
	var gap := model()
	check(gap.replay_recorder.start(gap, directory.path_join("gap.json")), "gap test start")
	var no_records: Array[Dictionary] = []
	gap.tick_completed.emit(2, no_records)
	check(gap.replay_recorder.status == "failed" and not FileAccess.file_exists(gap.replay_recorder.output_path), "missing tick never publishes")
	var interrupted := model()
	check(interrupted.replay_recorder.start(interrupted, directory.path_join("interrupted.json")), "interruption test start")
	for i: int in 120:
		interrupted._run_server_tick(PackedInt32Array())
	check(interrupted.replay_recorder.batch_writes == 2 and not FileAccess.file_exists(interrupted.replay_recorder.output_path), "buffered staging without complete output")
	check(not ReplayFormat.read_file(interrupted.replay_recorder.journal_path).error.is_empty(), "unfinished journal rejected")
	interrupted.replay_recorder._file.close()
	interrupted.replay_recorder._file = null
	check(not interrupted.replay_recorder._write_batch() and interrupted.replay_recorder.status == "failed", "batch failure explicit and staging retained")
	var corrupt := model()
	check(corrupt.replay_recorder.start(corrupt, directory.path_join("corrupt.json")), "corruption test starts")
	corrupt._run_server_tick(PackedInt32Array())
	corrupt.replay_recorder._file.store_string("corrupt journal line\n")
	check(corrupt.replay_recorder.finish().status == "failed" and not FileAccess.file_exists(corrupt.replay_recorder.output_path), "corrupt staging never published")
	var unsafe := model()
	check(unsafe.replay_recorder.start(unsafe, directory.path_join("unsafe.json")), "JSON coercion test starts")
	check(not unsafe.replay_recorder._append({"key":Resource.new()}) and unsafe.replay_recorder.status == "failed", "unsupported objects fail before JSON coercion")
	print("Prototype 0.3B recorder checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
