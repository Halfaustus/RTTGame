extends "res://tests/prototype_06b_test.gd"

func actor(id: int, player: int, team: int) -> UnitState:
	var unit := UnitState.new(id,player,Vector3.ZERO)
	unit.owner_player_id = player
	var definition := UnitDefinition.new()
	definition.configuration_source = "test_only:06f_ledger"
	definition.member_count = 1
	unit.configure(team,definition)
	return unit

func death(id: int, source: UnitState, at: float = 1.0) -> Dictionary:
	return {"unit_id":id,"unit_died":true,"source_unit_id":source.unit_id,"source_player_id":source.owner_player_id,"time_seconds":at,"source_event_id":"test_only:06f:"+str(at)}

func run() -> void:
	var formal := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var frozen := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var ledger := CombatOutcomeLedger.new()
	var victim := actor(1,10,1)
	var attacker := actor(2,20,2)
	var other := actor(3,21,2)
	for entry: Dictionary in [{"unit":victim,"value":200},{"unit":attacker,"value":50},{"unit":other,"value":50}]:
		check(ledger.register_unit(entry.unit,entry.value),"immutable match identity registered")
	check(ledger.commit_damage({"unit_id":1,"unit_died":false}) and ledger.deaths.is_empty(),"single-member damage never awards whole-squad value")
	check(ledger.commit_damage(death(1,other)),"only final eliminating source committed")
	check(ledger.project_player(20).kill_value == 0 and ledger.project_player(21).kill_value == 200,"earlier attacker receives neither kill value nor assist")
	check(ledger.project_player(10).death_value == 200 and ledger.deaths[1].killer_unit_id == 3,"whole unit death value and final unit identity")
	check(ledger.commit_damage(death(1,attacker,2)) and ledger.project_player(10).death_value == 200,"duplicate and later hits never double-count or replace killer")
	check(ledger.project_player(21).display_kd == "无损" and ledger.project_player(21).value_kd == null,"zero deaths use no-loss display without count KD")
	var friendly := actor(4,11,1)
	ledger.register_unit(friendly,100)
	check(ledger.commit_damage(death(4,victim,3)),"friendly kill records victim death")
	check(ledger.project_player(10).kill_value == 0 and ledger.project_player(11).death_value == 100 and ledger.deaths[4].friendly_fire,"friendly killer receives no kill value")
	var self_unit := actor(5,12,1)
	ledger.register_unit(self_unit,50)
	check(ledger.commit_damage(death(5,self_unit,4)) and ledger.project_player(12).death_value == 50 and ledger.project_player(12).kill_value == 0,"self damage is friendly death without kill value")
	check(ledger.commit_damage(death(2,victim,5)) and is_equal_approx(ledger.project_player(10).value_kd,0.25),"value KD uses cumulative values, including previously dead killer identity")
	var unpriced := actor(6,30,2)
	ledger.register_unit(unpriced,null)
	check(ledger.commit_damage(death(6,victim,6)) and not ledger.project_player(10).configured and ledger.project_player(10).display_kd == "未配置","missing value is not silently zero")
	check(not ledger.register_unit(actor(1,99,1),200) and not ledger.register_unit(actor(7,99,1),7),"identity reassignment and invalid scores rejected")
	var bad := death(3,victim,7)
	bad.source_player_id = 999
	check(not ledger.commit_damage(bad) and not ledger.deaths.has(3),"mismatched source domain identity never scores")
	var partial := CombatOutcomeLedger.new()
	var scored_killer := actor(80,80,2)
	var known_victim := actor(81,81,1)
	var unpriced_victim := actor(82,82,1)
	partial.register_unit(scored_killer,0)
	partial.register_unit(known_victim,25)
	partial.register_unit(unpriced_victim,null)
	partial.commit_damage(death(81,scored_killer,8))
	partial.commit_damage(death(82,scored_killer,9))
	var partial_kills := partial.project_player(80)
	check(partial_kills.kill_value == null and partial_kills.death_value == 0 and partial_kills.value_kd == null and not partial_kills.configured,"known kill subtotal is hidden when another kill value is unknown; death total remains known")
	var unpriced_deaths := partial.project_player(82)
	check(unpriced_deaths.kill_value == 0 and unpriced_deaths.death_value == null and unpriced_deaths.value_kd == null and not unpriced_deaths.configured,"unknown death value does not hide independent known kill total")
	var zero_ledger := CombatOutcomeLedger.new()
	var zero_killer := actor(83,83,2)
	var zero_victim := actor(84,84,1)
	zero_ledger.register_unit(zero_killer,10)
	zero_ledger.register_unit(zero_victim,0)
	zero_ledger.commit_damage(death(84,zero_killer,10))
	check(zero_ledger.project_player(83).kill_value == 0 and zero_ledger.project_player(84).death_value == 0 and zero_ledger.project_player(83).configured,"explicit configured zero remains a numeric total")
	var network_manager: Node = root.get_node_or_null("NetworkManager")
	check(network_manager != null,"network manager singleton is available to menu formatter")
	var previous_statistics: Dictionary = network_manager.local_combat_statistics.duplicate(true) if network_manager != null else {}
	var world = load("res://scripts/core/game_world.gd").new()
	var statistics_menu := Control.new()
	var statistics_label := Label.new()
	statistics_label.name = "CombatStatistics"
	statistics_menu.add_child(statistics_label)
	world._menu = statistics_menu
	if network_manager != null: network_manager.local_combat_statistics = partial_kills
	world._refresh_combat_statistics()
	check(network_manager != null and statistics_label.text.contains("未配置") and not statistics_label.text.contains("null") and statistics_label.text.contains("0"),"combat menu labels unknown total and preserves known zero")
	if network_manager != null: network_manager.local_combat_statistics = zero_ledger.project_player(83)
	world._refresh_combat_statistics()
	check(network_manager != null and statistics_label.text.contains("击杀价值 0") and not statistics_label.text.contains("未配置"),"combat menu formats configured zero as numeric zero")
	world.free()
	statistics_menu.free()
	if network_manager != null: network_manager.local_combat_statistics = previous_statistics
	# Real sequential impacts kill individual members at event time.
	var test := fixture(2)
	test.unit.definition.protection_kinetic = 6 # TEST ONLY, matching the existing B integration fixture.
	test.unit.definition.protection_chemical = 6
	test.target.owner_player_id = 43
	test.timeline.direct_hit_enabled = true
	test.weapon.enabled = false
	ledger = CombatOutcomeLedger.new()
	ledger.register_unit(test.unit,200)
	ledger.register_unit(test.target,50)
	test.timeline.direct_hits.damage_committed = ledger.commit_damage
	incoming(test,0.8,100,1)
	var result: Dictionary = test.timeline.step(test.aiming)
	check(not test.timeline.halted and test.unit.health == 5 and ledger.deaths.is_empty(),"first real member death earns no whole-squad value")
	var ammo := data.ammunition("A_556")
	ammo.nominal_damage = 100 # TEST ONLY second shot aligned to the survivor's actual position.
	var alive: SoldierState = test.unit.members.filter(func(member): return member.health > 0)[0]
	var event := {"event_id":"test_only:06f_final","emission_order":2,"time_seconds":test.timeline.projectiles.time_seconds,
		"unit_id":test.target.unit_id,"owner_player_id":43,"weapon_instance_id":"test_only:06f_weapon",
		"position":alive.position-Vector3(0,0,1),"velocity":Vector3(0,0,ammo.initial_speed_mps),"ammo":ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var motion := ProjectileUnitMotion.new()
	var poses := ProjectileUnitMotion.capture(test.aiming.units)
	motion.configure(test.timeline.projectiles.time_seconds,poses,poses)
	var flight := OrderedProjectileStep.new()
	flight.begin(test.timeline.projectiles,motion)
	check(not flight.spawn(event).is_empty(),"final shot spawns at actual current combat time")
	test.timeline.fire.emission_order = 2
	result = test.timeline.step(test.aiming)
	check(not test.timeline.halted and test.unit.health == 0 and result.damage_results.size() == 1,"real ordered final projectile eliminates remaining member")
	check(ledger.deaths.size() == 1 and ledger.project_player(43).kill_value == 200 and ledger.deaths[test.unit.unit_id].time_seconds == result.damage_results.back().time_seconds,"only actual final impact awards the squad at its true time")
	test.timeline.projectiles.collision.close()
	# One ordered explosive impact can eliminate several members; only the final
	# whole-unit death callback awards one value, and duplicate delivery is inert.
	test = fixture(2)
	test.unit.definition.protection_kinetic = 6
	test.unit.definition.protection_chemical = 6
	test.target.owner_player_id = 43
	var blast_ammo := data.ammunition("A_556")
	blast_ammo.ammo_id = "test_only:06f_multi_member_blast"
	blast_ammo.nominal_damage = 100
	blast_ammo.explosion_radius_m = 4
	blast_ammo.suppression = 0
	blast_ammo.configure_confirmed_curve()
	ledger = CombatOutcomeLedger.new()
	ledger.register_unit(test.unit,200)
	ledger.register_unit(test.target,50)
	test.timeline.direct_hit_enabled = true
	test.timeline.direct_hits.damage_committed = ledger.commit_damage
	var blast_event := {"event_id":"test_only:06f_blast_final","emission_order":1,"time_seconds":0.0,
		"unit_id":test.target.unit_id,"owner_player_id":43,"weapon_instance_id":"test_only:06f_blast_weapon",
		"position":Vector3(0,0,-1),"velocity":Vector3(0,0,blast_ammo.initial_speed_mps),"ammo":blast_ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var blast_motion := ProjectileUnitMotion.new()
	var blast_poses := ProjectileUnitMotion.capture(test.aiming.units)
	blast_motion.configure(0.0,blast_poses,blast_poses)
	var blast_flight := OrderedProjectileStep.new()
	blast_flight.begin(test.timeline.projectiles,blast_motion)
	check(not blast_flight.spawn(blast_event).is_empty(),"real ordered explosive elimination shot spawns")
	test.timeline.fire.emission_order = 1
	result = test.timeline.step(test.aiming,blast_motion)
	check(not test.timeline.halted and test.unit.health == 0 and result.damage_results.size() >= 2,"real explosion kills all members in one ordered timeline")
	check(ledger.deaths.size() == 1 and ledger.project_player(43).kill_value == 200 and ledger.deaths[test.unit.unit_id].killer_unit_id == test.target.unit_id,"multi-member explosion awards one whole-unit value to its final source")
	var saved_death: Dictionary = ledger.deaths[test.unit.unit_id].duplicate(true)
	for outcome: Dictionary in result.damage_results: ledger.commit_damage(outcome)
	check(ledger.deaths.size() == 1 and ledger.project_player(43).kill_value == 200 and ledger.deaths[test.unit.unit_id] == saved_death,"same-tick explosion duplicate outcomes are idempotent")
	test.timeline.projectiles.collision.close()
	# Two real same-tick impacts use the existing stable weapon key; the later
	# impact, and only that source, receives the whole-unit kill.
	test = fixture(2)
	test.unit.definition.protection_kinetic = 6
	test.target.owner_player_id = 43
	test.target.position = Vector3(10,0,-30)
	test.weapon.enabled = false
	var second_source := actor(7001,44,2)
	second_source.position = Vector3(20,0,-30)
	test.aiming.units[second_source.unit_id] = second_source
	ledger = CombatOutcomeLedger.new()
	ledger.register_unit(test.unit,200)
	ledger.register_unit(test.target,50)
	ledger.register_unit(second_source,60)
	test.timeline.direct_hit_enabled = true
	test.timeline.direct_hits.damage_committed = ledger.commit_damage
	var tie_ammo := data.ammunition("A_556")
	tie_ammo.ammo_id = "test_only:06f_tie_round"
	tie_ammo.nominal_damage = 100
	var tie_poses := ProjectileUnitMotion.capture(test.aiming.units)
	var tie_motion := ProjectileUnitMotion.new()
	tie_motion.configure(0.0,tie_poses,tie_poses)
	var tie_flight := OrderedProjectileStep.new()
	tie_flight.begin(test.timeline.projectiles,tie_motion)
	var first_event := {"event_id":"test_only:06f_tie:first","emission_order":1,"time_seconds":0.0,
		"unit_id":test.target.unit_id,"owner_player_id":43,"weapon_instance_id":"a_stable_first",
		"position":Vector3(0,0,-1),"velocity":Vector3(0,0,tie_ammo.initial_speed_mps),"ammo":tie_ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var final_event: Dictionary = first_event.duplicate(true)
	final_event.event_id = "test_only:06f_tie:final"
	final_event.emission_order = 2
	final_event.time_seconds = 0.01 # Still this fixed step; after first terminal in shared timeline order.
	final_event.unit_id = second_source.unit_id
	final_event.owner_player_id = second_source.owner_player_id
	final_event.weapon_instance_id = "z_stable_final"
	final_event.position = test.unit.members[1].position-Vector3(0,0,1)
	check(not tie_flight.spawn(first_event).is_empty() and not tie_flight.spawn(final_event).is_empty(),"two sources fire during one fixed combat step")
	test.timeline.fire.emission_order = 2
	result = test.timeline.step(test.aiming,tie_motion)
	check(not test.timeline.halted and result.damage_results.size() == 2 and test.unit.health == 0,"same-tick real source impacts eliminate target through ordered timeline "+str(result.damage_results)+" slots="+str(test.timeline.projectiles.profile))
	check(CombatEventOrder.before({"time_seconds":1.0,"unit_id":test.unit.unit_id,"weapon_instance_id":"a_stable_first","source_event_id":"a"},{"time_seconds":1.0,"unit_id":test.unit.unit_id,"weapon_instance_id":"z_stable_final","source_event_id":"z"}),"same-time impact tie uses existing stable weapon key")
	check(ledger.deaths.has(test.unit.unit_id) and ledger.deaths[test.unit.unit_id].killer_unit_id == second_source.unit_id and ledger.project_player(44).kill_value == 200 and ledger.project_player(43).kill_value == 0,"stable final source receives whole-unit kill without an assist")
	test.timeline.projectiles.collision.close()
	# Actual server cleanup and recipient filtering; no ENet or production DATA.
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	check(model.configure_active_test_map() and model._ensure_deployment_ready(),"server economy/navigation ready")
	model._peer_players[42] = 10
	model._peer_players[43] = 11
	model.deployment.register_player(10,1,0)
	model.deployment.register_player(11,1,0)
	victim = UnitState.new(9000,42,Vector3(20,0.5,100))
	victim.owner_player_id = 10
	victim.configure(1,model._weapon_presets[0])
	model._authoritative_units[9000] = victim
	model._movement.add_unit(victim)
	model._combat.add_unit(victim)
	model._aiming.units = model._authoritative_units
	model._aiming.inputs[9000] = {"test_only":true}
	model._pending_positions[9000] = victim.position
	model._movement._deployment_navigation[9000] = {"test_only":"width_cache_key_collision"}
	check(model.deployment.register_live_unit(9000,10,victim.definition,0),"live card registered for upkeep")
	check(model._register_combat_unit(victim) and model.combat_outcomes.identities[9000].value_points == 200,"value uses configured value rather than sortie cost")
	var balance: float = model.deployment.export_player(10).balance
	check(model.deployment.card_counts(10,"test.rifle").present == 1 and model.deployment.current_upkeep(10) > 0,"live unit occupies card and accrues upkeep")
	model._task_queue.submit(9000,{"type":"move","target":Vector3(25,0.5,100)},false)
	model._movement.request_move(9000,42,Vector3(25,0.5,100))
	victim.health = 0
	check(model._retire_active_unit(9000),"dead authoritative unit retires")
	check(not model._authoritative_units.has(9000) and not model._movement._units.has(9000) and not model._combat._units.has(9000),"all live domain indices removed")
	check(model._movement._deployment_navigation.has(9000),"retiring a unit cannot erase shared deployment navigation keyed by equal width")
	check(not model._task_queue.tasks.has(9000) and not model._pending_positions.has(9000) and not model._aiming.inputs.has(9000),"queue movement/private state cleaned")
	check(model.deployment.card_counts(10,"test.rifle").present == 0 and model.deployment.current_upkeep(10) == 0 and model.deployment.export_player(10).balance == balance,"death releases capacity and stops upkeep without charging or refunding")
	check(model._retired_unit_ids == [9000] and not model._retire_active_unit(9000),"retirement cannot repeat")
	check(model._replication_queue.filter(func(message): return message.method == "_receive_unit_death").size() == 2,"known death queued to both permitted peers before identity removal")
	check(model.combat_outcomes.identities.has(9000),"source identity survives retirement")
	var hidden := actor(9001,0,2)
	model._authoritative_units[9001] = hidden
	hidden.health = 0
	var before: int = model._replication_queue.size()
	model._retire_active_unit(9001)
	check(model._replication_queue.size() == before,"undisclosed enemy death never replicated")
	model._queue_replication("_receive_combat_statistics",[model.combat_outcomes.project_player(10)])
	check(model._replication_queue.size() == before,"statistics cannot be broadcast")
	model._queue_replication("_receive_combat_statistics",[model.combat_outcomes.project_player(10)],43)
	check(model._replication_queue.size() == before,"statistics cannot be sent to another owner")
	model._queue_replication("_receive_combat_statistics",[model.combat_outcomes.project_player(10)],42)
	check(model._replication_queue.back().recipient_player_id == 10 and not model._replication_queue.back().arguments[0].has("killer_unit_id"),"owner-only totals omit internal death identity")
	# A transport leave closes the peer session but does not retract a legal shot
	# already in the ordered projectile timeline or erase its match identity.
	var orphan := fixture(1)
	orphan.unit.definition.protection_kinetic = 6
	orphan.target.owner_peer_id = 99
	orphan.target.owner_player_id = 12
	model._peer_players[99] = 12
	model._authoritative_units[orphan.target.unit_id] = orphan.target
	model._authoritative_units[orphan.unit.unit_id] = orphan.unit
	model.combat_outcomes.register_unit(orphan.unit,200)
	model.combat_outcomes.register_unit(orphan.target,50)
	orphan.timeline.direct_hit_enabled = true
	orphan.timeline.direct_hits.damage_committed = model._record_combat_damage
	var orphan_ammo := data.ammunition("A_556")
	orphan_ammo.ammo_id = "test_only:06f_disconnected_fired_round"
	orphan_ammo.nominal_damage = 100
	var orphan_event := {"event_id":"test_only:06f_disconnected_fired","emission_order":1,"time_seconds":0.0,
		"unit_id":orphan.target.unit_id,"owner_player_id":12,"weapon_instance_id":"test_only:06f_disconnected_weapon",
		"position":Vector3(0,0,-1),"velocity":Vector3(0,0,orphan_ammo.initial_speed_mps),"ammo":orphan_ammo,
		"weapon_values":{"reduction_ignore":0.0,"attack_top":false}}
	var orphan_poses := ProjectileUnitMotion.capture(orphan.aiming.units)
	var orphan_motion := ProjectileUnitMotion.new()
	orphan_motion.configure(0.0,orphan_poses,orphan_poses)
	var orphan_flight := OrderedProjectileStep.new()
	orphan_flight.begin(orphan.timeline.projectiles,orphan_motion)
	check(not orphan_flight.spawn(orphan_event).is_empty(),"legal source projectile is already fired before disconnect")
	model._on_peer_disconnected(99)
	model.timeline.begin_tick()
	model._consume_sessions(PackedInt32Array())
	check(not model._peer_players.has(99) and model._authoritative_units.has(orphan.target.unit_id) and model.combat_outcomes.identities.has(orphan.target.unit_id),"disconnect handler closes peer session while preserving active unit and registered match identity")
	orphan.timeline.fire.emission_order = 1
	var orphan_result: Dictionary = orphan.timeline.step(orphan.aiming,orphan_motion)
	check(not orphan.timeline.halted and orphan.unit.health == 0 and orphan_result.damage_results.size() > 0,"already-fired projectile finishes after disconnect session handling")
	check(model.combat_outcomes.project_player(12).kill_value == 200 and model.combat_outcomes.deaths[orphan.unit.unit_id].killer_unit_id == orphan.target.unit_id and model.combat_outcomes.identities.has(orphan.target.unit_id),"production ledger preserves source identity and owner-only kill statistic after disconnect")
	orphan.timeline.projectiles.collision.close()
	model.queue_free()
	var feed := PresentationFeed.new()
	feed.apply_live_structure({"unit_id":90,"members":[]})
	feed.unit_death_received.emit(90)
	feed.apply_live_structure({"unit_id":90,"members":[]})
	check(not feed.live_structures.has(90),"late state cannot resurrect dead private cache")
	feed.reset_received.emit()
	feed.apply_live_structure({"unit_id":90,"members":[]})
	check(feed.live_structures.has(90),"new session clears retired identity tombstones")
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == formal and FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == frozen,"formal DATA and frozen v1 remain unchanged")
	print("0.6F checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
