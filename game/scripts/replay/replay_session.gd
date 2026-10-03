extends Node

var clock := ReplayClock.new()
var world: Node3D
var _time_label: Label
var _view_selector: OptionButton
var _shutdown_request := ""
var _shutdown_token := ""
var _control_elapsed := 0.0
var _stopping := false
var _last_frame_usec := 0

func _ready() -> void:
	var path := ""
	var player_id := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--replay-file="):
			path = argument.trim_prefix("--replay-file=")
		elif argument.begins_with("--view-player-id="):
			var value := argument.trim_prefix("--view-player-id=")
			if not value.is_valid_int() or int(value) < 0 or int(value) > ReplayFormat.MAX_INTEGER:
				_reject("invalid match player_id")
				return
			player_id = int(value)
		elif argument.begins_with("--replay-stop-request="):
			_shutdown_request = argument.trim_prefix("--replay-stop-request=")
		elif argument.begins_with("--replay-stop-token="):
			_shutdown_token = argument.trim_prefix("--replay-stop-token=")
	var decoded := ReplayFormat.read_file(path)
	if not decoded.error.is_empty():
		_reject(decoded.error)
		return
	var compatibility := ReplayContent.compatibility(decoded.document)
	if not compatibility.is_empty():
		_reject(compatibility)
		return
	var open_error := clock.open(decoded.document, player_id)
	if not open_error.is_empty():
		_reject(open_error)
		return
	# No presentation scene is loaded until all compatibility checks pass.
	world = load("res://scenes/maps/test_world.tscn").instantiate()
	world.replay_mode = true
	world.presentation_source = clock.presentation.feed
	world.view_player_id = player_id
	add_child(world)
	_build_overlay(decoded.document.header.players, player_id)
	clock.progress_changed.connect(_show_time)
	clock.playback_finished.connect(func():
		_show_time(clock.duration_seconds, clock.duration_seconds, clock.current_tick)
		print("REPLAY finished: tick=%d; records=%d" % [clock.current_tick, clock.presentation.applied_record_count()]))
	if not clock.start():
		_reject("cannot apply initial replay checkpoint")
		return
	_last_frame_usec = Time.get_ticks_usec()
	print("REPLAY playback ready: %s; 1x; player_id=%d; duration=%.3fs" % [path, player_id, clock.duration_seconds])

func _build_overlay(players: Array, player_id: int) -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	canvas.add_child(box)
	_time_label = Label.new()
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_time_label)
	_view_selector = OptionButton.new()
	_view_selector.add_item("Routes: none", 0)
	# Store full match IDs as metadata, not temporary peers or 32-bit widget IDs.
	_view_selector.set_item_metadata(0, 0)
	for player: Dictionary in players:
		_view_selector.add_item("Routes: player_id %d (%s)" % [int(player.player_id), player.label])
		var index := _view_selector.item_count - 1
		_view_selector.set_item_metadata(index, int(player.player_id))
		if player.player_id == player_id:
			_view_selector.select(index)
	box.add_child(_view_selector)
	_view_selector.item_selected.connect(_select_view)

func _select_view(index: int) -> void:
	var id: int = _view_selector.get_item_metadata(index)
	world._clear_movement_paths()
	world.view_player_id = id
	clock.presentation.view_player_id = id
	clock.presentation.refresh_display()
	_view_selector.release_focus()

func _show_time(seconds: float, duration: float, tick: int) -> void:
	_time_label.text = "Replay 1x  %.2fs / %.2fs  tick %d%s" % [seconds, duration, tick, "  END" if clock.status == "finished" else ""]

func _process(_delta: float) -> void:
	# Godot may clamp process delta at very low FPS (physics catch-up limit).
	# Offline 1x follows monotonic elapsed wall time instead of simulation delta.
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _last_frame_usec) / 1000000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now
	if clock.status == "playing" and not clock.advance(elapsed):
		_reject(clock.error)
	_poll_stop(elapsed)

func _poll_stop(delta: float) -> void:
	if _stopping or _shutdown_request.is_empty() or _shutdown_token.is_empty():
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
	if parser.data.get("token", "") != _shutdown_token or parser.data.get("action", "") != "stop_replay":
		return
	_stopping = true
	print("REPLAY stopped: tick=%d" % clock.current_tick)
	get_tree().quit(0)

func _reject(message: String) -> void:
	push_error("REPLAY rejected: " + message)
	set_process(false)
	get_tree().quit(1)
