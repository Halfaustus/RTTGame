extends SceneTree

# Full-graph reference retains the pre-optimization geometry predicates.
# Compare local updates against it, rather than testing implementation details only.
class ReferenceGrid extends StaticNavigationGrid:
	func dynamic_segment_clear(start: Vector3, end: Vector3) -> bool:
		var a := Vector2(start.x,start.z)
		var b := Vector2(end.x,end.z)
		for index: int in _dynamic_centers.size():
			var center := Vector2(_dynamic_centers[index].x,_dynamic_centers[index].z)
			if Geometry2D.get_closest_point_to_segment(center,a,b).distance_to(center) < _dynamic_radii[index]-POSITION_EPSILON: return false
		return true

	func configure_dynamic(centers: Array[Vector3], radii: Array[float]) -> void:
		for edge: Vector2i in _disabled_edges: _routes.connect_points(edge.x,edge.y)
		_disabled_edges.clear()
		_dynamic_centers = centers.duplicate()
		_dynamic_radii = radii.duplicate()
		for id: int in _routes.get_point_ids():
			var point := _routes.get_point_position(id)
			_routes.set_point_disabled(id,not _dynamic_clear(Vector3(point.x,0,point.y)))
			for next: int in _routes.get_point_connections(id):
				if next <= id: continue
				var other := _routes.get_point_position(next)
				if not dynamic_segment_clear(Vector3(point.x,0,point.y),Vector3(other.x,0,other.y)):
					_disabled_edges.append(Vector2i(id,next))
		for edge: Vector2i in _disabled_edges: _routes.disconnect_points(edge.x,edge.y)

const CONFIG = preload("res://data/prototype_movement.tres")
const INF = preload("res://data/unit_stationary.tres")
const VEH = preload("res://data/unit_mobile.tres")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL movement performance: " + label)

func equivalent(local: StaticNavigationGrid, reference: StaticNavigationGrid, label: String) -> void:
	var equal := true
	for id: int in reference._routes.get_point_ids():
		equal = equal and local._routes.is_point_disabled(id) == reference._routes.is_point_disabled(id)
		var a := local._routes.get_point_connections(id)
		var b := reference._routes.get_point_connections(id)
		a.sort()
		b.sort()
		equal = equal and a == b
	check(equal,label)

func run() -> void:
	var config: MovementConfig = CONFIG.duplicate(true)
	config.minimum_xz = Vector2.ZERO
	config.maximum_xz = Vector2(12,12)
	var map := PrototypeMapDefinition.new()
	map.obstacles = [Rect2(5,5,2,2)]
	var local := StaticNavigationGrid.new()
	var reference := ReferenceGrid.new()
	check(local.initialize(config,map) and reference.initialize(config,map),"oracle grids initialize")
	# Fixed seed exercises centers between cells, overlapping circles, map edges,
	# variable radii and alternating configurations, without regenerating fixtures.
	var random := RandomNumberGenerator.new()
	random.seed = 50503
	for sample: int in 24:
		var centers: Array[Vector3] = []
		var radii: Array[float] = []
		for index: int in sample % 6:
			centers.append(Vector3(random.randf_range(-1,13),0,random.randf_range(-1,13)))
			radii.append(random.randf_range(0.1,2.5))
		local.configure_dynamic(centers,radii)
		reference.configure_dynamic(centers,radii)
		equivalent(local,reference,"node/edge occupancy matches full scan " + str(sample))
		var queries_equal := true
		for segment: int in 40:
			var a := Vector3(random.randf_range(-1,13),0,random.randf_range(-1,13))
			var b := Vector3(random.randf_range(-1,13),0,random.randf_range(-1,13))
			queries_equal = queries_equal and local.dynamic_segment_clear(a,b) == reference.dynamic_segment_clear(a,b)
			queries_equal = queries_equal and local.dynamic_segment_clear(a,a) == reference.dynamic_segment_clear(a,a)
		check(queries_equal,"spatial buckets match brute-force point/swept predicates " + str(sample))
		# Reusing an identical request must not change graph or paths.
		local.configure_dynamic(centers,radii)
		equivalent(local,reference,"identical configuration stable " + str(sample))
	local.configure_dynamic([],[])
	reference.configure_dynamic([],[])
	equivalent(local,reference,"clearing occupancy restores all touched nodes/edges")
	var id: int = local._routes.get_point_ids()[0]
	var next: int = local._routes.get_point_connections(id)[0]
	var middle := (local._routes.get_point_position(id)+local._routes.get_point_position(next))*0.5
	var circles: Array[Vector3] = [Vector3(middle.x,0,middle.y)]
	var radii: Array[float] = [0.1]
	local.configure_dynamic(circles,radii)
	reference.configure_dynamic(circles,radii)
	equivalent(local,reference,"edge crossing detected even when both endpoints are outside circle")
	check(not local._routes.are_points_connected(id,next),"small circle removes crossed edge")
	circles[0] = Vector3(10,0,10)
	check(local._dynamic_centers[0] != circles[0],"caller mutation cannot silently change cached occupancy")
	local.configure_dynamic(circles,[1.5])
	reference.configure_dynamic(circles,[1.5])
	equivalent(local,reference,"moved blocker and radius update invalidate old occupancy")
	local.initialize(config,map)
	reference.initialize(config,map)
	local.configure_dynamic([],[])
	equivalent(local,reference,"map rebuild clears occupancy history")
	local.profile = {"enabled":true}
	local.configure_dynamic([],[])
	check(local.profile.get("graph_points_examined",0) == 0 and local.profile.get("graph_edges_examined",0) == 0,"empty unchanged occupancy does not traverse graph")
	local.configure_dynamic([Vector3(2,0,2)],[1.0])
	check(local.profile.get("graph_points_examined",0) < local._routes.get_point_count(),"one blocker only examines nearby graph points")
	local.configure_dynamic([Vector3(2,0,2),Vector3(9,0,9)],[1.0,0.5])
	reference.configure_dynamic([Vector3(2,0,2),Vector3(9,0,9)],[1.0,0.5])
	equivalent(local,reference,"cached circle combines with new blocker")
	check(local.profile.get("circle_cache_hits",0) > 0,"unchanged individual circle geometry is reused")
	local.configure_dynamic([Vector3(2,0,2),Vector3(9.1,0,9)],[1.00000001,0.5])
	reference.configure_dynamic([Vector3(2,0,2),Vector3(9.1,0,9)],[1.00000001,0.5])
	equivalent(local,reference,"precise changed radius and moved second circle do not reuse stale geometry")
	check(local._circle_overlays.size() == 2,"circle history is bounded by last nonempty request")

	var simulation := MovementSimulation.new(CONFIG)
	check(simulation.initialize_navigation(),"scale simulation initializes")
	var squads: Array[UnitState] = []
	var accepted := 0
	for index: int in 48:
		var squad := UnitState.new(index+1,42,Vector3(10,0.5,100))
		squad.configure(1,INF)
		simulation.add_unit(squad)
		squads.append(squad)
		if simulation.request_move(squad.unit_id,42,Vector3(10,0,110)).is_empty(): accepted += 1
	check(accepted == 48,"all 48 overlapping squads accept owned commands")
	for tick: int in 240: simulation.advance(1.0/60.0)
	var followed := true
	for squad: UnitState in squads:
		followed = followed and squad.position.distance_to(Vector3(10,0.5,110)) < 0.001
		for member: SoldierState in squad.members:
			var target := squad.position+squad.formation_slots[member.formation_slot].rotated(Vector3.UP,squad.yaw)
			followed = followed and member.position.distance_to(target) < 0.001 and member.health > 0
	check(followed,"48 real squads/384 Soldiers reach original targets and valid formation slots")
	var vehicle := UnitState.new(100,42,Vector3(10,0.5,110))
	vehicle.configure(1,VEH)
	simulation.add_unit(vehicle)
	check(simulation.translation_clear(vehicle,vehicle.position,vehicle.position+Vector3.RIGHT),"overlapping Soldiers still do not block vehicles")
	var blocker := UnitState.new(101,42,Vector3(12,0.5,110))
	blocker.configure(1,VEH)
	simulation.add_unit(blocker)
	check(not simulation.translation_clear(vehicle,vehicle.position,Vector3(14,0.5,110)),"swept collision still prevents tunneling")
	var vehicle_nav := simulation.navigation_for(vehicle)
	check(not vehicle_nav.is_position_walkable(blocker.position),"vehicle query sees live blocker")
	check(simulation.navigation_for(squads[0]).is_position_walkable(blocker.position),"shared grid switches back to nonblocking infantry")
	check(not simulation.navigation_for(vehicle).is_position_walkable(blocker.position),"vehicle query restores occupancy after infantry")
	blocker.position = Vector3(20,0.5,110)
	check(simulation.navigation_for(vehicle).is_position_walkable(Vector3(12,0.5,110)),"external authoritative blocker move is seen by next query")
	blocker.health = 0
	check(simulation.navigation_for(vehicle).is_position_walkable(blocker.position),"dead blocker immediately leaves path occupancy")
	blocker.health = blocker.maximum_health
	simulation.remove_unit(101)
	check(simulation.navigation_for(vehicle).is_position_walkable(blocker.position),"removed blocker leaves path occupancy")
	check(simulation.request_move(100,99,Vector3(20,0,110)) == "not owner","server command ownership unchanged")
	var traffic := MovementSimulation.new(CONFIG)
	traffic.initialize_navigation()
	var vehicles: Array[UnitState] = []
	accepted = 0
	for index: int in 48:
		var state := UnitState.new(index+1,42,Vector3(-16+(index%24)*2,0.5,98+(index/24)*4))
		state.configure(1,VEH)
		state.yaw = PI
		traffic.add_unit(state)
		vehicles.append(state)
	for state: UnitState in vehicles:
		if traffic.request_move(state.unit_id,42,Vector3(state.position.x,0,state.position.z+12)).is_empty(): accepted += 1
	check(accepted == 48,"48 vehicles retain legal independent path requests")
	var separated := true
	for tick: int in 180:
		traffic.advance(1.0/60.0)
		for a: int in vehicles.size():
			for b: int in range(a+1,vehicles.size()):
				separated = separated and vehicles[a].position.distance_to(vehicles[b].position) >= vehicles[a].movement_radius()+vehicles[b].movement_radius()-0.00001
	check(separated,"48 simultaneously moving vehicles never overlap during sampled ticks")
	print("Movement performance: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
