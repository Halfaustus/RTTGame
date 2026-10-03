class_name TerrainSurface
extends RefCounted

var _roads: Array[Rect2] = []


func _init(definition: PrototypeMapDefinition) -> void:
	for rectangle: Rect2 in definition.hardened_surfaces:
		_roads.append(rectangle.abs())


func is_hardened(position: Vector3) -> bool:
	for road: Rect2 in _roads:
		if position.x >= road.position.x and position.x <= road.end.x \
			and position.z >= road.position.y and position.z <= road.end.y:
			return true
	return false


func split_segment(start: Vector3, end: Vector3) -> PackedVector3Array:
	# Include all road entry/exit parameters; overlapping roads are classified by midpoint.
	var cuts: Array[float] = [0.0, 1.0]
	var origin := Vector2(start.x, start.z)
	var direction := Vector2(end.x - start.x, end.z - start.z)
	for road: Rect2 in _roads:
		var first := 0.0
		var last := 1.0
		var intersects := true
		for axis: int in 2:
			if is_zero_approx(direction[axis]):
				if origin[axis] < road.position[axis] or origin[axis] > road.end[axis]:
					intersects = false
					break
			else:
				var a := (road.position[axis] - origin[axis]) / direction[axis]
				var b := (road.end[axis] - origin[axis]) / direction[axis]
				first = maxf(first, minf(a, b))
				last = minf(last, maxf(a, b))
				if first > last:
					intersects = false
					break
		if intersects:
			cuts.append(first)
			cuts.append(last)
	cuts.sort()
	var points := PackedVector3Array([start])
	var previous := 0.0
	for fraction: float in cuts:
		if fraction > previous + 0.0000001 and fraction < 1.0:
			points.append(start.lerp(end, fraction))
			previous = fraction
	points.append(end)
	return points


func segment_time(start: Vector3, end: Vector3, unit: UnitState, fallback: float) -> float:
	var points := split_segment(start, end)
	var duration := 0.0
	for index: int in points.size() - 1:
		var speed := unit.speed_on(is_hardened((points[index] + points[index + 1]) * 0.5), fallback)
		if not is_finite(speed) or speed <= 0.0:
			return INF
		duration += points[index].distance_to(points[index + 1]) / speed
	return duration
