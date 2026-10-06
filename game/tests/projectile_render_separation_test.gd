extends "res://tests/db29_projectile_test.gd"

class SnapshotServer:
	extends "res://scripts/networking/network_manager.gd"
	var captured: Array[Dictionary] = []
	func _flush_replication() -> void:
		captured.append_array(_replication_queue)
		_replication_queue.clear()

func snapshot(time: float, x: float) -> Dictionary:
	return {"projectile_id":"flight:1","emission_order":1,"time_seconds":time,"position":Vector3(x,2,0),"velocity":Vector3(900,0,0),"acceleration":Vector3.ZERO}

func run() -> void:
	var buffer := ProjectileSnapshotBuffer.new()
	buffer.push(snapshot(0,0))
	buffer.push(snapshot(1.0/30,30))
	for alpha in [0.0,0.25,0.5,0.75,1.0]:
		check(absf(buffer.sample(alpha/30).position.x-30*alpha)<0.0001,"snapshot interpolation alpha %s" % alpha)
	buffer.push(snapshot(1.0/30,30))
	check(buffer.snapshots.size()==2,"duplicate timestamp is ignored")
	check(absf(buffer.sample(10).position.x-75)<0.0001,"extrapolation freezes after 50ms")
	buffer.render(0.07,1.0/120)
	buffer.push(snapshot(0.08,68)) # TEST ONLY perturbed authority recovery.
	var correction := buffer.render(0.08,1.0/120)
	check(correction.position.x>68 and correction.position.x<80,"small prediction error converges rather than teleporting")
	for frame in range(120): correction=buffer.render(0.08,1.0/120)
	check(absf(correction.position.x-68)<0.001,"correction offset decays to authority target")
	var late := ProjectileSnapshotBuffer.new()
	late.push(snapshot(10,9000))
	check(late.sample(9.95).position.x==9000,"late join does not replay absent history")
	for fps in [30,60,120,144]:
		var rendering := ProjectileSnapshotBuffer.new()
		rendering.push(snapshot(0,0))
		rendering.push(snapshot(1.0/30,30))
		var previous_x := -1.0
		for frame in range(ceili(float(fps)/30)+1):
			var time := minf(float(frame)/fps,1.0/30)
			var rendered := rendering.render(time,1.0/fps)
			check(absf(rendered.position.x-900*time)<0.001 and rendered.position.x>=previous_x,"render-frame interpolation at %dFPS frame %d" % [fps,frame])
			previous_x=rendered.position.x
	var model := SnapshotServer.new()
	root.add_child(model)
	model._peer_players[42]=10
	model._peer_players[43]=20
	model._peer_players[44]=30
	model._queue_replication("_receive_projectile_events",[[snapshot(0,0)],[],0.0])
	check(model._replication_queue.size()==3 and model._replication_queue[0].arguments==model._replication_queue[2].arguments,"three domain players receive the same sanitized motion")
	model._replication_queue.clear()
	check(model.configure_active_test_map() and model._ensure_deployment_ready(),"actual server initialized for periodic snapshot test")
	var unit := UnitState.new(9900,42,Vector3(20,0.5,100))
	unit.configure(1,model._weapon_presets[0])
	unit.owner_player_id=10
	model._authoritative_units[9900]=unit
	model._movement.add_unit(unit)
	model._combat.add_unit(unit)
	model._execute_command({"type":"ground_fire","unit_ids":[9900],"target":Vector3(20,0,-180),"peer_id":42,"player_id":10})
	for tick in range(90): model._run_server_tick(PackedInt32Array([42,43,44]))
	var states_by_id := {}
	for packet: Dictionary in model.captured:
		if packet.method!="_receive_projectile_events" or packet.peer_id!=42: continue
		for row: Dictionary in packet.arguments[0]:
			if not states_by_id.has(row.projectile_id): states_by_id[row.projectile_id]=[]
			states_by_id[row.projectile_id].append(row.time_seconds)
	check(states_by_id.values().any(func(times): return times.size()>2 and times.back()>times.front()),"actual server broadcasts successive public motion snapshots, not just clock anchors")
	model.free()
	var visual := ProjectileVisuals.new()
	for rate in [20,30,60]:
		var samples := ProjectileSnapshotBuffer.new()
		samples.push(snapshot(0,0))
		samples.push(snapshot(1.0/rate,900.0/rate))
		var profile := visual.tracer_profile(samples.sample(0.5/rate).velocity.length())
		check(absf(profile.bright_length-10.8)<0.00001 and absf(profile.length-21.6)<0.00001,"tracer length independent of %dHz sampling" % rate)
	check(visual.tracer_profile(1800).bright_length==15 and visual.tracer_profile(1800).length==30,"faster tracer is capped")
	check(visual.tracer_profile(450).bright_length<visual.tracer_profile(900).bright_length,"speed scaling")
	check(ProjectileVisuals.trail_alpha(0,0.5)==1 and ProjectileVisuals.trail_alpha(0.5,0.5)==0.5 and ProjectileVisuals.trail_alpha(1,0.5)==0,"gradient head/middle/tail")
	var baseline: Array[Dictionary] = []
	for fps in [30,60,120,144]:
		var sim := DB29ProjectileSimulation.new()
		wall(sim,"hit",90)
		var feed := PresentationFeed.new()
		var renderer := ProjectileVisuals.new()
		renderer.setup(feed)
		# Deliberately vary only client parameters and FPS.
		renderer.tracer_visual_time=0.008+0.00001*fps
		renderer.tracer_max_length=10+fps
		renderer.tracer_fade_time=0.003
		var rows := sim.step([emission("fixed",1,0)])
		check(absf(sim.active_spawns()[0].position.x-30)<0.0001,"actual 900m/s authoritative step stays 30m at client %dFPS" % fps)
		var trace: Array[Dictionary] = []
		for tick in range(5):
			for row: Dictionary in rows:
				if row.reason=="spawn": feed.apply_projectile_spawn(ProjectileProjection.spawn(row))
				else: feed.apply_projectile_terminal(ProjectileProjection.terminal(row))
				trace.append(row.duplicate(true))
			for active: Dictionary in sim.active_spawns(): feed.apply_projectile_spawn(ProjectileProjection.spawn(active))
			feed.synchronize_projectile_time(sim.time_seconds)
			for frame in range(ceili(float(fps)/30)):
				renderer._process(1.0/fps)
			rows=sim.step()
		if baseline.is_empty(): baseline=trace
		else: check(trace==baseline,"authority trajectory/impact/time/lifetime unchanged at %dFPS and altered tracer parameters" % fps)
		check(trace.back().reason=="impact" and feed.live_projectiles.is_empty() and feed.projectile_buffers.is_empty(),"authority impact clears interpolation regardless of visual lag")
		check(renderer._flashes.size()<=1,"impact afterimage is not duplicated")
		feed.apply_projectile_terminal(ProjectileProjection.terminal(trace.back()))
		check(renderer._flashes.size()<=1,"duplicate impact is safe")
		feed.reset_received.emit()
		check(renderer._flashes.is_empty() and feed.projectile_buffers.is_empty(),"disconnect/reset clears render buffers")
		sim.collision.close()
		renderer.free()
	visual.free()
	print("Projectile render separation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
