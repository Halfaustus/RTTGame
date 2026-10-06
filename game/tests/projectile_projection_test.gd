extends "res://tests/db29_combat_timeline_test.gd"

func run() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._peer_players[42] = 1
	model._peer_players[43] = 2
	model._players[1] = {"team_id":1}
	model._players[2] = {"team_id":2}
	var private_event := {"projectile_id":"projectile:unit-secret/weapon-secret:1","emission_order":7,
		"time_seconds":0.0,"position":Vector3(1,10,3),"velocity":Vector3(10,10,0),"acceleration":GravityBallistics.GRAVITY,
		"unit_id":123,"owner_player_id":999,"weapon_instance_id":"weapon-secret","source_event_id":"secret",
		"ammo_definition_id":"secret-ammo","ammo":data.ammunition("A_556"),"target_id":999,"future_private_field":{"inventory":1234}}
	var end := private_event.duplicate()
	end.reason = "impact"
	end.time_seconds = 0.02
	end.position = Vector3(1.2,10.198,3)
	end.hit_unit_id = 888
	end.object_id = "secret-hit"
	var batch: Array = [[private_event],[end],0.03]
	var public_one: Array = model._replication_arguments_for_peer("_receive_projectile_events",batch,42)
	var public_two: Array = model._replication_arguments_for_peer("_receive_projectile_events",batch,43)
	check(public_one == public_two and not public_one.is_empty(),"all registered players receive identical projectile motion independent of source team/visibility")
	check(model._replication_arguments_for_peer("_receive_projectile_events",batch,99).is_empty(),"unauthenticated connection receives no projectile payload")
	check(public_one[0][0].size() == 6 and public_one[1][0].size() == 4,"strict spawn and terminal field whitelist")
	check(public_one[0][0].projectile_id == "flight:7" and public_one[1][0].projectile_id == "flight:7","source-free stable display identity")
	for field: String in ["unit_id","owner_player_id","weapon_instance_id","source_event_id","ammo_definition_id","ammo","target_id","future_private_field","hit_unit_id","object_id"]:
		check(not public_one[0][0].has(field) and not public_one[1][0].has(field),"private field excluded: "+field)
	check(public_one[0][0].values().all(func(value): return not value is Object),"public values have no Resource references")
	public_one[0][0].position = Vector3.ZERO
	check(private_event.position == Vector3(1,10,3),"projection does not mutate authoritative data")
	check(model._replication_arguments_for_peer("_receive_weapon_fires",[[private_event]],42).is_empty(),"weapon fire details remain private")
	check(model._replication_arguments_for_peer("_receive_unit_snapshot",[{"team_id":2}],42).is_empty(),"enemy unit snapshot remains withheld")
	check(model._replication_arguments_for_peer("_receive_projectile_events",[[{"target_id":999}],[],0.0],42).is_empty(),"malformed motion cannot create a disclosure event")
	check(model._replication_arguments_for_peer("_receive_projectile_events",[[],[],NAN],42).is_empty(),"invalid authority clock rejected")
	model._queue_replication("_receive_projectile_events",batch)
	check(model._replication_queue.size() == 2 and model._replication_queue[0].arguments == model._replication_queue[1].arguments,"actual queue sends sanitized batch to both registered peers")
	model._replication_queue.clear()
	model.legacy_combat_fixture_enabled = true
	model._queue_replication("_receive_projectile_events",batch)
	check(model._replication_queue.size() == 2 and model._replication_queue[0].arguments[0][0].size() == 6,"legacy opt-in cannot bypass public projectile privacy")
	model.legacy_combat_fixture_enabled = false
	model._receive_projectile_events(public_two[0],public_two[1],0.03)
	check(model.presentation.live_projectiles.is_empty(),"direct local invocation cannot spoof server RPC")
	# Independent per-ID snapshots: an old surviving projectile may arrive after a newer one.
	var feed := PresentationFeed.new()
	var visual := ProjectileVisuals.new()
	visual.setup(feed)
	root.add_child(visual)
	var projected := ProjectileProjection.spawn(private_event)
	var newer := projected.duplicate()
	newer.projectile_id = "flight:8"
	newer.emission_order = 8
	feed.apply_projectile_spawn(newer)
	feed.apply_projectile_spawn(projected)
	feed.apply_projectile_spawn(projected)
	check(feed.live_projectiles.size() == 2,"out-of-order surviving snapshot accepted and duplicate spawn deduplicated")
	var snapshot := projected.duplicate()
	snapshot.time_seconds = 2.0
	snapshot.position = Vector3(21,10,3)
	snapshot.velocity = Vector3(10,-10,0)
	feed.apply_projectile_spawn(snapshot)
	feed.apply_projectile_spawn(projected)
	check(feed.live_projectiles["flight:7"] == snapshot,"newer current flight snapshot replaces state; stale spawn cannot rewind")
	feed.synchronize_projectile_time(2.0)
	visual._process(0.02)
	check(feed.projectile_position("flight:7",3.0) == Vector3(31,-5,3),"gravity display uses current snapshot state without resimulating shot")
	check(visual.mesh.get_surface_count() == 1,"one shared mesh renders active projectile trails")
	feed.advance_projectile_display(10)
	check(absf(feed.projectile_display_time-2.0-feed.interpolation_delay-PresentationFeed.MAX_EXTRAPOLATION_SECONDS) < 0.000001,"stalled authority bounds extrapolation to client time budget")
	feed.synchronize_projectile_time(1.0)
	check(feed.projectile_authority_time == 2.0,"old clock packet cannot rewind authoritative time")
	feed.unit_death_received.emit(123)
	check(feed.live_projectiles.size() == 2,"source removal does not end public flight")
	var terminal := {"projectile_id":"flight:7","time_seconds":2.02,"position":Vector3(21.2,9.798,3),"reason":"impact"}
	feed.apply_projectile_terminal(terminal)
	feed.apply_projectile_terminal(terminal)
	feed.apply_projectile_spawn(projected)
	check(feed.live_projectiles.size() == 1 and not feed.live_projectiles.has("flight:7"),"duplicate terminal and stale spawn cannot resurrect ended flight")
	feed.apply_projectile_terminal({"projectile_id":"unknown"})
	check(feed.live_projectiles.size() == 1,"unknown terminal cannot create projectile")
	feed.reset_received.emit()
	check(feed.live_projectiles.is_empty() and visual.mesh.get_surface_count() == 0 and visual._flashes.is_empty(),"reset clears current trajectories and terminal flashes")
	feed.apply_projectile_spawn(projected)
	feed.apply_projectile_terminal(ProjectileProjection.terminal(end))
	check(feed.live_projectiles.is_empty() and visual._flashes.size() == 1,"same-batch short flight terminates but remains briefly visible as a terminal trail")
	visual._process(0.12)
	visual._process(0.0)
	check(visual.mesh.get_surface_count() == 0,"terminal flash expires without simulated impact effects")
	model.presentation.apply_projectile_spawn(projected)
	model._on_server_disconnected()
	check(model.presentation.live_projectiles.is_empty(),"disconnect clears feed state before next match")
	# Real consumer lifecycle: slot reuse and source metadata remain authoritative only.
	var sim := DB29ProjectileSimulation.new()
	sim.configure_bounds(Rect2(-1,-1,2,2))
	var shot := {"event_id":"private:source:1","emission_order":1,"time_seconds":0.0,"position":Vector3.ZERO,"velocity":Vector3(900,0,0),"ammo":data.ammunition("A_556"),"unit_id":123,"owner_player_id":999,"weapon_instance_id":"private:source"}
	var input: Array[Dictionary] = [shot]
	var events := sim.step(input)
	check(events.size() == 2 and events[1].reason == "battlefield_exit","real point consumer produces same-step spawn and exit")
	var first_id: String = ProjectileProjection.spawn(events[0]).projectile_id
	check(first_id == ProjectileProjection.terminal(events[1]).projectile_id,"real lifecycle identity consistent")
	shot.event_id = "private:source:2"
	shot.emission_order = 2
	shot.time_seconds = sim.time_seconds
	input = [shot]
	events = sim.step(input)
	check(sim.profile.reuses == 1 and ProjectileProjection.spawn(events[0]).projectile_id != first_id,"reused simulation slot never reuses public identity")
	sim.collision.close()
	# Snapshot from a real surviving shell starts at current flight position, not muzzle.
	sim = DB29ProjectileSimulation.new()
	shot.time_seconds = 0.0
	shot.emission_order = 1
	input = [shot]
	sim.step(input)
	var active := sim.active_spawns()
	var late := ProjectileProjection.batch([active,[],sim.time_seconds])
	check(late[0].size() == 1 and absf(late[0][0].position.x-30) < 0.0001 and late[0][0].time_seconds == sim.time_seconds,"late join receives current real flight state")
	var late_feed := PresentationFeed.new()
	late_feed.synchronize_projectile_time(late[2])
	late_feed.apply_projectile_spawn(late[0][0])
	check(late_feed.projectile_position(late[0][0].projectile_id,sim.time_seconds) == active[0].position,"late join does not replay from muzzle")
	sim.collision.close()
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	world.presentation_source = feed
	root.add_child(world)
	check(world._projectile_visuals != null and world._projectile_visuals.feed == feed,"activity scene binds independent projectile presentation")
	world.free()
	visual.free()
	model.free()
	print("Projectile projection: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
