extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			directory = argument.trim_prefix("--evidence=")
	var decoded := ReplayFormat.read_file(directory.path_join("match.rttreplay.json"))
	var parser := JSON.new()
	var error: String = decoded.error
	if parser.parse(FileAccess.get_file_as_string(directory.path_join("server-final.json"))) != OK or not parser.data is Dictionary:
		error = "missing independent server evidence"
	if error.is_empty():
		var data: Dictionary = decoded.document
		var actual: Dictionary = parser.data
		if data.records != actual.records or data.header != actual.header or data.snapshots.back() != actual.checkpoint or data.last_tick != actual.completed_ticks or data.last_tick != actual.recording.last_tick or data.record_count != actual.recording.record_count or actual.recording.status != "complete":
			error = "replay differs from authoritative server records/header/checkpoint/tick/count"
		var types := {}
		var modes := {}
		for row: Dictionary in data.records:
			types[row.type] = types.get(row.type,0) + 1
			if row.type == "move" and not row.payload.accepted_ids.is_empty():
				modes[int(row.payload.mode)] = true
		for type: String in ["player_join","player_leave","spawn","move","stop","unit_state","shot","death"]:
			if not types.has(type):
				error = "missing required real ENet record: " + type
		if types.get("player_join",0) != 2 or types.get("player_leave",0) != 2 or data.header.players.size() != 2 or not data.snapshots.back().connected_player_ids.is_empty() or modes.size() != 4:
			error = "join/leave/history/all-mode coverage mismatch"
		print("ENet event counts: ", types)
		print("last_tick=",data.last_tick," record_count=",data.record_count," snapshots=",data.snapshots.size())
	if not error.is_empty():
		push_error("FAIL ENet replay audit: " + error)
	else:
		print("PASS ENet replay: all records, final state, header, tick and count exactly match independent server capture")
	quit(0 if error.is_empty() else 1)
