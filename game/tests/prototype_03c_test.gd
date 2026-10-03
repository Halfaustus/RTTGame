extends SceneTree

var failures := 0
var actual_path := "res://../tmp/03b/enet-225234/match.rttreplay.json"

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		print("PASS 0.3C: ", label)
	else:
		failures += 1
		push_error("FAIL 0.3C: " + label)

func view(clock: ReplayClock, player: int) -> Node3D:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	world.replay_mode = true
	world.view_player_id = player
	world.presentation_source = clock.presentation.feed
	root.add_child(world)
	return world

func matches(world: Node3D, states: Array) -> bool:
	if world._visual_units.size() != states.size():
		return false
	for state: Dictionary in states:
		if not world._visual_units.has(int(state.unit_id)):
			return false
		var visual: Node3D = world._visual_units[int(state.unit_id)]
		if visual.position.distance_to(PresentationFeed.vector(state.position)) > 0.00001 or absf(visual.health-state.health) > 0.00001 or visual.team_id != state.team_id or visual.owner_peer_id != state.owner_player_id or absf(wrapf(visual.get_node("MeshInstance3D").rotation.y-state.yaw,-PI,PI)) > 0.00001:
			return false
	return true

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--actual-replay="):
			actual_path = argument.trim_prefix("--actual-replay=")
	var frozen := ReplayFormat.read_file("res://tests/fixtures/replay_v1.json")
	check(frozen.error.is_empty(), "frozen v1 unchanged and readable")
	var data: Dictionary = frozen.document.duplicate(true)
	# In-memory extension only; never rewrite the frozen fixture.
	data.last_tick = 5
	var final: Dictionary = data.snapshots.back().duplicate(true)
	final.through = {"tick":5, "sequence":-1}
	data.snapshots.append(final)
	check(ReplayFormat.validate(data).is_empty(), "valid empty tick tail fixture")
	var clock := ReplayClock.new()
	check(clock.open(data,1).is_empty(), "clock accepts v1")
	var world := view(clock,1)
	var seen := {"shots":0,"finished":0}
	clock.presentation.feed.combat_shot_received.connect(func(_a: Vector3,_b: Vector3): seen.shots += 1)
	clock.playback_finished.connect(func(): seen.finished += 1)
	check(clock.start() and matches(world,data.initial_state.units), "initial state at tick zero")
	clock.advance(0.5 / clock.tick_hz)
	check(clock.current_tick == 0 and seen.shots == 0, "no early event between ticks")
	clock.advance(0.5 / clock.tick_hz)
	check(clock.current_tick == 1 and seen.shots == 1 and not world._visual_units.has(2) and world._route_points.has(1), "same tick sequence shot death state applied once")
	var cursor := clock.presentation.cursor()
	world._clear_movement_paths()
	world.view_player_id = 0
	clock.presentation.refresh_display()
	check(world._route_points.is_empty() and clock.presentation.cursor() == cursor and seen.shots == 1 and not world._visual_units.has(2), "route view change does not replay shots or revive units")
	world.view_player_id = 1
	clock.presentation.refresh_display()
	check(world._route_points.has(1) and world._visual_units[1].owner_peer_id == 1 and world._visual_units[1].owner_peer_id != 42, "routes use match player ID, not fixture peer 42")
	clock.advance(2.0 / clock.tick_hz)
	check(clock.current_tick == 3 and clock.status == "playing" and clock.presentation.applied_record_count() == data.record_count and world._route_points.is_empty(), "empty ticks consume time after final event")
	clock.advance(10.0)
	check(clock.status == "finished" and clock.current_tick == 5 and is_equal_approx(clock.elapsed_seconds,5.0/clock.tick_hz) and seen.finished == 1, "end clamps to total duration")
	clock.advance(10.0)
	check(seen.shots == 1 and seen.finished == 1 and matches(world, final.units), "end stays fixed without duplicated events")
	world.free()
	var actual := ReplayFormat.read_file(actual_path)
	check(actual.error.is_empty(), "actual 0.3B complete recording loads")
	if actual.error.is_empty():
		check(ReplayContent.compatibility(actual.document).is_empty(), "actual map rules and full manifest match")
		var bad: Dictionary = actual.document.duplicate(true)
		bad.header.map_id = "wrong-map"
		check(not ReplayContent.compatibility(bad).is_empty(), "wrong map rejected")
		bad = actual.document.duplicate(true)
		bad.header.rules_id = "wrong-rules"
		check(not ReplayContent.compatibility(bad).is_empty(), "wrong rules rejected")
		bad = actual.document.duplicate(true)
		bad.header.content_fingerprints[ReplayContent.FILES[0]] = "0".repeat(64)
		check(not ReplayContent.compatibility(bad).is_empty(), "wrong fingerprint rejected")
		bad = actual.document.duplicate(true)
		bad.header.content_fingerprints.clear()
		check(not ReplayContent.compatibility(bad).is_empty(), "missing fingerprint manifest rejected")
		check(not ReplayFormat.read_file(actual_path + ".incomplete").error.is_empty(), "unfinished journal cannot load")
		for delta: float in [1.0/60,0.37,100.0]:
			var player := ReplayClock.new()
			check(player.open(actual.document,1).is_empty(), "actual recording clock opens")
			var display := view(player,1)
			var events := {"shots":0,"deaths":0}
			player.presentation.feed.combat_shot_received.connect(func(_a: Vector3,_b: Vector3): events.shots += 1)
			player.presentation.feed.unit_death_received.connect(func(_id: int): events.deaths += 1)
			player.start()
			while player.status == "playing":
				check(player.advance(delta), "ordered frame advance")
			check(player.status == "finished" and player.presentation.applied_record_count() == actual.document.record_count and player.presentation.display_states() == actual.document.snapshots.back().units and matches(display, actual.document.snapshots.back().units), "actual final state and all records match at delta %.3f" % delta)
			check(events.shots == 15 and events.deaths == 1, "low FPS and large delta neither lose nor duplicate events")
			var key := InputEventKey.new()
			key.keycode = KEY_Q
			key.pressed = true
			display._unhandled_input(key)
			display._request_stop_selected()
			check(display._pending_actions.is_empty() and not display._attack_move_armed and root.get_node("NetworkManager")._pending_commands.is_empty(), "game operations cannot send replay commands")
			display.free()
	var zero: Dictionary = data.duplicate(true)
	zero.records = []
	zero.snapshots = []
	zero.last_tick = 0
	zero.record_count = 0
	var zero_clock := ReplayClock.new()
	check(zero_clock.open(zero).is_empty() and zero_clock.start() and zero_clock.status == "finished", "zero-duration replay ends at initial state")
	var network := root.get_node("NetworkManager")
	check(network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer and network.timeline.tick == 0 and network._authoritative_units.is_empty() and not network._movement.is_navigation_ready(), "no connection simulation navigation AI or authoritative generation")
	print("Prototype 0.3C checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
