extends Node

var _shutdown_request := ""
var _shutdown_token := ""
var _control_elapsed := 0.0
var _stopping := false

func _enter_tree() -> void:
	if not NetworkManager.configure_active_test_map():
		push_error("Active TEST ONLY battlefield initialization failed")
		get_tree().quit(1)

func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_start_server()
	else:
		_start_client()


func _start_server() -> void:
	var recording_path := ""
	var snapshot_ticks := 300
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--record-replay="):
			recording_path = argument.trim_prefix("--record-replay=")
			if recording_path.is_empty():
				push_error("Empty replay output path")
				get_tree().quit(1)
				return
		elif argument.begins_with("--replay-snapshot-ticks="):
			var value := argument.trim_prefix("--replay-snapshot-ticks=")
			if not value.is_valid_int() or int(value) < 1:
				push_error("Invalid replay snapshot interval")
				get_tree().quit(1)
				return
			snapshot_ticks = int(value)
		elif argument.begins_with("--shutdown-request="):
			_shutdown_request = argument.trim_prefix("--shutdown-request=")
		elif argument.begins_with("--shutdown-token="):
			_shutdown_token = argument.trim_prefix("--shutdown-token=")
	NetworkManager.configure_recording(recording_path, snapshot_ticks)
	var success := NetworkManager.start_server()

	if not success:
		push_error("Dedicated server startup failed.")
		get_tree().quit(1)
	set_process(success and not _shutdown_request.is_empty() and not _shutdown_token.is_empty())


func _process(delta: float) -> void:
	if _stopping or _shutdown_request.is_empty():
		return
	_control_elapsed += delta
	if _control_elapsed < 0.2:
		return
	_control_elapsed = 0.0
	if not FileAccess.file_exists(_shutdown_request):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_shutdown_request)) != OK or not parser.data is Dictionary:
		return
	if parser.data.get("token", "") != _shutdown_token or parser.data.get("action", "") != "finish":
		return
	_stopping = true
	var result := NetworkManager.finish_server()
	var exit_code := 0 if result.status in ["disabled", "complete"] else 2
	var receipt := FileAccess.open(_shutdown_request + ".receipt.json", FileAccess.WRITE)
	if receipt == null:
		push_error("Normal shutdown receipt unavailable")
		exit_code = 2
	else:
		receipt.store_string(JSON.stringify({"normal_shutdown": true, "shutdown_token": _shutdown_token, "exit_code": exit_code, "recording": result}, "\t", true, true))
		receipt.close()
	print("SERVER normal shutdown: recording=%s; exit=%d" % [result.status, exit_code])
	get_tree().quit(exit_code)


func _start_client() -> void:
	var success := NetworkManager.connect_to_server()

	if not success:
		push_error("Client startup failed.")
