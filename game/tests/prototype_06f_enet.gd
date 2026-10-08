extends SceneTree

var role := ""
var port := 17877
var started := 0
var injected := false
var finished := false
var observed_deaths: Array[int] = []
var statuses: Dictionary = {}
var source_id := 0
var target_id := 0
var phase_tick := -1
var injected_at_msec := -1
var last_statistics: Dictionary = {}
var issues: Array[String] = []
var network: Node

func _initialize() -> void: setup.call_deferred()

func setup() -> void:
	network = root.get_node("NetworkManager")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	started = Time.get_ticks_msec()
	if not network.configure_active_test_map() or not network.configure_acceptance_06c(true): fail("test setup rejected"); return
	network.presentation.unit_death_received.connect(func(id): observed_deaths.append(id))
	network.presentation.unit_status_received.connect(func(row): statuses[row.unit_id] = row.duplicate(true))
	network.combat_statistics_received.connect(func(row): last_statistics = row.duplicate(true))
	if role == "server":
		if not network.start_server(port): fail("server startup rejected")
	else:
		if not network.connect_to_server("127.0.0.1",port): fail("client connect rejected")

func _process(_delta: float) -> bool:
	if finished: return false
	if Time.get_ticks_msec()-started > 15000:
		if role == "server": issues.append("server state at timeout: injected=%s, source=%s, target=%s, deaths=%s, tick=%d, phase=%d, injected_at=%d, now=%d" % [str(injected),str(source_id),str(target_id),str(network.combat_outcomes.deaths.keys()),network.timeline.tick,phase_tick,injected_at_msec,Time.get_ticks_msec()])
		fail("three-endpoint completion timeout"); return false
	if role == "server": run_server()
	elif observed_deaths.size() >= 2 and not last_statistics.is_empty():
		if observed_deaths.size() != 2 or not observed_deaths.has(6) or not observed_deaths.has(3): issues.append("both expected units did not retire exactly once")
		var own: bool = network.local_player_id == 1
		if last_statistics.player_id != network.local_player_id: issues.append("statistics identity differs from authenticated player")
		if own and last_statistics.kill_value != 5: return false # Wait for private totals after the late shot.
		if own and (last_statistics.death_value != 5 or last_statistics.display_kd != "1.00"): issues.append("wrong owner value KD")
		if not own and (last_statistics.kill_value != 0 or last_statistics.death_value != 0): issues.append("other player received private statistics")
		var saw_private := false
		for row: Dictionary in statuses.values():
			if row.get("return_fire_only",false): saw_private = true
		if saw_private != own: issues.append("marker ownership projection mismatch")
		for id: int in observed_deaths:
			if network.presentation.live_structures.has(id) or network.local_task_queues.has(id): issues.append("retired client cache retained")
		complete({"role":role,"player_id":last_statistics.player_id,"deaths":observed_deaths,"statistics":last_statistics,"private_marker_seen":saw_private})
	return false

func run_server() -> void:
	if phase_tick < 0:
		if network._peer_players.size() != 2: return
		for unit: UnitState in network._authoritative_units.values():
			if source_id == 0 and unit.owner_player_id == 1 and unit.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE: source_id = unit.unit_id
			if target_id == 0 and unit.team_id == 2 and unit.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE and unit.position.x > 0: target_id = unit.unit_id
		if source_id == 0 or target_id == 0: fail("TEST ONLY combat actors missing"); return
		if not network.set_authoritative_marker_activity(source_id,{"laser":"paused","return_fire_only":true}): fail("TEST ONLY marker activity rejected"); return
		if network.deployment.card_counts(1,"test.editor.armor").present != 1: fail("TEST ONLY source card setup mismatch"); return
		phase_tick = network.timeline.tick
	if not injected and network.timeline.tick-phase_tick >= 15:
		var source: UnitState = network._authoritative_units[source_id]
		var target: UnitState = network._authoritative_units[target_id]
		spawn_exact(target,source,1000,1000) # Early enemy shot retires the eventual killer.
		spawn_exact(source,target,100,1000) # Legal slower round remains after its source's death.
		injected = true
		injected_at_msec = Time.get_ticks_msec()
	if injected and network.combat_outcomes.deaths.has(target_id) and network.combat_outcomes.deaths.has(source_id) and Time.get_ticks_msec()-injected_at_msec >= 1000:
		var ledger: CombatOutcomeLedger = network.combat_outcomes
		if ledger.deaths[target_id].killer_unit_id != source_id or ledger.deaths[target_id].killer_player_id != 1: issues.append("in-flight source attribution lost")
		if ledger.deaths[source_id].time_seconds >= ledger.deaths[target_id].time_seconds: issues.append("late projectile did not score after its source died")
		if ledger.deaths[target_id].source_event_id != "test_only:06f_enet:2" or not ledger.identities.has(source_id): issues.append("retired source identity did not survive to late impact")
		if network._authoritative_units.has(source_id) or network._authoritative_units.has(target_id): issues.append("server dead unit retained")
		if network.deployment.card_counts(1,"test.editor.armor").present != 0: issues.append("dead source failed to release one card capacity slot")
		if network.deployment.card_counts(2,"test.editor.armor").present != 1: issues.append("other player's capacity changed")
		complete({"role":role,"source_id":source_id,"target_id":target_id,"final_killer":ledger.deaths[target_id].killer_unit_id,"statistics":ledger.project_player(1)})

func spawn_exact(source: UnitState, target: UnitState, speed: float, damage: float) -> void:
	var simulation: DB29ProjectileSimulation = network._projectiles
	var ammo := ConfirmedGameData.new().ammunition("A_556")
	ammo.initial_speed_mps = speed
	ammo.nominal_damage = damage
	ammo.ammo_id = "test_only:06f_enet_exact"
	var order: int = network._fire.emission_order+1
	var event := {"event_id":"test_only:06f_enet:"+str(order),"emission_order":order,"time_seconds":simulation.time_seconds,
		"unit_id":source.unit_id,"owner_player_id":source.owner_player_id,"team_id":source.team_id,"weapon_instance_id":"test_only:06f_enet_weapon",
		"position":source.position+source.position.direction_to(target.position),"velocity":source.position.direction_to(target.position)*speed,"ammo":ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var motion := ProjectileUnitMotion.new()
	var poses := ProjectileUnitMotion.capture(network._authoritative_units)
	motion.configure(simulation.time_seconds,poses,poses)
	var flight := OrderedProjectileStep.new()
	flight.begin(simulation,motion)
	if flight.spawn(event).is_empty(): issues.append("exact TEST ONLY projectile spawn rejected")
	network._fire.emission_order = order

func fail(message: String) -> void:
	issues.append(message)
	complete({"role":role})

func complete(result: Dictionary) -> void:
	finished = true
	result.issues = issues
	var file := FileAccess.open("res://../tmp/06f-07states/enet-"+role+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("06F ENET ",role," ","PASS" if issues.is_empty() else "FAIL", " ",issues)
	if role == "server": network.finish_server()
	else: network.multiplayer.multiplayer_peer.close()
	quit(0 if issues.is_empty() else 1)
