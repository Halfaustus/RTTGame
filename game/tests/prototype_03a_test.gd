extends SceneTree

const CONFIG = preload("res://data/prototype_movement.tres")
var failures := 0
var replay_shots := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL 0.3A: " + label)
	else:
		print("PASS 0.3A: ", label)


func move(ids: Array[int], mode: int = 0) -> Dictionary:
	return {"type": "move", "group": true, "unit_ids": ids, "mode": mode,
		"target": Vector3(8, 0, 110), "facing": Vector3.RIGHT}


func finish_document(model: Node, initial: Dictionary, records: Array[Dictionary], snapshots: Array[Dictionary]) -> Dictionary:
	var data := ReplayFormat.document(model.replay_header(), initial)
	data.records = records.duplicate(true)
	data.snapshots = snapshots.duplicate(true)
	data.record_count = records.size()
	data.last_tick = model.timeline.tick
	return data


func _server_checks() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	check(model._movement.initialize_navigation(), "server navigation")
	model._initialize_rebels()
	var initial: Dictionary = model.capture_replay_checkpoint()
	var records: Array[Dictionary] = []
	var snapshots: Array[Dictionary] = []
	model.tick_completed.connect(func(_tick: int, rows: Array[Dictionary]):
		check(model.timeline.phase == "record", "record hook after combat, before replication")
		records.append_array(rows))
	model._on_peer_connected(42)
	model._on_peer_connected(99)
	check(model._authoritative_units.size() == 3, "join callbacks do not mutate authoritative state")
	model._run_server_tick(PackedInt32Array([42, 99]))
	snapshots.append(model.capture_replay_checkpoint())
	check(model._peer_players[42] == 1 and model._peer_players[99] == 2 and model._authoritative_units[4].owner_peer_id == 42 and model._authoritative_units[4].owner_player_id == 1, "match player identity separate from peer ID")
	for mode: int in [0, 1, 2, 3]:
		var ids: Array[int] = [4, 999, 7]
		var old: Dictionary = model._movement.command_snapshot(4)
		model._queue_command(move(ids, mode), 42)
		check(model._movement.command_snapshot(4) == old, "command remains queued before tick")
		model._run_server_tick(PackedInt32Array([42, 99]))
		check(model._movement.command_snapshot(4).mode == mode and model.timeline.records[0].payload.accepted_ids == [4], "mode/path recorded and ownership individually filtered")
		snapshots.append(model.capture_replay_checkpoint())
	var stop_ids: Array[int] = [4, 999, 4]
	model._queue_command({"type": "stop", "unit_ids": stop_ids, "mode": -1, "target": null, "facing": null}, 42)
	model._run_server_tick(PackedInt32Array([42, 99]))
	check(model._movement.command_snapshot(4).mode == -1, "stop cancels route and final turn at command phase")
	snapshots.append(model.capture_replay_checkpoint())
	var invalid := move([4])
	invalid.target = Vector3(NAN, 0, 110)
	model._queue_command(invalid, 42)
	model._run_server_tick(PackedInt32Array([42, 99]))
	check(model.timeline.records[0].payload.target == null and model.timeline.records[0].payload.accepted_ids.is_empty(), "non-finite rejected input remains JSON-safe audit data")
	snapshots.append(model.capture_replay_checkpoint())
	var oversized := move([9223372036854775807])
	oversized.mode = 9223372036854775807
	model._queue_command(oversized, 42)
	model._run_server_tick(PackedInt32Array([42, 99]))
	check(model.timeline.records[0].payload.mode == {"invalid_integer": "9223372036854775807"}, "unsafe rejected int64 input preserves exact text")
	snapshots.append(model.capture_replay_checkpoint())
	model._queue_command(move([4]), 42)
	model._on_peer_disconnected(42)
	model._on_peer_connected(42)
	model._run_server_tick(PackedInt32Array([42, 99]))
	check(model._peer_players[42] == 3 and model._authoritative_units[10].owner_player_id == 3 and model.timeline.records.any(func(row: Dictionary): return row.kind == "command" and row.payload.accepted_ids.is_empty()), "reused peer rejects previous player queued command")
	snapshots.append(model.capture_replay_checkpoint())
	model._queue_command(move([4, 10]), 42)
	model._run_server_tick(PackedInt32Array([42, 99]))
	check(model.timeline.records[0].payload.accepted_ids == [10] and model._movement.command_snapshot(4).mode == -1, "reused peer cannot control old player's units")
	check(model._next_unit_id == 13 and model._authoritative_units.has(1) and model._authoritative_units.has(3), "monotonic IDs and no repeat enemy generation")
	snapshots.append(model.capture_replay_checkpoint())
	var data := finish_document(model, initial, records, snapshots)
	check(ReplayFormat.validate(data).is_empty(), "production tick states form valid replay data: " + ReplayFormat.validate(data))
	check(ReplayFormat.write_file("res://../tmp/03a/server-model.json", data).is_empty(), "serialize actual isolated server pipeline evidence")
	check(ReplayFormat.read_file("res://../tmp/03a/server-model.json").error.is_empty(), "validate server data after native-to-JSON conversion")
	var count: int = model._pending_commands.size()
	model._submit_stop(stop_ids)
	check(model._pending_commands.size() == count, "RPC entry rejects unauthenticated local sender")
	check(model.timeline.phase == "idle" and model.timeline.records.size() < records.size(), "only current tick buffered, no full recorder")
	model.queue_free()
	await process_frame


func _combat_tick_checks() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	model.legacy_combat_fixture_enabled = true
	root.add_child(model)
	var map := PrototypeMapDefinition.new()
	check(model._movement.initialize_navigation(map), "isolated combat navigation")
	model._combat = CombatSimulation.new(map)
	model._players[1] = {"player_id": 1, "label": "Player 1"}
	model._peer_players[42] = 1
	var attacker := UnitState.new(1, 42, Vector3(10, 0.5, 100))
	attacker.owner_player_id = 1
	attacker.configure(1, preload("res://data/unit_mobile.tres"))
	var enemy := UnitState.new(2, 0, Vector3(11, 0.5, 100))
	enemy.configure(2, preload("res://data/unit_unarmed.tres"))
	enemy.health = 5
	for unit: UnitState in [attacker, enemy]:
		model._authoritative_units[unit.unit_id] = unit
		model._movement.add_unit(unit)
		model._combat.add_unit(unit)
	model._next_unit_id = 3
	var initial: Dictionary = model.capture_replay_checkpoint()
	var command := move([1])
	command.target = Vector3(12, 0, 100)
	model._queue_command(command, 42)
	model._run_server_tick(PackedInt32Array([42]))
	check(model.timeline.tick == 1 and absf(attacker.yaw) <= PI / model.timeline.tick_hz + 0.00001, "server step uses fixed tick interval")
	var types: Array = []
	for row: Dictionary in model.timeline.records:
		types.append(row.type)
	check(types == ["move", "shot", "death", "unit_state"], "command then movement/combat death then final record order")
	var records: Array[Dictionary] = model.timeline.records.duplicate(true)
	var snapshots: Array[Dictionary] = [model.capture_replay_checkpoint()]
	var data := finish_document(model, initial, records, snapshots)
	check(ReplayFormat.validate(data).is_empty() and snapshots[0].retired_unit_ids == [2], "same-tick damage/death checkpoint validates without revival")
	check(ReplayFormat.write_file("res://../tmp/03a/combat-model.json", data).is_empty(), "serialize combat pipeline evidence")
	check(ReplayFormat.read_file("res://../tmp/03a/combat-model.json").error.is_empty(), "validate combat data after native-to-JSON conversion")
	var yaw: float = attacker.yaw
	model._physics_process(0.9)
	check(model.timeline.tick == 2 and absf(attacker.yaw - yaw) <= PI / model.timeline.tick_hz + 0.00001, "physics delta cannot change fixed tick step")
	model.queue_free()
	await process_frame


func _format_checks(data: Dictionary) -> void:
	check(ReplayFormat.validate(data).is_empty(), "v1 golden fixture compatibility")
	var encoded := ReplayFormat.serialize(data)
	var decoded := ReplayFormat.deserialize(encoded.text)
	check(encoded.error.is_empty() and decoded.error.is_empty() and decoded.document == data, "JSON round trip preserves state, routes, random result and IDs")
	check(ReplayFormat.write_file("res://../tmp/03a/round-trip.json", data).is_empty() and ReplayFormat.read_file("res://../tmp/03a/round-trip.json").error.is_empty(), "file serialization/read validation")
	check(not ReplayFormat.deserialize("{broken").error.is_empty(), "malformed JSON rejected")
	for scenario: String in ["version", "sequence", "phase", "checkpoint_boundary", "snapshot_health", "death_reuse", "death_duplicate", "identity", "health", "mode", "owner", "vector", "unsafe_integer", "count", "final_checkpoint", "native_object"]:
		var bad := data.duplicate(true)
		match scenario:
			"version": bad.header.format_version = 2
			"sequence": bad.records[1].sequence = 8
			"phase": bad.records[1].phase = "commands"
			"checkpoint_boundary": bad.snapshots[0].through.sequence = 1
			"snapshot_health": bad.snapshots[0].units[0].health = 80
			"death_reuse":
				bad.records.append({"tick": 3, "sequence": 0, "phase": "session", "kind": "event", "type": "spawn", "payload": bad.initial_state.units[1].duplicate(true)})
				bad.last_tick = 3
				bad.record_count += 1
			"death_duplicate": bad.records[3].type = "death"; bad.records[3].phase = "combat"; bad.records[3].payload = {"unit_id": 2}
			"identity": bad.records[3].payload.owner_player_id = 0
			"health": bad.initial_state.units[0].health = NAN
			"mode": bad.records[0].payload.mode = 99
			"owner": bad.records[0].payload.player_id = 9
			"vector": bad.initial_state.units[0].position = [0, 1]
			"unsafe_integer": bad.initial_state.next_unit_id = 9007199254740992
			"count": bad.record_count -= 1
			"final_checkpoint": bad.snapshots.pop_back()
			"native_object": bad.header.extra = CONFIG
		check(not ReplayFormat.validate(bad).is_empty(), "reject " + scenario)
	check(ReplayFormat.compatibility(data, "fixture-map-v1", "fixture-rules-v1", {"fixture-map": "0".repeat(64)}).is_empty(), "matching content identifiers/fingerprint")
	check(not ReplayFormat.compatibility(data, "wrong-map", "fixture-rules-v1", {}).is_empty() and not ReplayFormat.compatibility(data, "fixture-map-v1", "fixture-rules-v1", {"fixture-map": "1".repeat(64)}).is_empty(), "map/rules/content mismatch rejected")


func _presentation_checks(data: Dictionary) -> void:
	var adapter := ReplayPresentation.new()
	check(adapter.open(data, 1).is_empty(), "offline adapter accepts validated data")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	world.replay_mode = true
	world.presentation_source = adapter.feed
	world.view_player_id = 1
	root.add_child(world)
	adapter.feed.combat_shot_received.connect(func(_a: Vector3, _b: Vector3): replay_shots += 1)
	var network := root.get_node("NetworkManager")
	var before: Array[Dictionary] = network.live_snapshots()
	check(not adapter.apply_record(data.records[0]), "record application requires a checkpoint first")
	check(adapter.apply_checkpoint() and world._visual_units.size() == 2, "initial checkpoint builds presentation only")
	check(not adapter.apply_record(data.records[1]), "out-of-order record cannot skip a command")
	for record: Dictionary in data.records:
		check(adapter.apply_record(record), "ordered record applied once")
	check(replay_shots == 1 and world._visual_units.size() == 1 and not world._visual_units.has(2), "shot/death presentation without local damage simulation")
	check(not adapter.apply_record(data.records[-1]) and replay_shots == 1, "duplicate record ignored")
	check(adapter.apply_checkpoint(0) and world._visual_units[1].position == Vector3(12, 0.5, 100) and world._route_points.has(1), "checkpoint restores current pose and owner route")
	check(not adapter.apply_record(data.records[1]) and replay_shots == 1, "snapshot-covered shot is never replayed")
	for i: int in range(4, data.records.size()):
		check(adapter.apply_record(data.records[i]), "only records strictly after checkpoint applied")
	check(not world._route_points.has(1) and world._visual_units[1].health == 100, "stop and absolute health from recorded state")
	world._request_stop_selected()
	world._request_move_at(Vector2(100, 100))
	check(network._pending_commands.is_empty() and network.live_snapshots() == before and network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "replay view neither connects nor executes authoritative commands/AI")
	var live_feed := PresentationFeed.new()
	var live = load("res://scenes/maps/test_world.tscn").instantiate()
	live.presentation_source = live_feed
	root.add_child(live)
	live_feed.apply_live_unit({"unit_id": 33, "owner_peer_id": 1, "position": Vector3(4, 0.5, 100), "unit_type": 1, "armed": true, "team_id": 1, "maximum_health": 100, "health": 57, "yaw": 0.7})
	check(live._visual_units[33].health == 57 and absf(live._visual_units[33].get_node("MeshInstance3D").rotation.y - 0.7) < 0.00001, "live and replay feed share production presentation")
	world.queue_free()
	live.queue_free()
	await process_frame


func _run() -> void:
	var loaded := ReplayFormat.read_file("res://tests/fixtures/replay_v1.json")
	check(loaded.error.is_empty(), "read frozen v1 fixture: " + loaded.error)
	if not loaded.error.is_empty():
		quit(1)
		return
	_format_checks(loaded.document)
	await _server_checks()
	await _combat_tick_checks()
	await _presentation_checks(loaded.document)
	print("Prototype 0.3A replay foundation checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
