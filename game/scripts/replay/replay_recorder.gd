class_name ReplayRecorder
extends RefCounted

# Append-only staging journal is deliberately NOT an RTTReplay v1 document.
# Only finish() may publish a fully validated replay. No recovery/player in 0.3B.
signal recording_failed(message: String)

const BUFFER_BYTES := 262144
const BUFFER_TICKS := 120
var status := "disabled"
var error := ""
var output_path := ""
var journal_path := ""
var snapshot_ticks := 300
var last_tick := 0
var record_count := 0
var batch_writes := 0
var _file: FileAccess
var _buffer := ""
var _last_write_tick := 0
var _network: Node
var _owns_output := false


func start(network: Node, path: String, interval: int = 300) -> bool:
	if status != "disabled":
		return false
	_network = network
	output_path = ProjectSettings.globalize_path(path)
	journal_path = output_path + ".incomplete"
	snapshot_ticks = interval
	if path.is_empty() or path.ends_with(".incomplete") or path.ends_with(".publishing") or interval < 1 or network.timeline.tick != 0:
		return _fail("recording must start at tick 0 with a path and positive snapshot interval")
	if FileAccess.file_exists(output_path) or FileAccess.file_exists(journal_path) or FileAccess.file_exists(output_path + ".publishing") or FileAccess.file_exists(output_path + ".status.json"):
		return _fail("refusing to overwrite existing replay/staging file: " + output_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		return _fail("cannot create recording directory: %s" % directory_error)
	_file = FileAccess.open(journal_path, FileAccess.WRITE)
	if _file == null:
		return _fail("cannot open recording journal: %s" % FileAccess.get_open_error())
	_owns_output = true
	status = "recording"
	if not _append({"journal": "RTTReplayJournal", "journal_version": 1,
		"header": network.replay_header().duplicate(true), "initial_state": network.initial_replay_checkpoint.duplicate(true)}):
		return false
	if not _write_batch():
		return false
	network.tick_completed.connect(_consume_tick)
	_write_status()
	print("REPLAY recording: %s; snapshot interval %d ticks" % [output_path, snapshot_ticks])
	return true


func _consume_tick(tick: int, records: Array[Dictionary]) -> void:
	if status != "recording":
		return
	if tick != last_tick + 1:
		_fail("missing/out-of-order completed tick: expected %d, got %d" % [last_tick + 1, tick])
		return
	# Never retain signal-owned dictionaries or simulation references.
	var owned := records.duplicate(true)
	var entry := {"tick": tick, "records": owned}
	if tick % snapshot_ticks == 0:
		entry.snapshot = _network.capture_replay_checkpoint().duplicate(true)
	last_tick = tick
	record_count += owned.size()
	if not _append(entry):
		return
	if _buffer.length() >= BUFFER_BYTES or tick - _last_write_tick >= BUFFER_TICKS:
		_write_batch()


func _append(value: Dictionary) -> bool:
	# JSON must not silently coerce objects/non-finite values before final validation.
	if not ReplayFormat.is_json_safe(value):
		return _fail("recording contains non-JSON data, non-finite values or unsafe integers")
	_buffer += JSON.stringify(value, "", true, true) + "\n"
	return true


func _write_batch() -> bool:
	if _file == null:
		return _fail("recording file unavailable")
	_file.store_string(_buffer)
	_file.flush()
	if _file.get_error() != OK:
		return _fail("recording batch write failed: %s" % _file.get_error())
	_buffer = ""
	_last_write_tick = last_tick
	batch_writes += 1
	_write_status()
	return true


func finish() -> Dictionary:
	if status != "recording":
		return summary()
	if _network.timeline.phase != "idle" or _network.timeline.tick != last_tick:
		_fail("finalization requires the last completed tick boundary")
		return summary()
	var final_checkpoint: Dictionary = _network.capture_replay_checkpoint().duplicate(true)
	if not _append({"final": true, "header": _network.replay_header().duplicate(true),
		"checkpoint": final_checkpoint, "last_tick": last_tick, "record_count": record_count}):
		return summary()
	if not _write_batch():
		return summary()
	_file.close()
	_file = null
	var assembled := _assemble()
	if not assembled.error.is_empty():
		_fail(assembled.error)
		return summary()
	var publishing := output_path + ".publishing"
	var write_error := ReplayFormat.write_file(publishing, assembled.document)
	if not write_error.is_empty():
		_fail("final replay validation/write failed: " + write_error)
		return summary()
	# Read-back validation includes actual disk JSON numeric conversion.
	var verified := ReplayFormat.deserialize(FileAccess.get_file_as_string(publishing))
	if not verified.error.is_empty():
		_fail("published data read-back failed: " + verified.error)
		return summary()
	if FileAccess.file_exists(output_path):
		_fail("output appeared during recording; refusing overwrite")
		return summary()
	var rename_error := DirAccess.rename_absolute(publishing, output_path)
	if rename_error != OK:
		_fail("atomic publication failed: %s" % rename_error)
		return summary()
	status = "complete"
	_write_status()
	# Journal is retained as provenance; only output_path is the complete replay.
	print("REPLAY complete: %s; last_tick=%d; record_count=%d" % [output_path, last_tick, record_count])
	return summary()


func _assemble() -> Dictionary:
	var source := FileAccess.open(journal_path, FileAccess.READ)
	if source == null:
		return {"error": "cannot reopen recording journal", "document": {}}
	var document := {}
	var expected_tick := 1
	var finished := false
	while not source.eof_reached():
		var line := source.get_line()
		if line.is_empty() and source.eof_reached():
			break
		var parser := JSON.new()
		if parser.parse(line) != OK or not parser.data is Dictionary or finished:
			return {"error": "corrupt/trailing recording journal", "document": {}}
		var entry: Dictionary = parser.data
		if document.is_empty():
			if entry.get("journal", "") != "RTTReplayJournal" or entry.get("journal_version", 0) != 1 or not entry.get("initial_state") is Dictionary or not entry.get("header") is Dictionary:
				return {"error": "invalid recording journal header", "document": {}}
			document = ReplayFormat.document(entry.header, entry.initial_state)
		elif entry.get("final", false):
			if entry.get("last_tick", -1) != expected_tick - 1 or entry.get("record_count", -1) != document.records.size() or not entry.get("header") is Dictionary or not entry.get("checkpoint") is Dictionary:
				return {"error": "recording extent/count mismatch", "document": {}}
			document.header = entry.header
			document.last_tick = entry.last_tick
			document.record_count = entry.record_count
			if entry.last_tick > 0:
				if not document.snapshots.is_empty() and document.snapshots.back().through.tick == entry.last_tick:
					document.snapshots.pop_back()
				document.snapshots.append(entry.checkpoint)
			finished = true
		else:
			if entry.get("tick", 0) != expected_tick or not entry.get("records") is Array:
				return {"error": "recording journal tick gap", "document": {}}
			for record: Variant in entry.records:
				if not record is Dictionary or record.get("tick", -1) != entry.tick:
					return {"error": "record belongs to wrong journal tick", "document": {}}
			document.records.append_array(entry.records)
			if entry.has("snapshot"):
				if not entry.snapshot is Dictionary:
					return {"error": "invalid journal snapshot", "document": {}}
				document.snapshots.append(entry.snapshot)
			expected_tick += 1
	source.close()
	return {"error": "" if finished else "incomplete recording journal", "document": document if finished else {}}


func summary() -> Dictionary:
	return {"status": status, "error": error, "output_path": output_path, "journal_path": journal_path,
		"last_tick": last_tick, "record_count": record_count, "batch_writes": batch_writes}


func _fail(message: String) -> bool:
	status = "failed"
	error = message
	if _file != null:
		_file.close()
		_file = null
	push_error("REPLAY FAILED (match continues, incomplete data retained): " + message)
	_write_status()
	recording_failed.emit(message)
	return false


func _write_status() -> void:
	if output_path.is_empty() or not _owns_output:
		return
	var file := FileAccess.open(output_path + ".status.json", FileAccess.WRITE)
	if file == null:
		push_error("REPLAY status file unavailable: " + output_path + ".status.json")
		return
	file.store_string(JSON.stringify(summary(), "\t", true, true))
	file.flush()
	if file.get_error() != OK:
		push_error("REPLAY status write failed: %s" % file.get_error())
	file.close()
