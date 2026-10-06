class_name ProjectileSnapshotBuffer
extends RefCounted

# Client render proxy. Network positions are immutable copies of authority samples.
const CAPACITY := 8
var max_extrapolation_time := 0.05
var correction_seconds := 0.05
var snap_distance := 30.0
var snapshots: Array[Dictionary] = []
var _path_distances: Array[float] = []
var _known_path_distance := 0.0
var visual_position := Vector3.ZERO
var visual_velocity := Vector3.ZERO
var _initialized := false

func push(state: Dictionary) -> void:
	if not snapshots.is_empty() and float(state.time_seconds) <= float(snapshots.back().time_seconds): return
	if not snapshots.is_empty(): _known_path_distance += snapshots.back().position.distance_to(state.position)
	snapshots.append(state.duplicate(true))
	_path_distances.append(_known_path_distance)
	if snapshots.size() > CAPACITY:
		snapshots.pop_front()
		_path_distances.pop_front()

func sample(render_time: float) -> Dictionary:
	if snapshots.is_empty(): return {}
	var first: Dictionary = snapshots.front()
	if render_time <= float(first.time_seconds): return {"position":first.position,"velocity":first.velocity}
	for index in range(1,snapshots.size()):
		var a: Dictionary = snapshots[index-1]
		var b: Dictionary = snapshots[index]
		if render_time <= float(b.time_seconds):
			var alpha := clampf((render_time-float(a.time_seconds))/(float(b.time_seconds)-float(a.time_seconds)),0,1)
			return {"position":a.position.lerp(b.position,alpha),"velocity":a.velocity.lerp(b.velocity,alpha)}
	var latest: Dictionary = snapshots.back()
	var elapsed := clampf(render_time-float(latest.time_seconds),0,max_extrapolation_time)
	var acceleration: Vector3 = latest.get("acceleration",Vector3.ZERO)
	return {"position":latest.position+latest.velocity*elapsed+acceleration*(0.5*elapsed*elapsed),"velocity":latest.velocity+acceleration*elapsed}

func render(render_time: float,delta: float) -> Dictionary:
	var target := sample(render_time)
	if target.is_empty(): return target
	# Normal interpolation is exact. Smooth only recovery from a prediction error.
	var was_extrapolated := _initialized and _last_render_time > _last_latest_time
	if was_extrapolated and float(snapshots.back().time_seconds) > _last_latest_time and delta > 0:
		_correction_offset = visual_position+visual_velocity*delta-target.position
	if not _initialized or _correction_offset.length() > snap_distance: _correction_offset = Vector3.ZERO
	_correction_offset *= exp(-maxf(0,delta)/maxf(0.000001,correction_seconds))
	visual_position = target.position+_correction_offset
	visual_velocity = target.velocity
	_initialized = true
	_last_render_time = render_time
	_last_latest_time = float(snapshots.back().time_seconds)
	return {"position":visual_position,"velocity":visual_velocity}

var _last_render_time := 0.0
var _last_latest_time := 0.0
var _correction_offset := Vector3.ZERO

# Draw only observed trajectory history. Late join starts at its first sample;
# missing earlier history is deliberately not reconstructed or exposed.
func trail_points(head: Vector3, at: float, maximum_length: float, terminal: bool = false) -> PackedVector3Array:
	var points := PackedVector3Array([head])
	if snapshots.is_empty(): return points
	var budget := _known_path_distance
	if terminal:
		budget += head.distance_to(snapshots.back().position)
	else:
		for index in range(snapshots.size()):
			if at <= float(snapshots[index].time_seconds):
				budget = _path_distances[index]
				if index == 0: budget = 0.0
				else:
					var alpha := clampf((at-float(snapshots[index-1].time_seconds))/(float(snapshots[index].time_seconds)-float(snapshots[index-1].time_seconds)),0,1)
					budget = lerpf(_path_distances[index-1],_path_distances[index],alpha)
				break
	var remaining := minf(maxf(0,maximum_length),budget)
	for index in range(snapshots.size()-1,-1,-1):
		if float(snapshots[index].time_seconds) >= at and not terminal: continue
		if float(snapshots[index].time_seconds) > at: continue
		var previous: Vector3 = snapshots[index].position
		var offset := previous-points[-1]
		var distance := offset.length()
		if distance <= 0.000001: continue
		if remaining <= 0: break
		points.append(points[-1]+offset*(minf(remaining,distance)/distance))
		remaining -= minf(remaining,distance)
	return points