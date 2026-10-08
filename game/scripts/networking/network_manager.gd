extends Node

signal tick_completed(tick: int, records: Array[Dictionary])
signal deployment_state_received(state: Dictionary)
signal deployment_result_received(result: Dictionary)
signal deployment_event(event: Dictionary)
signal weapon_fire_received(event: Dictionary)
signal projectile_spawn_received(event: Dictionary)
signal projectile_terminal_received(event: Dictionary)
signal acceptance_explosion_received(event: Dictionary)
signal command_notice_received(notice: Dictionary)

signal unit_spawn_received(unit_id: int, owner_peer_id: int, position: Vector3)
signal unit_positions_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_targets_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_paths_received(unit_ids: Array[int], paths: Array[PackedVector3Array])
signal unit_combat_state_received(unit_id: int, team_id: int, maximum_health: float, health: float)
signal combat_shot_received(start: Vector3, end: Vector3)
signal unit_death_received(unit_id: int)
signal unit_stops_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_armament_received(unit_id: int, armed: bool)
signal unit_type_received(unit_id: int, unit_type: int)
signal unit_orientations_received(unit_ids: Array[int], yaws: Array[float])

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 16
const INTERNAL_STATE_REPLICATION_HZ := 10 # Temporary 0.5B parameter; unchanged.
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const COMBAT_CONFIG: CombatConfig = preload("res://data/prototype_combat.tres")
const DEPLOYMENT_CONFIG: DeploymentConfig = preload("res://data/prototype_deployment.tres")

# Only the dedicated server writes authoritative unit state.
var presentation := PresentationFeed.new()
var timeline := SimulationTimeline.new(Engine.physics_ticks_per_second)
var _replication_queue: Array[Dictionary] = []
var _pending_sessions: Array[Dictionary] = []
var _pending_commands: Array[Dictionary] = []
var _pending_deployment_requests: Array[Dictionary] = []
var _dirty_deployment: Dictionary[int, bool] = {}
var deployment := DeploymentEconomy.new()
var local_deployment_state: Dictionary = {}
var local_player_id := 0 # Authenticated domain identity received in own account state.
var _peer_players: Dictionary[int, int] = {}
var _players: Dictionary[int, Dictionary] = {}
var _next_player_id := 1
var _retired_unit_ids: Array[int] = []
var _dirty_units: Dictionary[int, bool] = {}
var _match_header: Dictionary = {}
var initial_replay_checkpoint: Dictionary = {}
var replay_recorder := ReplayRecorder.new()
var _recording_path := ""
var _snapshot_ticks := 300
var _next_unit_id: int = 1
var _authoritative_units: Dictionary[int, UnitState] = {}
var _movement := MovementSimulation.new(MOVEMENT_CONFIG)
var _task_queue := UnitTaskQueue.new()
var _task_queue_revision := -1
signal task_queue_received(rows: Array)
var local_task_queues: Dictionary = {}
var combat_outcomes := CombatOutcomeLedger.new()
var _dirty_statistics: Dictionary = {}
var local_combat_statistics: Dictionary = {}
signal combat_statistics_received(statistics: Dictionary)
var _dirty_combat_overview := true
var local_combat_overview: Dictionary = {}
signal combat_overview_received(overview: Dictionary)
var _marker_activity: Dictionary = {} # Filled only by authoritative ability services.
var _pending_positions: Dictionary[int, Vector3] = {}
var _replication_elapsed: float = 0.0
var _combat := CombatSimulation.new(MovementSimulation.MAP_DEFINITION)
var _aiming := AimingSimulation.new()
var _fire := FireSimulation.new()
var _projectiles: DB29ProjectileSimulation
var _combat_timeline := DB29CombatTimeline.new()
var _server_clock := FixedStepClock.new()
var _artillery := ArtillerySimulation.new()
var _previous_ballistic_positions: Dictionary = {}
var legacy_combat_fixture_enabled := false # Explicit historical test opt-in only.
var _weapon_presets: Array[UnitDefinition] = [preload("res://data/units/db33_active_test_squad.tres"),preload("res://data/units/db33_active_test_squad.tres")]
var _rebels_initialized: bool = false
var _player_spawn_index: int = 1
var acceptance_06c := false
var acceptance_full_06 := false
var _acceptance_auto_units: Dictionary = {}
var _acceptance_known_enemies: Dictionary = {}
# Server-owned discovery integration seam. An absent provider proves no enemy
# visibility; production discovery remains deferred. Never supplied by RPC.
var authoritative_visibility_provider: Callable

func configure_acceptance_06c(full: bool = false) -> bool:
	if deployment.is_ready() or not _authoritative_units.is_empty() or timeline.tick != 0 or legacy_combat_fixture_enabled: return false
	var presets: Array[UnitDefinition] = [load("res://data/units/acceptance_06c_normal.tres"),load("res://data/units/acceptance_06c_top.tres"),load("res://data/units/acceptance_06c_armor.tres")]
	if full:
		presets.append(load("res://data/units/acceptance_06c_suppression.tres"))
		presets.append(load("res://data/units/acceptance_06c_modules.tres"))
		presets.append(load("res://data/units/acceptance_06c_manual.tres"))
		presets.append(load("res://data/units/acceptance_06c_mechanical.tres"))
	for definition: UnitDefinition in presets:
		if definition == null or not definition.configuration_source.begins_with("test_only:rtt_unit_editor:") or not definition.spatial_valid(): return false
	_weapon_presets = presets
	acceptance_06c = true
	acceptance_full_06 = full
	if full: _movement._config.units_per_peer = 7
	return true

func _unit_disclosed(id: int) -> bool:
	return _authoritative_units.has(id) and (_authoritative_units[id].team_id == COMBAT_CONFIG.player_team_id or (acceptance_06c and _acceptance_known_enemies.has(id)))

# Explicit activity selection; historical isolated models retain their map.
func configure_active_test_map() -> bool:
	if deployment.is_ready() or not _authoritative_units.is_empty() or timeline.tick != 0 or legacy_combat_fixture_enabled:
		return false
	_movement = MovementSimulation.new(preload("res://data/db33_active_test_movement.tres"))
	return _movement.initialize_navigation()


func _ready() -> void:
	presentation.weapon_fire_received.connect(weapon_fire_received.emit)
	presentation.projectile_spawn_received.connect(projectile_spawn_received.emit)
	presentation.projectile_terminal_received.connect(projectile_terminal_received.emit)
	deployment.state_changed.connect(func(player_id: int): _dirty_deployment[player_id] = true)
	deployment.event_emitted.connect(deployment_event.emit)
	presentation.unit_spawn_received.connect(unit_spawn_received.emit)
	presentation.unit_positions_received.connect(unit_positions_received.emit)
	presentation.unit_move_targets_received.connect(unit_move_targets_received.emit)
	presentation.unit_move_paths_received.connect(unit_move_paths_received.emit)
	presentation.unit_combat_state_received.connect(unit_combat_state_received.emit)
	presentation.combat_shot_received.connect(combat_shot_received.emit)
	presentation.unit_death_received.connect(unit_death_received.emit)
	presentation.unit_stops_received.connect(unit_stops_received.emit)
	presentation.unit_armament_received.connect(unit_armament_received.emit)
	presentation.unit_type_received.connect(unit_type_received.emit)
	presentation.unit_orientations_received.connect(unit_orientations_received.emit)
	set_physics_process(false)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_server(port: int = DEFAULT_PORT) -> bool:
	if not _recording_path.is_empty() and _movement._config == preload("res://data/db33_active_test_movement.tres"):
		push_error("Active TEST ONLY battlefield recording requires a future explicit replay format decision")
		return false
	if not _ensure_deployment_ready():
		return false
	# Finish the synchronous static grid before accepting connections or commands.
	if not _movement.is_navigation_ready() and not _movement.initialize_navigation():
		push_error("Dedicated server navigation initialization failed.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)

	if error != OK:
		push_error(
			"Failed to start server on port %d. Error: %s"
			% [port, error]
		)
		return false

	multiplayer.multiplayer_peer = peer

	_ensure_match_header()
	_initialize_rebels()
	initial_replay_checkpoint = capture_replay_checkpoint()
	if not _recording_path.is_empty():
		replay_recorder.start(self, _recording_path, _snapshot_ticks)
	set_physics_process(true)
	print("Dedicated server started on port %d." % port)
	return true


func configure_recording(path: String, snapshot_ticks: int = 300) -> void:
	_recording_path = path
	_snapshot_ticks = snapshot_ticks


func finish_server() -> Dictionary:
	# Consume queued connection/command callbacks once before the final boundary.
	set_physics_process(false)
	if multiplayer.is_server():
		_run_server_tick(multiplayer.get_peers())
		# Ending a match closes all remaining player sessions, even if ENet has not
		# detected a killed client's timeout yet. Record their departure before close.
		if not _peer_players.is_empty():
			var peers := _peer_players.keys()
			peers.sort()
			for id: int in peers:
				_pending_sessions.append({"type": "leave", "peer_id": id, "reason": "match_end"})
			_run_server_tick(PackedInt32Array())
	var result := replay_recorder.finish()
	multiplayer.multiplayer_peer.close()
	return result


func connect_to_server(
	address: String = "127.0.0.1",
	port: int = DEFAULT_PORT
) -> bool:
	_clear_local_combat_overview()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error(
			"Failed to create client connection to %s:%d. Error: %s"
			% [address, port, error]
		)
		return false

	multiplayer.multiplayer_peer = peer

	print("Connecting to server at %s:%d..." % [address, port])
	return true


func _on_connected_to_server() -> void:
	local_player_id = 0
	local_combat_statistics.clear()
	_clear_local_combat_overview()
	presentation.reset_received.emit()
	print(
		"Connected to server. Local peer ID: %d"
		% multiplayer.get_unique_id()
	)


func _on_connection_failed() -> void:
	local_player_id = 0
	local_combat_statistics.clear()
	_clear_local_combat_overview()
	presentation.reset_received.emit()
	print("Connection to server failed.")


func _on_server_disconnected() -> void:
	local_player_id = 0
	local_combat_statistics.clear()
	_clear_local_combat_overview()
	presentation.reset_received.emit()
	print("Disconnected from server.")


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	if multiplayer.is_server():
		_pending_sessions.append({"type": "join", "peer_id": peer_id})


func _apply_peer_join(peer_id: int) -> void:
	_task_queue_revision = -1
	if _peer_players.has(peer_id):
		return
	var player_id := _next_player_id
	_next_player_id += 1
	_peer_players[peer_id] = player_id
	_dirty_statistics[player_id] = true
	_dirty_combat_overview = true
	_players[player_id] = {"player_id": player_id, "label": "Player %d" % player_id}
	deployment.register_player(player_id, COMBAT_CONFIG.player_team_id, timeline.tick)
	timeline.append("event", "player_join", {"player_id": player_id, "peer_id": peer_id})
	# Keep current peer ownership for control; the match player ID is archival identity.
	if multiplayer.get_peers().has(peer_id):
		for snapshot: Dictionary in live_snapshots():
			_queue_replication("_receive_unit_snapshot", [snapshot], peer_id)
		if _projectiles != null:
			var active_spawns: Array[Dictionary] = []
			active_spawns = _projectiles.active_spawns()
			active_spawns.sort_custom(func(a,b): return a.emission_order < b.emission_order)
			if not active_spawns.is_empty(): _queue_replication("_receive_projectile_events",[active_spawns,[],_projectiles.time_seconds],peer_id)
	for index: int in _movement._config.units_per_peer:
		var unit_id := _next_unit_id
		_next_unit_id += 1
		var spawn: Vector3 = _movement._config.spawn_position(_player_spawn_index)
		if acceptance_full_06: spawn = Vector3(-18.0+index*7.0,0.5,108.0+(player_id-1)*7.0) # TEST ONLY clear lanes, outside existing obstacles.
		_player_spawn_index += 1
		var state := UnitState.new(unit_id, peer_id, spawn)
		state.owner_player_id = player_id
		state.configure(COMBAT_CONFIG.player_team_id, COMBAT_CONFIG.player_definitions[index % COMBAT_CONFIG.player_definitions.size()] if legacy_combat_fixture_enabled else _weapon_presets[index % _weapon_presets.size()])
		var sized_spawn: Variant = _movement.resolve_spawn_position(state.position, state)
		if sized_spawn == null:
			push_error("No valid unit-sized player spawn.")
			continue
		state.position = sized_spawn
		_authoritative_units[unit_id] = state
		state.generated_tick = timeline.tick
		deployment.register_live_unit(unit_id, player_id, state.definition, state.generated_tick)
		_register_combat_unit(state)
		_movement.add_unit(state)
		_combat.add_unit(state)
		if not legacy_combat_fixture_enabled: _aiming.inputs[state.unit_id] = {"moving_spread_multiplier":1.5} # TEST ONLY, never DATA.
		timeline.append("event", "spawn", ReplayFormat.unit_state(state, _movement))
		print("Authoritative unit %d created. Owner peer: %d; match player: %d" % [unit_id, peer_id, player_id])
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_snapshot", [_presentation_snapshot(state)])
		if acceptance_06c: print("TEST ONLY 06C UNIT "+JSON.stringify(_presentation_snapshot(state)))


func _initialize_rebels() -> void:
	if _rebels_initialized:
		return
	_rebels_initialized = true
	var positions: Array[Vector3] = COMBAT_CONFIG.rebel_positions
	if acceptance_06c: positions = [Vector3(-12,0.5,96),Vector3(-3,0.5,96),Vector3(8,0.5,96)]
	for index: int in positions.size():
		var requested: Vector3 = positions[index]
		var state := UnitState.new(_next_unit_id, 0, requested)
		_next_unit_id += 1
		state.configure(COMBAT_CONFIG.rebel_team_id, COMBAT_CONFIG.rebel_definition if legacy_combat_fixture_enabled else _weapon_presets[1])
		if acceptance_06c:
			state.configure(COMBAT_CONFIG.rebel_team_id,load("res://data/units/acceptance_06c_infantry.tres") if index == 0 else _weapon_presets[2])
			if index == 2: state.yaw = PI/2.0
			_acceptance_known_enemies[state.unit_id] = true
		var sized_spawn: Variant = _movement.resolve_spawn_position(state.position, state)
		if sized_spawn == null:
			push_error("No valid unit-sized rebel spawn.")
			continue
		state.position = sized_spawn
		_authoritative_units[state.unit_id] = state
		_register_combat_unit(state,5 if acceptance_06c else null) # TEST ONLY enemy value, never formal DATA.
		_movement.add_unit(state)
		_combat.add_unit(state)
		if not legacy_combat_fixture_enabled: _aiming.inputs[state.unit_id] = {"moving_spread_multiplier":1.5} # TEST ONLY, never DATA.
		if acceptance_06c: print("TEST ONLY 06C UNIT "+JSON.stringify(_presentation_snapshot(state)))


func live_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for state: UnitState in _authoritative_units.values():
		if state.health > 0.0:
			snapshots.append(_presentation_snapshot(state))
	return snapshots


@rpc("authority", "call_remote", "reliable")
func _receive_unit_snapshot(state: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.apply_live_unit(state)

func _presentation_snapshot(state: UnitState) -> Dictionary:
	var result := state.snapshot()
	result.definition_id = state.definition.resource_path
	var count := 0
	for member: SoldierState in state.members:
		if member.health > 0: count += 1
	result.member_count = count
	return result


@rpc("authority", "call_remote", "reliable")
func _receive_combat_shot(shot: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.apply_shot(shot)


@rpc("authority", "call_remote", "reliable")
func _receive_unit_death(unit_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	local_task_queues.erase(unit_id)
	presentation.unit_death_received.emit(unit_id)
	task_queue_received.emit([])


func request_move(unit_id: int, target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_move.rpc_id(1, unit_id, target_position, mode)


func request_moves(unit_ids: Array[int], target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC, facing: Vector3 = Vector3.ZERO, append: bool = false) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_group_move.rpc_id(1, unit_ids, target_position, mode, facing, append)


func request_stops(unit_ids: Array[int]) -> void:
	if unit_ids.is_empty() or multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_stop.rpc_id(1, unit_ids)

func request_ground_fire(unit_ids: Array[int],point: Vector3,artillery: bool = false,count: int = 1,append: bool = false) -> void:
	if unit_ids.is_empty() or multiplayer.is_server(): return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	_submit_ground_fire.rpc_id(1,unit_ids,point,artillery,count,append)

func request_acceptance_auto(unit_ids: Array[int],enabled: bool) -> void:
	if not acceptance_full_06 or unit_ids.is_empty() or multiplayer.is_server(): return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	_submit_acceptance_auto.rpc_id(1,unit_ids,enabled)

func request_acceptance_module_probe(unit_ids: Array[int]) -> void:
	if not acceptance_full_06 or unit_ids.is_empty() or multiplayer.is_server(): return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	_submit_acceptance_module_probe.rpc_id(1,unit_ids)

@rpc("any_peer","call_remote","reliable")
func _submit_acceptance_module_probe(unit_ids: Array[int]) -> void:
	if not acceptance_full_06 or not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender): return
	_queue_command({"type":"acceptance_module_probe","unit_ids":unit_ids.duplicate(),"mode":-1,"group":false},sender)

func _acceptance_probe_command(target: UnitState,sender: int,player: int) -> Dictionary:
	for source: UnitState in _authoritative_units.values():
		if source.owner_peer_id != sender or source.owner_player_id != player or source.health <= 0 or source.definition.resource_path != "res://data/units/acceptance_06c_modules.tres": continue
		if source.runtime_weapons.is_empty(): continue
		var weapon: RuntimeWeaponInstance = source.runtime_weapons[0]
		var origin := DirectBallistics.muzzle(weapon,_aiming.inputs.get(source.unit_id,{}))
		var aim := target.position-Vector3.UP*target.definition.hitbox_half_extents.y*0.5
		var downward := origin.y-aim.y
		if downward <= 0: return {}
		var point := origin+(aim-origin)*(origin.y/downward)
		point.y = 0
		return {"type":"ground_fire","unit_ids":[source.unit_id],"peer_id":sender,"player_id":player,"target":point,"count":1,"mode":-1,"facing":Vector3.ZERO,"group":false}
	return {}

@rpc("any_peer","call_remote","reliable")
func _submit_acceptance_auto(unit_ids: Array[int],enabled: bool) -> void:
	if not acceptance_full_06 or not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender): return
	_queue_command({"type":"acceptance_auto","unit_ids":unit_ids.duplicate(),"enabled":enabled,"mode":-1,"group":false},sender)

func _acceptance_nearest_target(weapon: RuntimeWeaponInstance) -> AttackTarget:
	if not weapon.owning_node_valid(): return null
	var owner := weapon.owner_state()
	if not acceptance_full_06 or not _acceptance_auto_units.has(owner.unit_id) or owner.health <= 0 or weapon.definition.definition_id == "W_M252": return null
	var best: AttackTarget = null
	var best_distance := INF
	var previous := weapon.target
	for id: int in _acceptance_known_enemies:
		if not _authoritative_units.has(id): continue
		var target: UnitState = _authoritative_units[id]
		if target.health <= 0 or target.team_id == owner.team_id: continue
		var candidate := AttackTarget.unit(target)
		weapon.target = candidate
		var sample := {"moving":false} if _movement._attack_moves.has(owner.unit_id) else {}
		var eligible := _aiming.eligibility(weapon,sample) == "eligible"
		var distance := weapon.world_position().distance_squared_to(target.position)
		if eligible and (distance < best_distance or (distance == best_distance and (best == null or id < best.unit_id))): best = candidate; best_distance = distance
	weapon.target = previous
	return best

func _authoritative_target_visible(owner: UnitState,target: AttackTarget) -> bool:
	if target.kind == AttackTarget.Kind.FORCED_GROUND: return true
	if owner == null or not target.valid(_authoritative_units): return false
	if target.state().team_id == owner.team_id: return true
	if acceptance_full_06: return _acceptance_known_enemies.has(target.unit_id)
	return authoritative_visibility_provider.is_valid() and bool(authoritative_visibility_provider.call(owner,target))

func _automatic_target(weapon: RuntimeWeaponInstance,sample: Dictionary = {}) -> AttackTarget:
	# Preserve the explicit fixture toggle and frozen full06 targeting behavior.
	if acceptance_full_06: return _acceptance_nearest_target(weapon)
	if not weapon.owning_node_valid(): return null
	var owner := weapon.owner_state()
	if _authoritative_units.get(owner.unit_id) != owner: return null
	# Existing ammo adapter classification identifies indirect launch weapons.
	for ammo: AmmoDefinition in weapon.definition.ammo_definitions:
		if ammo.distance_selected_launch: return null
	var best: AttackTarget = null
	var best_distance := INF
	for target: UnitState in _authoritative_units.values():
		if target.health <= 0 or target.team_id == owner.team_id: continue
		var candidate := AttackTarget.unit(target)
		if _aiming.candidate_eligibility(weapon,candidate,sample) != "eligible": continue
		var distance := weapon.world_position().distance_squared_to(target.position)
		if distance < best_distance or (distance == best_distance and (best == null or target.unit_id < best.unit_id)):
			best = candidate
			best_distance = distance
	return best

func _update_automatic_engagement() -> void:
	if acceptance_full_06:
		_update_acceptance_engagement()
		return
	for id: int in _movement._attack_moves:
		var engaging := false
		var owner: UnitState = _authoritative_units.get(id)
		if owner != null and owner.health > 0:
			for weapon: RuntimeWeaponInstance in owner.runtime_weapons:
				# Only parking evaluates the future stationary weapon eligibility.
				if weapon.target != null and _aiming.eligibility(weapon,{"moving":false}) == "eligible":
					engaging = true
					continue
				if weapon.target != null and weapon.manual_target: continue
				var candidate := _automatic_target(weapon,{"moving":false})
				if candidate != null:
					weapon.bind_target(candidate,false)
					engaging = true
		if engaging: _movement._engaging[id] = true
		else: _movement._engaging.erase(id)

func _update_acceptance_engagement() -> void:
	if not acceptance_full_06: return
	for id: int in _movement._attack_moves:
		var engaging := false
		for weapon: RuntimeWeaponInstance in _authoritative_units[id].runtime_weapons:
			# Keep a valid existing target; otherwise select and bind the very target
			# used to stop the route. A stale out-of-range target cannot park us forever.
			if weapon.target != null and _aiming.eligibility(weapon,{"moving":false}) == "eligible":
				engaging = true
				continue
			if weapon.target != null and weapon.manual_target: continue
			var candidate := _acceptance_nearest_target(weapon)
			if candidate != null:
				weapon.bind_target(candidate,false)
				engaging = true
		if engaging: _movement._engaging[id] = true
		else: _movement._engaging.erase(id)

@rpc("any_peer", "call_remote", "reliable")
func _submit_ground_fire(unit_ids: Array[int],point: Vector3,artillery: bool,count: int,append: bool = false) -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender): return
	_queue_command({"type":"artillery" if artillery else "ground_fire","unit_ids":unit_ids.duplicate(),"target":point,"count":count,"mode":-1,"facing":Vector3.ZERO,"group":false,"append":append},sender)


@rpc("any_peer", "call_remote", "reliable")
func _submit_stop(unit_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	_queue_command({"type": "stop", "unit_ids": unit_ids.duplicate(), "mode": -1, "target": null, "facing": null}, sender)


func _apply_stop(unit_ids: Array[int], sender: int) -> Dictionary:
	var accepted := _movement.request_stop(unit_ids, sender)
	var positions: Array[Vector3] = []
	for unit_id: int in accepted:
		_task_queue.cancel(unit_id)
		positions.append(_authoritative_units[unit_id].position)
		_artillery.cancel(_authoritative_units[unit_id])
		for instance: RuntimeWeaponInstance in _authoritative_units[unit_id].runtime_weapons: instance.clear_target()
		_movement.attack_facing_requests.erase(unit_id)
		# Remove any older buffered position before broadcasting the current stop position.
		_pending_positions.erase(unit_id)
	for command: Dictionary in _pending_commands:
		if command.peer_id != sender: continue
		command.unit_ids = command.unit_ids.filter(func(id): return not accepted.has(id))
	_pending_commands = _pending_commands.filter(func(command): return not command.unit_ids.is_empty())
	return {"unit_ids": accepted, "positions": positions}


@rpc("authority", "call_remote", "reliable")
func _receive_unit_stops(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_stops_received.emit(unit_ids, positions)


@rpc("any_peer", "call_remote", "reliable")
func _submit_group_move(unit_ids: Array[int], target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC, facing: Vector3 = Vector3.ZERO, append: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	_queue_command({"type": "move", "unit_ids": unit_ids.duplicate(), "mode": mode, "target": target_position, "facing": facing, "group": true,"append":append}, sender)


@rpc("any_peer", "call_remote", "reliable")
func _submit_move(unit_id: int, target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var ids: Array[int] = [unit_id]
	_queue_command({"type": "move", "unit_ids": ids, "mode": mode, "target": target_position, "facing": Vector3.ZERO, "group": false}, sender)


@rpc("authority", "call_remote", "reliable")
func _receive_move_targets(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_move_targets_received.emit(unit_ids, positions)


@rpc("authority", "call_remote", "reliable")
func _receive_move_paths(unit_ids: Array[int], paths: Array[PackedVector3Array]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != paths.size():
		return
	presentation.unit_move_paths_received.emit(unit_ids, paths)

@rpc("authority", "call_remote", "reliable")
func _receive_move_modes(unit_ids: Array[int], modes: Array[int]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if unit_ids.size() != modes.size(): return
	if modes.any(func(mode): return mode not in [MovementSimulation.MoveMode.BASIC,MovementSimulation.MoveMode.FAST,MovementSimulation.MoveMode.ATTACK,MovementSimulation.MoveMode.REVERSE]): return
	presentation.unit_move_modes_received.emit(unit_ids,modes)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if legacy_combat_fixture_enabled:
		_run_server_tick(multiplayer.get_peers())
	else:
		_server_clock.advance(delta,func() -> bool:
			var before := timeline.tick
			_run_server_tick(multiplayer.get_peers())
			return timeline.tick == before+1 and not _combat_timeline.halted)


func _run_server_tick(connected_peers: PackedInt32Array) -> void:
	# One authoritative fixed step. Network callback arrival never mutates simulation.
	if not legacy_combat_fixture_enabled and _combat_timeline.halted: return
	if not _ensure_deployment_ready():
		return
	timeline.begin_tick()
	deployment.begin_tick(timeline.tick)
	_consume_sessions(connected_peers)
	deployment.advance_to_tick(timeline.tick)
	_consume_deployment_requests(connected_peers)
	deployment.execute_deployments(_authoritative_units, _spawn_deployment)
	# Frozen v1 spawn events belong to session. Deployment requests are a
	# separate economic stream, adjudicated here before any spawn or movement.
	timeline.enter_phase("commands")
	_consume_commands(connected_peers)
	_advance_task_queues(connected_peers)
	timeline.enter_phase("movement")
	var delta := timeline.seconds_per_tick()
	for id: int in _movement.active_command_ids():
		_dirty_units[id] = true
	_aiming.units = _authoritative_units
	_aiming.visibility = _authoritative_target_visible
	_aiming.automatic_target_provider = _automatic_target
	_aiming.clear_path = _combat.has_line_of_sight
	_aiming.moving = _movement.is_moving
	if not legacy_combat_fixture_enabled: _update_automatic_engagement()
	var changed: Dictionary = {}
	var fixed_result := {"emissions":[],"events":[]}
	if legacy_combat_fixture_enabled:
		_movement.attack_facing_requests = _aiming.hull_requests()
		_movement.update_attack_engagement(_combat)
		changed = _movement.advance(delta)
	else:
		if _projectiles == null:
			_ensure_match_header()
			if not _combat_timeline.configure_settlement_context({"match_id":_match_header.match_id,
				"map_id":_movement._config.resource_path,"map_sha256":FileAccess.get_sha256(_movement._config.resource_path),
				"rules_id":ConfirmedDataValidator.RULES_ID,"data_version":ConfirmedDataValidator.DATA_VERSION,
				"data_sha256":FileAccess.get_sha256(ConfirmedGameData.PATH)}):
				push_error("Settlement context rejected: "+_combat_timeline.settlement_inbox.failure_reason)
				return
			_projectiles = _combat_timeline.projectiles
			_projectiles.configure_bounds(Rect2(_movement._config.minimum_xz,_movement._config.maximum_xz-_movement._config.minimum_xz))
			_projectiles.collision.initialize_map(MovementSimulation.MAP_DEFINITION,_movement._config)
			_combat_timeline.fire = _fire
			_combat_timeline.direct_hit_enabled = true
			_combat_timeline.overpenetration_enabled = true
			_combat_timeline.suppression_enabled = true
			_combat_timeline.modules_enabled = true
			_combat_timeline.direct_hits.damage_committed = _record_combat_damage
			_fire.fire_path_permission = func(_weapon,_origin,_point,_inputs): return true # Static eligibility and sampled friendly check own permission.
		fixed_result = _combat_timeline.step_movement(_movement,_aiming)
		changed = fixed_result.changed
		# Health snapshots are authoritative live results, not acceptance logging.
		var affected := {}
		for outcome: Dictionary in fixed_result.get("damage_results",[]): affected[outcome.unit_id] = true
		for id: int in affected: _queue_replication("_receive_unit_snapshot",[_presentation_snapshot(_authoritative_units[id])])
		if acceptance_06c:
			for envelope: Dictionary in fixed_result.get("settlements",[]):
				var input: Dictionary = envelope.input
				print("TEST ONLY 06C IMPACT "+JSON.stringify({"emission_order":input.emission_order,"kind":input.kind,"point":input.point,"time_seconds":input.time_seconds}))
				if acceptance_full_06 and input.reason == "impact" and float(input.ammo_values.get("explosion_radius_m",0)) > 0:
					_queue_replication("_receive_acceptance_explosion",[{"position":DirectHitSettlement.vector(input.point),"radius":float(input.ammo_values.explosion_radius_m)}])
			for outcome: Dictionary in fixed_result.get("damage_results",[]):
				print("TEST ONLY 06C DAMAGE "+JSON.stringify(outcome)) # Server console only, never RPC/replay.
			for input: Dictionary in fixed_result.get("suppression_inputs",[]): print("TEST ONLY 06C SUPPRESSION INPUT "+JSON.stringify(input))
			if acceptance_full_06:
				for row: Dictionary in fixed_result.get("suppression_results",[]): print("TEST ONLY 06D RESULT "+JSON.stringify(row))
				for row: Dictionary in fixed_result.get("module_results",[]): print("TEST ONLY 06E RESULT "+JSON.stringify(row))
	_pending_positions.merge(changed, true)
	for id: int in changed:
		_dirty_units[id] = true
	# A target entered range during this tick: park before applying firing eligibility.
	if legacy_combat_fixture_enabled: _movement.update_attack_engagement(_combat)
	timeline.enter_phase("combat")
	if legacy_combat_fixture_enabled: _aiming.advance(delta)
	else:
		var spawns: Array[Dictionary] = []
		var terminals: Array[Dictionary] = []
		for event: Dictionary in fixed_result.events:
			if event.reason == "spawn": spawns.append(event)
			else: terminals.append(event)
		for event: Dictionary in spawns: projectile_spawn_received.emit(event.duplicate(true))
		for event: Dictionary in terminals: projectile_terminal_received.emit(event.duplicate(true))
		if not connected_peers.is_empty() and (not spawns.is_empty() or not terminals.is_empty() or not _projectiles.active_slots.is_empty()):
			# Reuse the existing public shape for discrete current motion samples.
			var snapshots: Array[Dictionary] = spawns.duplicate()
			for active: Dictionary in _projectiles.active_spawns(false): snapshots.append(active)
			_queue_replication("_receive_projectile_events",[snapshots,terminals,_projectiles.time_seconds])
		var emissions: Array[Dictionary] = []
		for event: Dictionary in fixed_result.emissions:
			# Cache references stay server-only; explicit value event for presentation.
			var row := event.duplicate()
			row.erase("ammo")
			row.ammo_definition_id = event.ammo.ammo_id
			row.emission_sequence = int(str(event.event_id).get_slice(":",str(event.event_id).get_slice_count(":")-1))
			row.slot_id = ""
			emissions.append(row)
			weapon_fire_received.emit(row.duplicate(true))
		_artillery.after_emissions(fixed_result.emissions,_authoritative_units)
		if not emissions.is_empty() and not connected_peers.is_empty(): _queue_replication("_receive_weapon_fires",[emissions])
		_finish_active_deaths(fixed_result)
		for id: int in changed.keys():
			if not _authoritative_units.has(id): changed.erase(id)
		for id: int in _pending_positions.keys():
			if not _authoritative_units.has(id): _pending_positions.erase(id)
	# New emissions never enter legacy 'shot' (absolute HP result) or frozen v1.
	var combat_result: Dictionary = _combat.advance(delta, _movement) if legacy_combat_fixture_enabled else {"shots":[],"deaths":[]}
	for shot: Dictionary in combat_result["shots"]:
		_dirty_units[shot.target_id] = true
		var recorded_shot := shot.duplicate(true)
		recorded_shot.start = [shot.start.x, shot.start.y, shot.start.z]
		recorded_shot.end = [shot.end.x, shot.end.y, shot.end.z]
		timeline.append("event", "shot", recorded_shot)
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_combat_shot", [shot])
	for id: int in combat_result["deaths"]:
		deployment.remove_live_unit(id)
		_retired_unit_ids.append(id)
		timeline.append("event", "death", {"unit_id": id})
		_authoritative_units.erase(id)
		_pending_positions.erase(id)
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_death", [id])
	timeline.enter_phase("record")
	var dirty_ids := _dirty_units.keys()
	dirty_ids.sort()
	for id: int in dirty_ids:
		if _authoritative_units.has(id):
			timeline.append("event", "unit_state", ReplayFormat.unit_state(_authoritative_units[id], _movement))
	_dirty_units.clear()
	# Future recorder consumes completed state/events here; no whole-match buffer in A.
	tick_completed.emit(timeline.tick, timeline.records.duplicate(true))
	timeline.enter_phase("replication")
	if timeline.tick % maxi(1, timeline.tick_hz / INTERNAL_STATE_REPLICATION_HZ) == 0:
		if not connected_peers.is_empty():
			var structures: Array[Dictionary] = []
			for state: UnitState in _authoritative_units.values():
				var structure := state.structure_snapshot()
				if not legacy_combat_fixture_enabled: structure.marker_status = UnitMarkerStatus.build(state,_aiming,_marker_activity.get(state.unit_id,{}))
				structures.append(structure)
			_queue_replication("_receive_unit_structures", [structures])
			_queue_replication("_receive_unit_statuses", [structures])
		for peer_id: int in _peer_players:
			var player_id := _peer_players[peer_id]
			if _dirty_deployment.has(player_id):
				_queue_replication("_receive_deployment_state", [deployment.export_player(player_id)], peer_id)
			if not legacy_combat_fixture_enabled and _dirty_statistics.has(player_id):
				_queue_replication("_receive_combat_statistics", [combat_outcomes.project_player(player_id)], peer_id)
		if not legacy_combat_fixture_enabled and _dirty_combat_overview:
			for peer_id: int in _peer_players:
				_queue_replication("_receive_combat_overview", [_build_combat_overview(_peer_players[peer_id])], peer_id)
			_dirty_combat_overview = false
		_dirty_deployment.clear()
		_dirty_statistics.clear()
	_replication_elapsed += delta
	if _replication_elapsed >= _movement._config.replication_interval or not _movement.has_active_moves():
		if not _pending_positions.is_empty() and not multiplayer.get_peers().is_empty():
			var unit_ids: Array[int] = []
			var positions: Array[Vector3] = []
			for unit_id: int in _pending_positions:
				unit_ids.append(unit_id)
				positions.append(_pending_positions[unit_id])
			# Reliable ordered delivery also preserves spawn-before-position ordering.
			_queue_replication("_receive_unit_positions", [unit_ids, positions])
			_queue_replication("_receive_unit_orientations", [unit_ids, _unit_yaws(unit_ids)])
		_pending_positions.clear()
		_replication_elapsed = 0.0
	_flush_replication()
	timeline.finish_tick()


@rpc("authority", "call_remote", "reliable")
func _receive_unit_structures(states: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for state: Dictionary in states: presentation.apply_live_structure(state)

@rpc("authority", "call_remote", "reliable")
func _receive_weapon_fires(events: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for event: Dictionary in events: presentation.apply_fire_event(event)

@rpc("authority", "call_remote", "reliable")
func _receive_projectile_events(spawns: Array, terminals: Array, authority_time: float = -1.0) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if not is_finite(authority_time) or authority_time < 0: return
	presentation.synchronize_projectile_time(authority_time)
	for event: Dictionary in spawns: presentation.apply_projectile_spawn(event)
	for event: Dictionary in terminals: presentation.apply_projectile_terminal(event)


@rpc("authority", "call_remote", "reliable")
func _receive_unit_positions(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_positions_received.emit(unit_ids, positions)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	if multiplayer.is_server():
		_pending_sessions.append({"type": "leave", "peer_id": peer_id})


func _unit_yaws(unit_ids: Array[int]) -> Array[float]:
	var yaws: Array[float] = []
	for id: int in unit_ids:
		yaws.append(_authoritative_units[id].yaw)
	return yaws


@rpc("authority", "call_remote", "reliable")
func _receive_unit_orientations(unit_ids: Array[int], yaws: Array[float]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != yaws.size():
		return
	for yaw: float in yaws:
		if not is_finite(yaw):
			return
	presentation.unit_orientations_received.emit(unit_ids, yaws)


func _queue_command(command: Dictionary, sender: int) -> void:
	if not _peer_players.has(sender):
		return
	command.peer_id = sender
	command.player_id = _peer_players[sender]
	_pending_commands.append(command)


func _consume_sessions(connected_peers: PackedInt32Array) -> void:
	var sessions := _pending_sessions
	_pending_sessions = []
	for session: Dictionary in sessions:
		var peer_id: int = session.peer_id
		if session.type == "join":
			if connected_peers.has(peer_id):
				_apply_peer_join(peer_id)
		elif _peer_players.has(peer_id):
			var player_id := _peer_players[peer_id]
			_peer_players.erase(peer_id)
			_dirty_combat_overview = true
			deployment.cancel_player_orders(player_id)
			_movement.stop_owner(peer_id)
			for unit: UnitState in _authoritative_units.values():
				if unit.owner_player_id == player_id:
					_task_queue.cancel(unit.unit_id)
					_dirty_units[unit.unit_id] = true
			timeline.append("event", "player_leave", {"player_id": player_id, "peer_id": peer_id,
				"reason": session.get("reason", "transport_disconnect")})


func _consume_commands(connected_peers: PackedInt32Array) -> void:
	var commands := _pending_commands
	_pending_commands = []
	for command: Dictionary in commands:
		var result := {"unit_ids": [], "failed_ids": [], "rejection": "sender disconnected or player changed"}
		if connected_peers.has(command.peer_id) and _peer_players.get(command.peer_id, 0) == command.player_id:
			result = _submit_task_command(command)
			var notice := _command_notice(command, result)
			if not notice.is_empty(): _queue_replication("_receive_command_notice", [notice], command.peer_id)
		var requested_ids: Array = []
		for id: int in command.unit_ids:
			requested_ids.append(ReplayFormat.request_integer(id))
		var payload := {"player_id": command.player_id, "peer_id": command.peer_id,
			"unit_ids": requested_ids, "mode": ReplayFormat.request_integer(command.mode), "target": null, "facing": null,
			"accepted_ids": result.unit_ids, "failed_ids": result.failed_ids, "rejection": result.rejection}
		if command.type == "move":
			var target: Vector3 = command.target
			var facing: Vector3 = command.facing
			payload.target = [target.x, target.y, target.z] if target.is_finite() else null
			payload.facing = [facing.x, facing.y, facing.z] if facing.is_finite() else null
			payload.group = command.group
		# New fire requests are outside frozen input metadata; v1 records state.
		if command.type in ["move","stop"]: timeline.append("command", command.type, payload)


func _command_notice(command: Dictionary, result: Dictionary) -> Dictionary:
	if _peer_players.get(int(command.get("peer_id", 0)), 0) != int(command.get("player_id", -1)): return {}
	if command.get("type") not in ["move", "stop", "ground_fire", "artillery"]: return {}
	var reason := str(result.get("rejection", ""))
	if reason.is_empty() and result.get("failed_ids", []).is_empty(): return {}
	var ids: Array[int] = []
	for id: int in command.get("unit_ids", []):
		if _authoritative_units.has(id) and _authoritative_units[id].owner_player_id == command.player_id and not ids.has(id): ids.append(id)
	return {"command":command.type, "reason":reason if not reason.is_empty() else "部分单位无法执行", "unit_ids":ids, "_recipient_player_id":command.player_id}

@rpc("authority", "call_remote", "reliable")
func _receive_command_notice(notice: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if notice.get("command") not in ["move", "stop", "ground_fire", "artillery"] or not notice.get("reason") is String or not notice.get("unit_ids") is Array: return
	command_notice_received.emit({"command":notice.command, "reason":notice.reason, "unit_ids":notice.unit_ids.duplicate()})

func _task_eligible(command: Dictionary, unit: UnitState) -> bool:
	if unit.health <= 0 or unit.owner_player_id != command.player_id or unit.owner_peer_id != command.peer_id: return false
	if command.type == "move":
		return command.mode in [0,1,2,3] and _movement._valid_speeds(unit) and (command.mode != MovementSimulation.MoveMode.ATTACK or unit.is_armed()) and (command.mode != MovementSimulation.MoveMode.REVERSE or _movement._can_reverse(unit))
	if command.type == "artillery":
		return unit.runtime_weapons.any(func(w): return w.definition.definition_id == "W_M252")
	return unit.runtime_weapons.any(func(w): return w.definition.definition_id != "W_M252")

func _submit_task_command(command: Dictionary) -> Dictionary:
	if command.type not in ["move","ground_fire","artillery"]: return _execute_command(command)
	var result := {"unit_ids":[],"failed_ids":[],"rejection":""}
	if not command.target is Vector3 or not _movement._validate_target(command.target).is_empty():
		result.rejection = "invalid task destination"
		return result
	if command.type == "move" and (not command.facing is Vector3 or not command.facing.is_finite() or not is_zero_approx(command.facing.y)):
		result.rejection = "invalid facing"
		return result
	if command.type != "move" and int(command.count) not in [1,3,-1]:
		result.rejection = "invalid fire count"
		return result
	var eligible: Array[int] = []
	for id: int in command.unit_ids:
		if eligible.has(id): continue
		if _authoritative_units.has(id) and _task_eligible(command,_authoritative_units[id]):
			if command.type == "artillery":
				_aiming.units = _authoritative_units
				var error := _artillery.submit(_authoritative_units[id],command.target,int(command.count),_aiming,_movement,true)
				if not error.is_empty() and error != "ammunition_insufficient":
					result.failed_ids.append(id)
					result.rejection = error
					continue
			eligible.append(id)
		elif _authoritative_units.has(id) and _authoritative_units[id].owner_player_id == command.player_id and _authoritative_units[id].owner_peer_id == command.peer_id:
			result.failed_ids.append(id)
	var append := bool(command.get("append",false))
	# Plan all formation slots without changing current movement or fire state.
	var destinations := {}
	var formation_facing: Vector3 = command.facing
	if command.type == "move" and command.group:
		var plan := _movement.request_group_move(eligible,command.peer_id,command.target,command.mode,command.facing,true)
		if not plan.rejection.is_empty():
			result.rejection = plan.rejection
			result.failed_ids.append_array(eligible)
			return result
		destinations = plan.destinations
		formation_facing = Vector3(-sin(plan.final_yaw),0,-cos(plan.final_yaw))
		for id: int in plan.failed_ids: result.failed_ids.append(id)
		eligible.assign(plan.unit_ids)
	for id: int in eligible:
		var task := command.duplicate(true)
		task.unit_ids = [id]
		task.group = false
		task["started"] = false
		if destinations.has(id):
			task.target = Vector3(destinations[id].x,_movement._config.ground_height,destinations[id].z)
		if command.type == "move": task.facing = formation_facing
		if append and _task_queue.current(id).is_empty() and _movement._targets.has(id):
			var existing := task.duplicate(true)
			existing.target = Vector3(_movement._targets[id].x,_movement._config.ground_height,_movement._targets[id].z)
			existing.mode = _movement._move_modes[id]
			existing.started = true
			_task_queue.submit(id,existing,false)
		if task.type == "move":
			var start: Vector3 = _authoritative_units[id].position
			if append and _task_queue.tasks.has(id): start = _task_queue.tasks[id].back().target
			start.y = _authoritative_units[id].position.y
			var destination: Vector3 = task.target
			destination.y = start.y
			task["path"] = _movement.navigation_for(_authoritative_units[id]).find_path(start,destination,[],0.0,task.mode == MovementSimulation.MoveMode.FAST,_authoritative_units[id])
		if not append:
			# Eligibility is checked first: unsupported mixed-selection units keep tasks.
			_movement.request_stop([id],command.peer_id)
			_artillery.cancel(_authoritative_units[id])
			for weapon: RuntimeWeaponInstance in _authoritative_units[id].runtime_weapons: weapon.clear_target()
			var stopped_ids: Array[int] = [id]
			var stopped_positions: Array[Vector3] = [_authoritative_units[id].position]
			_queue_replication("_receive_unit_stops",[stopped_ids,stopped_positions])
		_task_queue.submit(id,task,append)
		_dirty_units[id] = true
		result.unit_ids.append(id)
	if eligible.is_empty() and result.rejection.is_empty(): result.rejection = "no owned eligible units"
	return result

func _advance_task_queues(connected_peers: PackedInt32Array) -> void:
	for id: int in _task_queue.tasks.keys():
		var task := _task_queue.current(id)
		var unit: UnitState = _authoritative_units.get(id)
		if unit == null or unit.health <= 0 or not connected_peers.has(task.peer_id) or _peer_players.get(task.peer_id,0) != task.player_id or unit.owner_player_id != task.player_id:
			_task_queue.cancel(id)
			continue
		if task.started:
			var complete := false
			if task.type == "move": complete = not _movement._targets.has(id) # Engaging / blocked is not arrival.
			elif task.type == "artillery": complete = not unit.runtime_weapons.any(func(w): return _artillery.tasks.has(w.instance_id))
			elif int(task.count) != -1: complete = not unit.runtime_weapons.any(func(w): return w.manual_target and w.forced_emissions_remaining != 0)
			if not complete: continue
			_task_queue.finish(id)
			task = _task_queue.current(id)
			if task.is_empty(): continue
		var result := _execute_command(task)
		if result.unit_ids.has(id): task.started = true
		elif result.rejection in ["ammunition_insufficient","no reachable destination","no reachable destinations"]:
			continue # Transient ammunition / occupancy shortages retain the head.
		else:
			var notice := _command_notice(task,result)
			if not notice.is_empty(): _queue_replication("_receive_command_notice",[notice],task.peer_id)
			_task_queue.finish(id)
	if _task_queue_revision != _task_queue.revision:
		_task_queue_revision = _task_queue.revision
		for peer: int in connected_peers:
			if not _peer_players.has(peer): continue
			var rows: Array[Dictionary] = []
			for unit: UnitState in _authoritative_units.values():
				if unit.owner_player_id == _peer_players[peer]: rows.append({"unit_id":unit.unit_id,"tasks":_task_queue.projection(unit.unit_id)})
			_replication_queue.append({"method":"_receive_task_queues","arguments":[rows],"peer_id":peer,"notice_player_id":_peer_players[peer]})

@rpc("authority", "call_remote", "reliable")
func _receive_task_queues(rows: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	local_task_queues.clear()
	for row: Dictionary in rows: local_task_queues[row.unit_id] = row.tasks.duplicate(true)
	task_queue_received.emit(rows)

func _execute_command(command: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	for id: int in command.unit_ids:
		# A reused ENet peer ID must not grant its new player the old player's units.
		if _authoritative_units.has(id) and _authoritative_units[id].owner_player_id != command.player_id:
			continue
		ids.append(id)
	var sender: int = command.peer_id
	var result := {"unit_ids": [], "failed_ids": [], "rejection": ""}
	if command.type == "acceptance_module_probe":
		if acceptance_full_06 and ids.size() == 1:
			var target: UnitState = _authoritative_units.get(ids[0])
			if target != null and target.owner_peer_id == sender and target.health > 0 and target.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE:
				var probe := _acceptance_probe_command(target,sender,int(command.player_id))
				if not probe.is_empty(): return _execute_command(probe)
		result.rejection = "select one owned living vehicle and keep module shooter alive"
	elif command.type == "acceptance_auto":
		if acceptance_full_06:
			for id: int in ids:
				if not _authoritative_units.has(id): continue
				var unit: UnitState = _authoritative_units[id]
				if unit.owner_peer_id != sender or unit.health <= 0 or not unit.is_armed(): continue
				if command.enabled: _acceptance_auto_units[id] = true
				else:
					_acceptance_auto_units.erase(id)
					for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
						if not weapon.manual_target: weapon.clear_target()
				result.unit_ids.append(id)
	elif command.type == "stop":
		var stopped := _apply_stop(ids, sender)
		result.unit_ids = stopped.unit_ids
		if result.unit_ids.is_empty():
			result.rejection = "no owned living units"
		elif not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_stops", [stopped.unit_ids, stopped.positions])
			_queue_replication("_receive_unit_orientations", [stopped.unit_ids, _unit_yaws(stopped.unit_ids)])
	elif command.type in ["ground_fire","artillery"]:
		if not command.target is Vector3 or not command.target.is_finite():
			result.rejection = "invalid fire position"
		elif not _movement._validate_target(command.target).is_empty():
			result.rejection = _movement._validate_target(command.target)
		else:
			for id: int in ids:
				if not _authoritative_units.has(id): continue
				var unit: UnitState = _authoritative_units[id]
				if unit.owner_peer_id != sender or unit.health <= 0: continue
				var reason := ""
				if command.type == "artillery": reason = _artillery.submit(unit,command.target,int(command.count),_aiming,_movement)
				elif not unit.runtime_weapons.any(func(weapon): return weapon.definition.definition_id != "W_M252"): reason = "artillery_requires_t"
				else:
					_artillery.cancel(unit)
					_movement.request_stop([id],sender)
					for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
						if weapon.definition.definition_id != "W_M252":
							if int(command.get("count",1)) == -1: weapon.bind_target(AttackTarget.ground(command.target),true)
							else: weapon.bind_single_ground_target(command.target)
				if reason.is_empty():
					result.unit_ids.append(id)
					_pending_positions.erase(id)
					# Clear the former route, then publish any new artillery approach.
					var stopped_ids: Array[int] = [id]
					var stopped_positions: Array[Vector3] = [unit.position]
					_queue_replication("_receive_unit_stops", [stopped_ids, stopped_positions])
					if _movement.is_moving(id):
						_queue_replication("_receive_move_targets", [stopped_ids, _movement.move_targets(stopped_ids)], sender)
						_queue_replication("_receive_move_paths", [stopped_ids, _movement.move_paths(stopped_ids)], sender)
				else: result.failed_ids.append(id); result.rejection = reason
	elif command.group:
		result = _movement.request_group_move(ids, sender, command.target, command.mode, command.facing)
		if not result.has("failed_ids"):
			result.failed_ids = []
	elif ids.is_empty():
		result.rejection = "no owned units"
	else:
		result.rejection = _movement.request_move(ids[0], sender, command.target, command.mode)
		if result.rejection.is_empty():
			result.unit_ids = ids
	for id: int in result.unit_ids:
		if command.type == "move":
			_artillery.cancel(_authoritative_units[id])
			if acceptance_full_06 and command.mode == MovementSimulation.MoveMode.ATTACK: _acceptance_auto_units[id] = true
			for weapon: RuntimeWeaponInstance in _authoritative_units[id].runtime_weapons:
				if weapon.forced_emissions_remaining >= 0: weapon.clear_target()
		_dirty_units[id] = true
	if not result.unit_ids.is_empty():
		print("%s accepted: peer %d, units %s" % [command.type.capitalize(), sender, result.unit_ids])
		if command.type == "move" and multiplayer.get_peers().has(sender):
			var accepted: Array[int] = []
			accepted.assign(result.unit_ids)
			_queue_replication("_receive_move_targets", [accepted, _movement.move_targets(accepted)], sender)
			_queue_replication("_receive_move_paths", [accepted, _movement.move_paths(accepted)], sender)
			var modes: Array[int] = []
			for id: int in accepted: modes.append(_movement._move_modes[id])
			_queue_replication("_receive_move_modes", [accepted, modes], sender)
			print("Move mode=%d group=%s accepted=%s" % [command.mode,command.group,accepted])
	else:
		if result.rejection.is_empty(): result.rejection = "no owned eligible units"
		print("%s rejected: peer %d: %s" % [command.type.capitalize(), sender, result.rejection])
	return result


func _ensure_match_header() -> void:
	if not _match_header.is_empty():
		return
	var crypto := Crypto.new()
	_match_header = ReplayFormat.header(crypto.generate_random_bytes(16).hex_encode(), timeline.tick_hz,
		ReplayContent.MAP_ID, ReplayContent.RULES_ID, crypto.generate_random_bytes(8).hex_encode(), [], ReplayContent.fingerprints())

func _register_combat_unit(unit: UnitState, value_points: Variant = null) -> bool:
	if value_points == null: value_points = deployment.value_for_definition(unit.definition)
	return combat_outcomes.register_unit(unit,value_points)

func _record_combat_damage(result: Dictionary) -> bool:
	for id: int in [int(result.unit_id),int(result.source_unit_id)]:
		if not combat_outcomes.identities.has(id) and _authoritative_units.has(id): _register_combat_unit(_authoritative_units[id])
	var was_dead: bool = combat_outcomes.deaths.has(result.unit_id)
	if not combat_outcomes.commit_damage(result): return false
	if not was_dead and combat_outcomes.deaths.has(result.unit_id):
		var death: Dictionary = combat_outcomes.deaths[result.unit_id]
		_dirty_statistics[death.player_id] = true
		if not death.friendly_fire: _dirty_statistics[death.killer_player_id] = true
		_dirty_combat_overview = true
	return true

func _finish_active_deaths(result: Dictionary) -> void:
	for outcome: Dictionary in result.get("damage_results",[]):
		if outcome.unit_died and combat_outcomes.deaths.has(outcome.unit_id): _retire_active_unit(outcome.unit_id)

func _retire_active_unit(id: int) -> bool:
	if not _authoritative_units.has(id) or _authoritative_units[id].health > 0: return false
	var unit: UnitState = _authoritative_units[id]
	# Resolve visibility before removal, recheck recipient identity at delivery.
	_queue_replication("_receive_unit_death",[id])
	deployment.remove_live_unit(id)
	_task_queue.cancel(id)
	_artillery.cancel(unit)
	_movement.remove_unit(id)
	_movement.attack_facing_requests.erase(id)
	_movement._sampled_commands.erase(id)
	_combat.remove_unit(id)
	_aiming.inputs.erase(id)
	_aiming.target_velocities.erase(id)
	_marker_activity.erase(id)
	_acceptance_auto_units.erase(id)
	_acceptance_known_enemies.erase(id)
	_previous_ballistic_positions.erase(id)
	_pending_positions.erase(id)
	_dirty_units.erase(id)
	if _combat_timeline.suppression_runtime != null:
		var runtime := _combat_timeline.suppression_runtime
		runtime.settlement.states.erase(id)
		runtime.base_inputs.erase(id)
		runtime.active.erase(id)
		runtime.revisions.erase(id)
		runtime.heap = runtime.heap.filter(func(row): return row.unit_id != id)
	if _combat_timeline.module_runtime != null:
		_combat_timeline.module_runtime.states.erase(id)
		_combat_timeline.module_runtime.base_inputs.erase(id)
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons: weapon.clear_target()
	if unit.squad_channels != null: unit.squad_channels.detach()
	for other: UnitState in _authoritative_units.values():
		for weapon: RuntimeWeaponInstance in other.runtime_weapons:
			if weapon.target != null and weapon.target.kind == AttackTarget.Kind.UNIT and weapon.target.unit_id == id: weapon.clear_target()
	for command: Dictionary in _pending_commands:
		command.unit_ids = command.unit_ids.filter(func(value): return value != id)
	_pending_commands = _pending_commands.filter(func(command): return not command.unit_ids.is_empty())
	_authoritative_units.erase(id)
	_retired_unit_ids.append(id)
	# Match identities and legal in-flight projectile slots survive retirement.
	return true

func set_authoritative_marker_activity(id: int, activity: Dictionary) -> bool:
	# Local authority service API; no corresponding client RPC or ability command.
	if not _authoritative_units.has(id) or _authoritative_units[id].health <= 0 or not UnitMarkerStatus.valid_activity(activity): return false
	_marker_activity[id] = activity.duplicate(true)
	return true

@rpc("authority","call_remote","reliable")
func _receive_combat_statistics(statistics: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1 or statistics.get("player_id",0) != local_player_id: return
	local_combat_statistics = statistics.duplicate(true)
	combat_statistics_received.emit(local_combat_statistics.duplicate(true))


func _build_combat_overview(viewer_player_id: int) -> Dictionary:
	var players: Array[Dictionary] = []
	var player_ids := _players.keys()
	player_ids.sort()
	for player_id: int in player_ids:
		var row := combat_outcomes.project_player(player_id)
		row["label"] = String(_players[player_id].get("label", "Player %d" % player_id))
		row["connected"] = _peer_players.values().has(player_id)
		players.append(row)
	return {"viewer_player_id":viewer_player_id,"players":players,
		"records":combat_outcomes.project_records(viewer_player_id)}


func _clear_local_combat_overview() -> void:
	local_combat_overview = {}
	combat_overview_received.emit({})


@rpc("authority","call_remote","reliable")
func _receive_combat_overview(overview: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if int(overview.get("viewer_player_id",0)) != local_player_id: return
	local_combat_overview = overview.duplicate(true)
	combat_overview_received.emit(local_combat_overview.duplicate(true))


func replay_header() -> Dictionary:
	_ensure_match_header()
	var result := _match_header.duplicate(true)
	var ids := _players.keys()
	ids.sort()
	for id: int in ids:
		result.players.append(_players[id].duplicate(true))
	return result


func capture_replay_checkpoint() -> Dictionary:
	assert(timeline.phase in ["idle", "record"])
	var units: Array[Dictionary] = []
	var ids := _authoritative_units.keys()
	ids.sort()
	for id: int in ids:
		if _authoritative_units[id].health > 0:
			units.append(ReplayFormat.unit_state(_authoritative_units[id], _movement))
	var retired := _retired_unit_ids.duplicate()
	retired.sort()
	var connected := _peer_players.values()
	connected.sort()
	return {"through": timeline.cursor(), "units": units, "retired_unit_ids": retired,
		"next_unit_id": _next_unit_id, "connected_player_ids": connected}


func _queue_replication(method: String, arguments: Array, peer_id: int = -1) -> void:
	if method == "_receive_task_queues": return # Dedicated owner-only projection path; never generic broadcast.
	if method == "_receive_combat_overview":
		if peer_id <= 0 or not _peer_players.has(peer_id): return
		var recipient_player_id: int = _peer_players[peer_id]
		_replication_queue.append({"method":method,"arguments":[_build_combat_overview(recipient_player_id)],
			"peer_id":peer_id,"recipient_player_id":recipient_player_id})
		return
	if method == "_receive_combat_statistics":
		if peer_id <= 0 or arguments.size() != 1 or not arguments[0] is Dictionary or arguments[0].get("player_id",0) != _peer_players.get(peer_id,-1): return
		_replication_queue.append({"method":method,"arguments":[combat_outcomes.project_player(_peer_players[peer_id])],"peer_id":peer_id,"recipient_player_id":_peer_players[peer_id]})
		return
	if method == "_receive_command_notice":
		# Private UI result: prohibit broadcast and recheck identity at delivery.
		if peer_id <= 0 or arguments.size() != 1 or not arguments[0] is Dictionary: return
		var notice: Dictionary = arguments[0]
		if int(notice.get("_recipient_player_id", 0)) <= 0 or int(notice.get("_recipient_player_id", 0)) != _peer_players.get(peer_id, 0): return
		var public_notice := {"command":notice.command, "reason":notice.reason, "unit_ids":notice.unit_ids.duplicate()}
		_replication_queue.append({"method":method, "arguments":[public_notice], "peer_id":peer_id, "notice_player_id":notice._recipient_player_id})
		return
	if legacy_combat_fixture_enabled and method != "_receive_projectile_events":
		_replication_queue.append({"method": method, "arguments": arguments.duplicate(true), "peer_id": peer_id})
		return
	var recipients: Array = _peer_players.keys() if peer_id == -1 else [peer_id]
	for recipient: int in recipients:
		var permitted := _replication_arguments_for_peer(method,arguments,recipient)
		if not permitted.is_empty():
			_replication_queue.append({"method":method,"arguments":permitted.duplicate(true),"peer_id":recipient,"recipient_player_id":_peer_players[recipient]})

func _replication_arguments_for_peer(method: String, arguments: Array, peer_id: int) -> Array:
	if not _peer_players.has(peer_id): return []
	if method == "_receive_task_queues": return []
	if method == "_receive_move_modes":
		var ids: Array[int] = []
		var modes: Array[int] = []
		if arguments.size() != 2 or arguments[0].size() != arguments[1].size(): return []
		for index: int in arguments[0].size():
			var id: int = arguments[0][index]
			if _authoritative_units.has(id) and _authoritative_units[id].owner_player_id == _peer_players[peer_id]:
				ids.append(id)
				modes.append(arguments[1][index])
		return [ids,modes] if not ids.is_empty() else []
	if method == "_receive_acceptance_explosion":
		return acceptance_explosion_arguments(arguments) if acceptance_full_06 else []
	# DB34 makes projectile motion public, without revealing source/impact identity.
	if method == "_receive_projectile_events": return ProjectileProjection.batch(arguments)
	if method == "_receive_weapon_fires": return []
	if method == "_receive_unit_structures":
		var structures: Array[Dictionary] = []
		for structure: Dictionary in arguments[0]:
			if _authoritative_units.has(structure.unit_id) and _authoritative_units[structure.unit_id].owner_player_id == _peer_players[peer_id]:
				structures.append(structure)
		return [structures] if not structures.is_empty() else []
	if method == "_receive_unit_statuses":
		var statuses: Array[Dictionary] = []
		for structure: Dictionary in arguments[0]:
			if not _unit_disclosed(int(structure.get("unit_id",0))): continue
			var status := UnitStatusProjection.project(structure,_authoritative_units[structure.unit_id].owner_player_id == _peer_players[peer_id])
			if not status.is_empty(): statuses.append(status)
		return [statuses] if not statuses.is_empty() else []
	if method == "_receive_unit_snapshot":
		if arguments.size() != 1 or not arguments[0] is Dictionary or not arguments[0].get("unit_id") is int: return []
		return arguments if _unit_disclosed(int(arguments[0].unit_id)) else []
	if method in ["_receive_unit_positions","_receive_unit_orientations","_receive_unit_stops","_receive_move_targets","_receive_move_paths"]:
		var ids: Array[int] = []
		var values: Array = arguments[1].duplicate()
		values.clear()
		for index: int in arguments[0].size():
			var id: int = arguments[0][index]
			if _unit_disclosed(id):
				ids.append(id)
				values.append(arguments[1][index])
		return [ids,values] if not ids.is_empty() else []
	if method == "_receive_unit_death":
		return arguments if _unit_disclosed(arguments[0]) else []
	return arguments

static func acceptance_explosion_arguments(arguments: Array) -> Array:
	if arguments.size() != 1 or not arguments[0] is Dictionary: return []
	var event: Dictionary = arguments[0]
	if not event.get("position") is Vector3 or not event.position.is_finite() or not ImpactDamageRules.number(event.get("radius"),0) or event.radius <= 0: return []
	return [{"position":event.position,"radius":event.radius}]

@rpc("authority","call_remote","reliable")
func _receive_unit_statuses(statuses: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for status: Dictionary in statuses: presentation.apply_live_status(status)

@rpc("authority","call_remote","reliable")
func _receive_acceptance_explosion(event: Dictionary) -> void:
	if not acceptance_full_06 or multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	var permitted := acceptance_explosion_arguments([event])
	if not permitted.is_empty(): acceptance_explosion_received.emit(permitted[0])


func _flush_replication() -> void:
	var messages := _replication_queue
	_replication_queue = []
	for message: Dictionary in messages:
		if message.has("recipient_player_id") and _peer_players.get(message.peer_id,-1) != message.recipient_player_id: continue
		if message.method in ["_receive_command_notice","_receive_task_queues"] and _peer_players.get(message.peer_id, 0) != message.notice_player_id: continue
		if multiplayer.get_peers().is_empty():
			continue
		if message.peer_id == -1:
			callv("rpc", [StringName(message.method)] + message.arguments)
		elif multiplayer.get_peers().has(message.peer_id):
			callv("rpc_id", [message.peer_id, StringName(message.method)] + message.arguments)


func _ensure_deployment_ready() -> bool:
	if not legacy_combat_fixture_enabled and timeline.tick == 0: timeline.tick_hz = 30
	if deployment.is_ready():
		return true
	var config: DeploymentConfig = DEPLOYMENT_CONFIG
	if not legacy_combat_fixture_enabled:
		config = DEPLOYMENT_CONFIG.duplicate()
		config.catalog = []
		for entry: Dictionary in DEPLOYMENT_CONFIG.catalog:
			if entry.config_id != "test.rifle": continue
			var active_entry := entry.duplicate()
			active_entry.definition = _weapon_presets[0]
			if acceptance_06c:
				active_entry.value_points = 5
				active_entry.sortie_points = 5
				active_entry.maximum_present = 8
			config.catalog.append(active_entry)
			if acceptance_06c:
				var fixtures: Array[Dictionary] = [{"id":"test.editor.top","definition":_weapon_presets[1]},{"id":"test.editor.armor","definition":_weapon_presets[2]}]
				if acceptance_full_06:
					fixtures.append({"id":"test.editor.suppression","definition":_weapon_presets[3]})
					fixtures.append({"id":"test.editor.modules","definition":_weapon_presets[4]})
					fixtures.append({"id":"test.editor.manual","definition":_weapon_presets[5]})
					fixtures.append({"id":"test.editor.mechanical","definition":_weapon_presets[6]})
				for fixture: Dictionary in fixtures:
					var test_entry := active_entry.duplicate()
					test_entry.config_id = fixture.id
					test_entry.definition = fixture.definition
					config.catalog.append(test_entry)
				continue
			var mortar_entry := active_entry.duplicate()
			mortar_entry.config_id = "test.mortar"
			mortar_entry.definition = preload("res://data/units/db33_active_test_mortar.tres")
			config.catalog.append(mortar_entry) # Existing test economy values; no formal unit pricing.
	var error := deployment.initialize(config, _movement._config, MovementSimulation.MAP_DEFINITION, timeline.tick_hz)
	if not error.is_empty():
		push_error("Deployment configuration rejected: " + error)
		return false
	return true


# Server-only binding API for the existing command/target layer, never UI identity.
func bind_weapon_target(sender_peer: int, unit_id: int, instance_id: String, target_id: int) -> bool:
	if not multiplayer.is_server(): return false
	if not _authoritative_units.has(unit_id) or not _authoritative_units.has(target_id): return false
	var owner: UnitState = _authoritative_units[unit_id]
	var target: UnitState = _authoritative_units[target_id]
	if owner.owner_peer_id != sender_peer or not _peer_players.has(sender_peer) or owner.owner_player_id != _peer_players[sender_peer] or target.team_id == owner.team_id: return false
	# No production detection provider yet; an enemy ID is not visibility proof.
	if not legacy_combat_fixture_enabled: return false
	for instance: RuntimeWeaponInstance in owner.runtime_weapons:
		if instance.instance_id == instance_id:
			instance.bind_target(AttackTarget.unit(target))
			return true
	return false


func request_deployment(config_id: String, point_id: String, destination: Vector3) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_deployment.rpc_id(1, config_id, point_id, destination)


func request_cancel_deployment(order_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_cancel_deployment.rpc_id(1, order_id)


func request_buy_deployment(config_id: String, point_id: String, request_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_buy_deployment.rpc_id(1, config_id, point_id, request_id)


func request_edit_deployment(action: String, order_id: int, destination: Vector3, request_id: int, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_edit_deployment.rpc_id(1, action, order_id, destination, request_id, mode)


@rpc("any_peer", "call_remote", "reliable")
func _submit_buy_deployment(config_id: String, point_id: String, request_id: int) -> void:
	_queue_deployment_request({"type":"buy", "config_id":config_id,"point_id":point_id,"request_id":request_id})


@rpc("any_peer", "call_remote", "reliable")
func _submit_edit_deployment(action: String, order_id: int, destination: Vector3, request_id: int, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	_queue_deployment_request({"type":"edit","action":action,"order_id":order_id,"destination":destination,"request_id":request_id,"mode":mode})


@rpc("any_peer", "call_remote", "reliable")
func _submit_deployment(config_id: String, point_id: String, destination: Vector3) -> void:
	_queue_deployment_request({"type": "order", "config_id": config_id, "point_id": point_id, "destination": destination})


@rpc("any_peer", "call_remote", "reliable")
func _submit_cancel_deployment(order_id: int) -> void:
	_queue_deployment_request({"type": "cancel", "order_id": order_id})


func _queue_deployment_request(request: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender) or not _peer_players.has(sender):
		return
	request.peer_id = sender
	request.player_id = _peer_players[sender]
	_pending_deployment_requests.append(request)


func _consume_deployment_requests(connected_peers: PackedInt32Array) -> void:
	var requests := _pending_deployment_requests
	_pending_deployment_requests = []
	for request: Dictionary in requests:
		if not connected_peers.has(request.peer_id) or _peer_players.get(request.peer_id, 0) != request.player_id:
			continue
		var result: Dictionary
		if request.type == "order":
			result = deployment.request_order(request.player_id, request.config_id, request.point_id, request.destination)
		elif request.type == "buy":
			result = deployment.buy_order(request.player_id, request.config_id, request.point_id)
		elif request.type == "edit":
			match request.action:
				"pickup": result = deployment.pickup_order(request.player_id, request.order_id)
				"place": result = deployment.place_order(request.player_id, request.order_id, request.destination, request.get("mode", MovementSimulation.MoveMode.BASIC))
				"cancel": result = deployment.cancel_order(request.player_id, request.order_id)
				_: result = {"ok":false,"reason":"invalid deployment action"}
		elif request.type == "cancel":
			result = deployment.cancel_order(request.player_id, request.order_id)
		else:
			result = {"ok":false,"reason":"invalid deployment action"}
		result.request_type = request.type
		result.request_id = request.get("request_id", 0)
		# Always return authoritative state, including on refusal, for UI recovery.
		_queue_replication("_receive_deployment_state", [deployment.export_player(request.player_id)], request.peer_id)
		_queue_replication("_receive_deployment_result", [result], request.peer_id)


@rpc("authority", "call_remote", "reliable")
func _receive_deployment_state(state: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var received_player_id := int(state.get("player_id",0))
	if local_player_id != 0 and received_player_id != local_player_id:
		_clear_local_combat_overview()
	local_deployment_state = state.duplicate(true)
	local_player_id = received_player_id
	deployment_state_received.emit(state.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _receive_deployment_result(result: Dictionary) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() == 1:
		deployment_result_received.emit(result.duplicate(true))


func _spawn_deployment(order: Dictionary, position: Vector3, entry: Dictionary, point: Dictionary) -> int:
	var peer_id := 0
	for peer: int in _peer_players:
		if _peer_players[peer] == order.player_id:
			peer_id = peer
	var state := UnitState.new(_next_unit_id, peer_id, position)
	_next_unit_id += 1
	state.owner_player_id = order.player_id
	state.configure(deployment.export_player(order.player_id).faction_id, entry.definition)
	_register_combat_unit(state,entry.value_points)
	state.yaw = point.yaw
	state.generated_tick = timeline.tick
	_authoritative_units[state.unit_id] = state
	_movement.add_unit(state)
	_combat.add_unit(state)
	if not legacy_combat_fixture_enabled: _aiming.inputs[state.unit_id] = {"moving_spread_multiplier":1.5} # TEST ONLY, never DATA.
	var movement := _movement.deploy_move(state, order.destination, order.move_mode, entry.width)
	# Existing v1 unit/path state and spawn event suffice; economic/order state is
	# deliberately absent from the frozen replay format.
	timeline.append("event", "spawn", ReplayFormat.unit_state(state, _movement))
	_queue_replication("_receive_unit_snapshot", [_presentation_snapshot(state)])
	var ids: Array[int] = [state.unit_id]
	if peer_id != 0:
		if _movement._targets.has(state.unit_id):
			_queue_replication("_receive_move_targets", [ids, _movement.move_targets(ids)], peer_id)
			_queue_replication("_receive_move_paths", [ids, _movement.move_paths(ids)], peer_id)
		_queue_replication("_receive_deployment_result", [{"ok":true,"request_id":0,"request_type":"generated","order_id":order.order_id,"unit_id":state.unit_id,"generated_tick":timeline.tick,"notice":movement.notice}], peer_id)
	return state.unit_id
