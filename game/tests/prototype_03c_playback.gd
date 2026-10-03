extends SceneTree

# Actual process clock and production replay entry; no server connection.
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := ""
	var evidence := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--replay-file="):
			path = argument.trim_prefix("--replay-file=")
		elif argument.begins_with("--evidence="):
			evidence = argument.trim_prefix("--evidence=")
	var started := Time.get_ticks_msec()
	session = load("res://scenes/replay/replay.tscn").instantiate()
	root.add_child(session)
	if session.world == null:
		quit(1)
		return
	var counts := {"shots":0,"deaths":0}
	session.clock.presentation.feed.combat_shot_received.connect(func(_a: Vector3,_b: Vector3): counts.shots += 1)
	session.clock.presentation.feed.unit_death_received.connect(func(_id: int): counts.deaths += 1)
	var deadline := Time.get_ticks_msec() + 30000
	while session.clock.status == "playing" and Time.get_ticks_msec() < deadline:
		await process_frame
	var playback_wall_seconds := (Time.get_ticks_msec() - started) / 1000.0
	var actual := ReplayFormat.read_file(path)
	var expected: Array = actual.document.snapshots.back().units
	var pass_value: bool = session.clock.status == "finished" and session.clock.presentation.display_states() == expected and session.clock.presentation.applied_record_count() == actual.document.record_count and counts.shots == 15 and counts.deaths == 1 and session.world._visual_units.size() == expected.size()
	pass_value = pass_value and playback_wall_seconds >= session.clock.duration_seconds - 0.05 and playback_wall_seconds <= session.clock.duration_seconds + 1.0
	for state: Dictionary in expected:
		var unit: Node3D = session.world._visual_units.get(int(state.unit_id))
		pass_value = pass_value and unit != null
		if unit != null:
			pass_value = pass_value and unit.position.distance_to(PresentationFeed.vector(state.position)) < 0.00001 and absf(unit.health-state.health) < 0.00001 and absf(wrapf(unit.get_node("MeshInstance3D").rotation.y-state.yaw,-PI,PI)) < 0.00001
	var before: Array[Dictionary] = session.clock.presentation.display_states()
	await create_timer(0.5).timeout
	pass_value = pass_value and before == session.clock.presentation.display_states() and session._time_label.text.contains("END")
	var network := root.get_node("NetworkManager")
	pass_value = pass_value and network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer and network.timeline.tick == 0 and network._authoritative_units.is_empty() and not network._movement.is_navigation_ready()
	var result := {"passed":pass_value,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"duration":session.clock.duration_seconds,
		"playback_wall_seconds":playback_wall_seconds,
		"tick":session.clock.current_tick,"record_count":session.clock.presentation.applied_record_count(),"events":counts,
		"offline":network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer,"final_states":session.clock.presentation.display_states(),"time_label":session._time_label.text}
	var file := FileAccess.open(evidence,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t",true,true))
	file.close()
	print("Actual offline playback: ","PASS" if pass_value else "FAIL")
	quit(0 if pass_value else 1)
