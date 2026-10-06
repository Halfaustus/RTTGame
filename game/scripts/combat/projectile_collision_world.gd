class_name ProjectileCollisionWorld
extends RefCounted

# Dedicated authoritative query space. No client scene/visual/body is consulted.
var space: RID
var bodies: Dictionary = {}
var objects: Dictionary = {}
var shapes: Dictionary = {}
var query := PhysicsShapeQueryParameters3D.new()
var profile := {"casts":0,"rest_queries":0,"ray_queries":0,"body_updates":0,"query_allocations":1}

func _init() -> void:
	space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space,true)

func close() -> void:
	for id: String in bodies.keys(): remove(id)
	if space.is_valid(): PhysicsServer3D.free_rid(space)
	space = RID()
	shapes.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted teardown cannot call a virtual method on its dying instance.
		for entry: Dictionary in bodies.values():
			PhysicsServer3D.free_rid(entry.body)
			PhysicsServer3D.free_rid(entry.shape)
		if space.is_valid(): PhysicsServer3D.free_rid(space)

func remove(id: String) -> void:
	if not bodies.has(id): return
	var entry: Dictionary = bodies[id]
	objects.erase(entry.body)
	PhysicsServer3D.free_rid(entry.body)
	PhysicsServer3D.free_rid(entry.shape)
	bodies.erase(id)

func box(id: String, category: String, half_extents: Vector3, transform: Transform3D, unit_id: int = 0, team_id: int = 0, blocks: bool = true) -> void:
	blocks = blocks and category in ["unit","terrain","obstacle","house"]
	if not bodies.has(id):
		var body := PhysicsServer3D.body_create()
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape,half_extents)
		PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body,shape)
		PhysicsServer3D.body_set_space(body,space)
		bodies[id] = {"body":body,"shape":shape,"extents":half_extents,"transform":transform}
	var entry: Dictionary = bodies[id]
	if entry.extents != half_extents:
		PhysicsServer3D.shape_set_data(entry.shape,half_extents)
		entry.extents = half_extents
	PhysicsServer3D.body_set_collision_layer(entry.body,(2 if category == "unit" else 1) if blocks else 0)
	PhysicsServer3D.body_set_collision_mask(entry.body,0)
	if entry.transform != transform or not objects.has(entry.body):
		PhysicsServer3D.body_set_state(entry.body,PhysicsServer3D.BODY_STATE_TRANSFORM,transform)
		entry.transform = transform
		profile.body_updates += 1
	objects[entry.body] = {"object_id":id,"object_category":category,"unit_id":unit_id,"team_id":team_id}

func sync_units(units: Dictionary) -> void:
	var live := {}
	for state: UnitState in units.values():
		if state.health <= 0: continue # No corpse physics bodies.
		var id := "unit:"+str(state.unit_id)
		live[id] = true
		var center := state.position
		var extents := state.hitbox_extents()
		var basis := Basis(Vector3.UP,state.yaw)
		if state.unit_type() == UnitDefinition.UnitType.INFANTRY and not state.members.is_empty():
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for member: SoldierState in state.members:
				if member.health <= 0: continue
				low = low.min(member.position-member.hitbox_half_extents)
				high = high.max(member.position+member.hitbox_half_extents)
			center = (low+high)*0.5
			extents = (high-low)*0.5
			basis = Basis.IDENTITY
		box(id,"unit",extents,Transform3D(basis,center),state.unit_id,state.team_id)
		objects[bodies[id].body]["unit_type"] = state.unit_type()
	for id: String in bodies.keys():
		if id.begins_with("unit:") and not live.has(id): remove(id)

func initialize_map(map: PrototypeMapDefinition, movement: MovementConfig) -> void:
	var size := movement.maximum_xz-movement.minimum_xz
	var center := (movement.maximum_xz+movement.minimum_xz)*0.5
	box("ground","terrain",Vector3(size.x/2,0.05,size.y/2),Transform3D(Basis.IDENTITY,Vector3(center.x,movement.ground_height-0.05,center.y)))
	for index: int in map.obstacles.size():
		var rectangle := map.obstacles[index]
		box("obstacle:"+str(index),"obstacle",Vector3(rectangle.size.x/2,map.obstacle_height/2,rectangle.size.y/2),Transform3D(Basis.IDENTITY,Vector3(rectangle.get_center().x,movement.ground_height+map.obstacle_height/2,rectangle.get_center().y)))

func exclusions(source_unit: int, houses: Array[int]) -> Array[RID]:
	var result: Array[RID] = []
	var ids := ["unit:"+str(source_unit)]
	for id: int in houses:
		if id > 0: ids.append("house:"+str(id))
	for id: String in ids:
		if bodies.has(id): result.append(bodies[id].body)
	return result

func sweep(start: Vector3, end: Vector3, radius: float, exclude: Array[RID], mask: int = 3) -> Dictionary:
	if not space.is_valid(): return {"failure":"physics_space_unavailable"}
	var direct := PhysicsServer3D.space_get_direct_state(space)
	if direct == null: return {"failure":"physics_space_unavailable"}
	if radius == 0:
		var ray := PhysicsRayQueryParameters3D.create(start,end,mask,exclude)
		ray.hit_from_inside = true
		profile.ray_queries += 1
		var hit := direct.intersect_ray(ray)
		if hit.is_empty(): return {}
		var result: Dictionary = objects.get(hit.rid,{}).duplicate()
		result.merge({"point":hit.position,"normal":hit.normal,"fraction":start.distance_to(hit.position)/maxf(start.distance_to(end),0.000001)})
		return result
	if not shapes.has(radius):
		var shape := SphereShape3D.new()
		shape.radius = radius
		shapes[radius] = shape
		profile.query_allocations += 1
	query.shape = shapes[radius]
	query.transform = Transform3D(Basis.IDENTITY,start)
	query.motion = Vector3.ZERO
	query.collision_mask = mask
	query.exclude = exclude
	query.margin = 0
	profile.rest_queries += 1
	var hit := direct.get_rest_info(query) # cast_motion ignores initial overlaps.
	var fraction := 0.0
	if hit.is_empty():
		query.motion = end-start
		profile.casts += 1
		var fractions := direct.cast_motion(query)
		if fractions.size() != 2 or fractions[0] >= 1: return {}
		fraction = fractions[1]
		query.transform.origin = start+(end-start)*fraction
		query.motion = Vector3.ZERO
		query.margin = Prototype05FConfig.CONTACT_EPSILON_M
		profile.rest_queries += 1
		hit = direct.get_rest_info(query)
		if hit.is_empty(): return {"failure":"contact_resolution_failed"} # Never silently tunnel.
	var result: Dictionary = objects.get(hit.rid,{}).duplicate()
	result.merge({"point":hit.point,"normal":hit.normal,"fraction":fraction})
	return result

func fire_clear(weapon: RuntimeWeaponInstance, origin: Vector3, point: Vector3, inputs: Dictionary) -> bool:
	if weapon.target.kind == AttackTarget.Kind.FORCED_GROUND: return true
	var hit := sweep(origin,point,weapon.definition.projectile.radius_m if weapon.definition.projectile != null else 0,exclusions(weapon.owner_state().unit_id,[int(inputs.get("house_id",0)),int(inputs.get("target_house_id",0))]),2)
	return not hit.has("failure") and (hit.is_empty() or hit.get("team_id",-1) != weapon.owner_state().team_id)

# DB29 static point query. Only overlap/tied hits require additional rays;
# there is no full static-body scan. Keep the legacy sphere/ray API unchanged.
func static_point_sweep(start: Vector3,end: Vector3,exclude: Array[RID],seconds: float) -> Dictionary:
	var best := sweep(start,end,0.0,exclude,1)
	if best.is_empty() or best.has("failure"): return best
	var first_fraction: float = best.fraction
	var endpoint := start.lerp(end,minf(1.0,first_fraction+ProjectileUnitMotion.TIME_TOLERANCE/maxf(seconds,ProjectileUnitMotion.TIME_TOLERANCE)))
	var ignored := exclude.duplicate()
	var current := best
	while not current.is_empty():
		var id: String = current.object_id
		if not bodies.has(id) or ignored.has(bodies[id].body): return {"failure":"static_contact_identity_invalid"}
		ignored.append(bodies[id].body)
		current = sweep(start,endpoint,0.0,ignored,1)
		if current.has("failure"): return current
		if current.is_empty(): break
		current.fraction = start.distance_to(current.point)/maxf(start.distance_to(end),0.000001)
		if absf(float(current.fraction-first_fraction))*seconds > ProjectileUnitMotion.TIME_TOLERANCE: break
		if current.object_id < best.object_id: best = current
	return best
