class_name ProjectileUnitMotion
extends RefCounted

# Shared authoritative snapshots and broad phase for ONE 30Hz interval.
# No live UnitState references, per-projectile rebuild or per-query field scan.
const CELL_METERS := 16.0 # Technical spatial partition, never a unit parameter.
const TIME_TOLERANCE := 0.00000001 # Global collision-time precision, seconds.
const SHAPE_ERROR_METERS := 0.001 # C-authorized conservative spatial tolerance.
var time_seconds := 0.0
var records: Dictionary = {}
var cells: Dictionary = {}
var failure_reason := ""
var ready := false
var profile := {"candidates":0,"precise_tests":0,"queries":0}

static func capture(units: Dictionary) -> Dictionary:
	var result := {}
	for unit: UnitState in units.values():
		if unit.health <= 0.0: continue
		var center := unit.position
		var extents := unit.hitbox_extents()
		var basis := Basis(Vector3.UP,unit.yaw)
		if unit.unit_type() == UnitDefinition.UnitType.INFANTRY and not unit.members.is_empty():
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for member: SoldierState in unit.members:
				if member.health <= 0.0: continue
				low = low.min(member.position-member.hitbox_half_extents)
				high = high.max(member.position+member.hitbox_half_extents)
			center = (low+high)*0.5
			extents = (high-low)*0.5
			basis = Basis.IDENTITY # Existing shared squad hitbox, not soldier bodies.
		result[unit.unit_id] = {"center":center,"extents":extents,"basis":basis,"team_id":unit.team_id,"unit_type":unit.unit_type()}
	return result

func configure(start: float,before: Dictionary,after: Dictionary) -> bool:
	ready = false
	records.clear()
	cells.clear()
	failure_reason = ""
	if not is_finite(start) or before.size() != after.size(): return _fail("unit_motion_topology_changed")
	time_seconds = start
	for id: Variant in before:
		if not after.has(id): return _fail("unit_motion_topology_changed")
		var a: Dictionary = before[id]
		var b: Dictionary = after[id]
		if not _valid(a) or not _valid(b): return _fail("invalid_unit_motion")
		if a.team_id != b.team_id or a.unit_type != b.unit_type: return _fail("unit_motion_topology_changed")
		var box := AABB(-a.extents,2.0*a.extents)
		var start_box: AABB = Transform3D(a.basis,a.center)*box
		var end_box: AABB = Transform3D(b.basis,b.center)*box
		var bounds := start_box.merge(end_box)
		var changing: bool = not a.basis.is_equal_approx(b.basis) or not a.extents.is_equal_approx(b.extents)
		var radius: float = maxf(a.extents.length(),b.extents.length())
		if changing:
			# Covers all intermediate orientations, not just endpoint boxes.
			bounds = AABB(a.center-Vector3.ONE*radius,Vector3.ONE*radius*2).merge(AABB(b.center-Vector3.ONE*radius,Vector3.ONE*radius*2))
		var angle: float = a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
		var shape_travel: float = radius*angle+(b.extents-a.extents).length()
		var record := {"unit_id":int(id),"object_id":"unit:"+str(id),"object_category":"unit","team_id":a.team_id,"unit_type":a.unit_type,"start":a.center,"end":b.center,"extents":a.extents,"end_extents":b.extents,"inverse":a.basis.inverse(),"basis":a.basis,"end_basis":b.basis,"bounds":bounds,"changing":changing,"shape_travel":shape_travel}
		records[id] = record
		for cell: Vector3i in _covered(bounds):
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(id)
	ready = true
	return true

func sweep(start: Vector3,end: Vector3,at: float,duration: float,source_unit: int,limit: float = 1.0,ignored: Dictionary = {}) -> Dictionary:
	profile.queries += 1
	if not ready: return {"failure":failure_reason if not failure_reason.is_empty() else "unit_motion_unconfigured"}
	var h := GravityBallistics.STEP_SECONDS
	if not start.is_finite() or not end.is_finite() or not is_finite(at) or not is_finite(duration) or duration < 0.0 or at < time_seconds-TIME_TOLERANCE or at+duration > time_seconds+h+TIME_TOLERANCE: return {"failure":"motion_interval_mismatch"}
	if duration == 0.0: return {}
	var shortened := start.lerp(end,limit)
	var bounds := AABB(start,Vector3.ZERO).expand(shortened)
	var candidates := {}
	for cell: Vector3i in _covered(bounds):
		for id: Variant in cells.get(cell,[]):
			if int(id) != source_unit and not ignored.has(id): candidates[id] = true
	var best := {}
	for id: Variant in candidates:
		var record: Dictionary = records[id]
		profile.candidates += 1
		if not _overlaps(bounds,record.bounds): continue
		profile.precise_tests += 1
		var t0 := record_fraction(record,at)
		var t1 := record_fraction(record,at+duration*limit)
		var hit := _changing_box(record,start,shortened,t0,t1) if record.changing else _box(record.inverse*(start-record.start.lerp(record.end,t0)),record.inverse*(shortened-record.start.lerp(record.end,t1)),record.extents)
		if hit.is_empty(): continue
		hit.fraction *= limit
		if not record.changing: hit.normal = record.basis*hit.normal
		hit.point = start.lerp(end,hit.fraction)
		hit.merge({"object_id":record.object_id,"object_category":"unit","unit_id":record.unit_id,"unit_type":record.unit_type,"team_id":record.team_id})
		if best.is_empty() or float(hit.fraction)*duration < float(best.fraction)*duration-TIME_TOLERANCE or (absf(float(hit.fraction-best.fraction))*duration <= TIME_TOLERANCE and hit.object_id < best.object_id): best = hit
	return best

# Explicit event-driven removal, preserving the configured interval and other
# shared samples. The source unit's already-fired projectiles remain independent.
func remove_unit(id: int) -> void:
	if not records.has(id): return
	for cell: Vector3i in _covered(records[id].bounds):
		if not cells.has(cell): continue
		cells[cell].erase(id)
		if cells[cell].is_empty(): cells.erase(cell)
	records.erase(id)

func record_fraction(record: Dictionary,at: float) -> float:
	var start: float = record.get("start_time",time_seconds)
	var duration := time_seconds+GravityBallistics.STEP_SECONDS-start
	return clampf((at-start)/duration,0.0,1.0) if duration > 0 else 1.0

func replace_unit(id: int,at: float,before: Dictionary,after: Dictionary) -> bool:
	var sample := ProjectileUnitMotion.new()
	if not sample.configure(at,before,after): return false
	remove_unit(id)
	if not sample.records.has(id): return true
	var record: Dictionary = sample.records[id]
	record.start_time = at
	records[id] = record
	for cell: Vector3i in _covered(record.bounds):
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(id)
	return true

static func _changing_box(record: Dictionary,start: Vector3,end: Vector3,t0: float,t1: float) -> Dictionary:
	# Each local segment uses its midpoint shape. Padding covers the maximum
	# endpoint-to-midpoint surface travel; never increases projectile radius.
	var travel: float = record.shape_travel*(t1-t0)
	# Euclidean corner padding, not just each-axis padding, is <= 1 mm.
	var count := maxi(1,ceili(travel*sqrt(3.0)/SHAPE_ERROR_METERS))
	var padding := travel/(2.0*count)
	for index: int in count:
		var f0 := float(index)/count
		var f1 := float(index+1)/count
		var a := lerpf(t0,t1,f0)
		var b := lerpf(t0,t1,f1)
		var middle := (a+b)*0.5
		var basis: Basis = record.basis.slerp(record.end_basis,middle)
		var inverse := basis.inverse()
		var extents: Vector3 = record.extents.lerp(record.end_extents,middle)+Vector3.ONE*padding
		var hit := _box(inverse*(start.lerp(end,f0)-record.start.lerp(record.end,a)),inverse*(start.lerp(end,f1)-record.start.lerp(record.end,b)),extents)
		if not hit.is_empty():
			hit.fraction = lerpf(f0,f1,float(hit.fraction))
			hit.normal = basis*hit.normal
			return hit
	return {}

static func _box(start: Vector3,end: Vector3,extents: Vector3) -> Dictionary:
	var enter := 0.0
	var leave := 1.0
	var normal := Vector3.ZERO
	var direction := end-start
	for axis in range(3):
		if direction[axis] == 0.0:
			if start[axis] < -extents[axis] or start[axis] > extents[axis]: return {}
			continue
		var near := (-extents[axis]-start[axis])/direction[axis]
		var far := (extents[axis]-start[axis])/direction[axis]
		var sign_value := -1.0
		if near > far:
			var swap := near
			near = far
			far = swap
			sign_value = 1.0
		if near > enter:
			enter = near
			normal = Vector3.ZERO
			normal[axis] = sign_value
		leave = minf(leave,far)
		if enter > leave: return {}
	return {"fraction":enter,"normal":normal}

static func _covered(bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var low := Vector3i((bounds.position/CELL_METERS).floor())
	var high := Vector3i((bounds.end/CELL_METERS).floor())
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1): result.append(Vector3i(x,y,z))
	return result

static func _overlaps(a: AABB,b: AABB) -> bool:
	return a.position.x <= b.end.x and a.end.x >= b.position.x and a.position.y <= b.end.y and a.end.y >= b.position.y and a.position.z <= b.end.z and a.end.z >= b.position.z

static func _valid(value: Dictionary) -> bool:
	for field: String in ["center","extents","basis","team_id","unit_type"]:
		if not value.has(field): return false
	return value.center is Vector3 and value.extents is Vector3 and value.basis is Basis and value.center.is_finite() and value.extents.is_finite() and value.extents.x > 0 and value.extents.y > 0 and value.extents.z > 0 and value.basis.is_finite() and value.basis.determinant() > 0 and value.basis.is_equal_approx(value.basis.orthonormalized())

func _fail(reason: String) -> bool:
	failure_reason = reason
	records.clear()
	cells.clear()
	return false
