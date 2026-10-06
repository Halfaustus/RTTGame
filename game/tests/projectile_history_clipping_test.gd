extends "res://tests/db29_projectile_test.gd"

func path_length(points: PackedVector3Array) -> float:
	var length := 0.0
	for index in range(1,points.size()): length+=points[index-1].distance_to(points[index])
	return length

func vertex_x_bounds(mesh: ImmediateMesh) -> Vector2:
	var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low:=INF
	var high:=-INF
	for vertex: Vector3 in vertices:
		low=minf(low,vertex.x)
		high=maxf(high,vertex.x)
	return Vector2(low,high)

func run() -> void:
	var feed:=PresentationFeed.new()
	var visual:=ProjectileVisuals.new()
	visual.setup(feed)
	root.add_child(visual)
	var initial: Dictionary={"projectile_id":"flight:1","emission_order":1,"time_seconds":0.0,"position":Vector3(0,2,0),"velocity":Vector3(900,0,0),"acceleration":GravityBallistics.GRAVITY}
	feed.apply_projectile_spawn(initial)
	feed.synchronize_projectile_time(0)
	visual._process(0)
	check(visual.mesh.get_surface_count()==0 and visual.is_processing(),"first display at spawn has no backward tail, keeps processing")
	# Longer low-speed cosmetic profile still clips to sub-metre flight history.
	feed.reset_received.emit()
	var short_slow := initial.duplicate(true)
	short_slow.projectile_id = "flight:99"
	short_slow.emission_order = 99
	short_slow.velocity = Vector3(32,0,0)
	feed.apply_projectile_spawn(short_slow)
	var short_slow_next := short_slow.duplicate(true)
	short_slow_next.time_seconds = 0.5/32
	short_slow_next.position = Vector3(0.5,2,0)
	feed.apply_projectile_spawn(short_slow_next)
	feed.synchronize_projectile_time(short_slow_next.time_seconds+feed.interpolation_delay)
	visual._process(0)
	check(visual.mesh.get_surface_count()==1,"enhanced low-speed observed history produces visible mesh")
	if visual.mesh.get_surface_count()==1:
		check(vertex_x_bounds(visual.mesh).x>=-0.000001,"enhanced low-speed live trail never passes launch")
	feed.apply_projectile_terminal({"projectile_id":"flight:99","time_seconds":short_slow_next.time_seconds,"position":short_slow_next.position,"reason":"impact"})
	check(path_length(visual._flashes[-1].points)<=0.500001 and visual._flashes[-1].length>4,"enhanced low-speed terminal clips actual path, not configured length")
	feed.reset_received.emit()
	for distance in [0.5,0.75,1.0]:
		feed.reset_received.emit()
		feed.apply_projectile_spawn(initial)
		var next:=initial.duplicate()
		next.time_seconds=float(distance)/900
		next.position=Vector3(distance,2,0)
		feed.apply_projectile_spawn(next)
		feed.synchronize_projectile_time(next.time_seconds+feed.interpolation_delay)
		visual._process(0)
		var points: PackedVector3Array=feed.projectile_buffers["flight:1"].trail_points(next.position,next.time_seconds,30)
		check(path_length(points)<=distance+0.00001 and points[-1]==initial.position,"short live tail ends at spawn and is bounded by travelled path")
		check(vertex_x_bounds(visual.mesh).x>=-0.000001 and vertex_x_bounds(visual.mesh).y<=distance+0.000001,"rendered short mesh does not pass muzzle")
		var sim:=DB29ProjectileSimulation.new()
		wall(sim,"near",distance+0.01)
		var actual:=sim.step([emission("short",1,0)])
		check(actual.size()==2 and actual[-1].reason=="impact","actual sub-step obstacle collision")
		feed.reset_received.emit()
		feed.apply_projectile_spawn(ProjectileProjection.spawn(actual[0]))
		feed.apply_projectile_terminal(ProjectileProjection.terminal(actual[-1]))
		visual._process(0)
		var terminal_points: PackedVector3Array=visual._flashes[0].points
		check(path_length(terminal_points)<=float(actual[-1].distance_m)+0.00001,"same-batch terminal path clipped to actual distance")
		check(vertex_x_bounds(visual.mesh).x>=-0.000001 and vertex_x_bounds(visual.mesh).y<=actual[-1].position.x+0.000001,"terminal mesh between actual spawn and impact")
		check(visual._flashes[0].remaining==ProjectileVisuals.TERMINAL_FLASH_SECONDS,"terminal duration remains 0.12s")
		check(sim.collision.profile.casts==0,"authoritative point collision remains unchanged")
		sim.collision.close()
	# Near-unit obstruction uses the actual shared collision frame, not VFX queries.
	var motion:=ProjectileUnitMotion.new()
	var body: Dictionary={"center":Vector3(1,2,0),"extents":Vector3.ONE*0.5,"basis":Basis.IDENTITY,"team_id":1,"unit_type":UnitDefinition.UnitType.INFANTRY}
	check(motion.configure(0,{2:body},{2:body}),"near unit authoritative frame initialized")
	var blocked:=DB29ProjectileSimulation.new()
	var contact:=blocked.step([emission("near_unit",1,0)],motion)
	check(contact.size()==2 and contact[-1].hit_unit_id==2 and absf(contact[-1].position.x-0.5)<0.000001,"nearby unit causes actual half-metre impact")
	feed.reset_received.emit()
	feed.apply_projectile_spawn(ProjectileProjection.spawn(contact[0]))
	feed.apply_projectile_terminal(ProjectileProjection.terminal(contact[-1]))
	visual._process(0)
	check(vertex_x_bounds(visual.mesh).x>=-0.000001 and path_length(visual._flashes[0].points)<=0.500001,"unit-impact afterimage remains between source and authoritative hit")
	blocked.collision.close()
	# Zero-life and boundary termination use the same geometric clipping.
	for width in [0.0,0.5]:
		var sim:=DB29ProjectileSimulation.new()
		sim.configure_bounds(Rect2(0.001 if width==0 else 0.0,-1,maxf(width,0.1),2))
		var actual:=sim.step([emission("edge",1,0)])
		feed.reset_received.emit()
		feed.apply_projectile_spawn(ProjectileProjection.spawn(actual[0]))
		feed.apply_projectile_terminal(ProjectileProjection.terminal(actual[-1]))
		visual._process(0)
		if width==0:
			check(actual[-1].reason=="battlefield_exit" and visual._flashes.is_empty() and visual.mesh.get_surface_count()==0,"zero-life exit has no artificial tail")
		else:
			check(actual[-1].reason=="battlefield_exit" and path_length(visual._flashes[0].points)<=width+0.00001,"immediate map exit never draws before origin")
		sim.collision.close()
	feed.reset_received.emit()
	feed.apply_projectile_spawn(initial)
	var current:=initial.duplicate()
	current.time_seconds=0.2
	current.position=Vector3(180,2,0)
	feed.apply_projectile_spawn(current)
	feed.synchronize_projectile_time(0.25)
	visual._process(0)
	check(absf(visual.mesh.get_aabb().size.x-21.6)<0.0001,"normal distance retains full configured visual length")
	var curved:=ProjectileSnapshotBuffer.new()
	for time in [0.0,0.5,1.0,1.5,2.0]:
		var snapshot:=initial.duplicate()
		snapshot.time_seconds=time
		snapshot.position=Vector3(10*time,10*time-5*time*time,0)
		snapshot.velocity=Vector3(10,10-10*time,0)
		curved.push(snapshot)
	var curved_tail:=curved.trail_points(Vector3(20,0,0),2,30)
	check(curved_tail[-1]==Vector3.ZERO and curved_tail.has(Vector3(10,5,0)),"gravity tail follows historical bend, not current tangent extended before spawn")
	check(path_length(curved_tail)>20 and path_length(curved_tail)<30,"curved history is not replaced by endpoint straight distance")
	var late:=ProjectileSnapshotBuffer.new()
	late.push(current)
	check(late.trail_points(current.position,0.2,30).size()==1,"late join invents no pre-join spawn history")
	for index in range(1,12):
		var snapshot:=current.duplicate()
		snapshot.time_seconds=0.2+index/30.0
		snapshot.position.x=180+index*30
		late.push(snapshot)
	check(late.snapshots.size()==8 and absf(path_length(late.trail_points(late.snapshots.back().position,late.snapshots.back().time_seconds,21.6))-21.6)<0.001,"bounded snapshot eviction retains normal-length tail")
	var extra:=initial.duplicate()
	extra.projectile_id="flight:2"
	extra.emission_order=2
	feed.apply_projectile_spawn(extra)
	var extra_current:=current.duplicate()
	extra_current.projectile_id="flight:2"
	extra_current.emission_order=2
	feed.apply_projectile_spawn(extra_current)
	visual._process(0)
	check(visual.mesh.get_surface_count()==1 and feed.live_projectiles.size()==2,"concurrent flights still share one mesh")
	check(ProjectileProjection.spawn(initial).size()==6,"public projection whitelist unchanged")
	var replay=load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	replay.replay_mode=true
	replay.presentation_source=PresentationFeed.new()
	root.add_child(replay)
	check(replay._projectile_visuals==null,"Replay world does not attach realtime projectile VFX")
	replay.free()
	feed.reset_received.emit()
	check(visual.mesh.get_surface_count()==0,"disconnect resets clipped terminal/live geometry")
	visual.free()
	print("Projectile history clipping: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
