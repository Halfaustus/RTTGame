class_name StaticNavigationGrid
extends RefCounted

const POSITION_EPSILON: float = 0.00001

var _grid := AStarGrid2D.new()
var _config: MovementConfig
var _blocked: Array[Rect2] = []
var _clearance: float
var _initialized: bool = false


func initialize(config: MovementConfig, definition: PrototypeMapDefinition) -> bool:
	_initialized = false
	_config = config
	if config.navigation_cell_size <= 0.0 or config.maximum_xz.x <= config.minimum_xz.x \
		or config.maximum_xz.y <= config.minimum_xz.y:
		return false
	_clearance = config.unit_width * 0.5 + config.obstacle_margin
	_blocked.clear()
	for obstacle: Rect2 in definition.obstacles:
		_blocked.append(obstacle.abs().grow(_clearance))
	var cell := config.navigation_cell_size
	var extent := config.maximum_xz - config.minimum_xz
	_grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(extent.x / cell), ceili(extent.y / cell)))
	_grid.cell_size = Vector2(cell, cell)
	_grid.offset = config.minimum_xz + Vector2.ONE * cell * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x: int in _grid.region.size.x:
		for z: int in _grid.region.size.y:
			var id := Vector2i(x, z)
			var point := _grid.get_point_position(id)
			_grid.set_point_solid(id, not is_position_walkable(Vector3(point.x, 0.0, point.y)))
	_initialized = true
	return true


func is_ready() -> bool:
	return _initialized


func is_position_walkable(position: Vector3) -> bool:
	if _config == null or not position.is_finite():
		return false
	var point := Vector2(position.x, position.z)
	# Vector3 stores float32 values; tolerate rounding at an inset map boundary.
	if point.x < _config.minimum_xz.x + _clearance - POSITION_EPSILON or point.x > _config.maximum_xz.x - _clearance + POSITION_EPSILON \
		or point.y < _config.minimum_xz.y + _clearance - POSITION_EPSILON or point.y > _config.maximum_xz.y - _clearance + POSITION_EPSILON:
		return false
	for obstacle: Rect2 in _blocked:
		if point.x >= obstacle.position.x and point.x <= obstacle.end.x \
			and point.y >= obstacle.position.y and point.y <= obstacle.end.y:
			return false
	return true


func segment_is_walkable(start: Vector3, end: Vector3) -> bool:
	if not is_position_walkable(start) or not is_position_walkable(end):
		return false
	for obstacle: Rect2 in _blocked:
		if _segment_hits_rectangle(Vector2(start.x, start.z), Vector2(end.x, end.z), obstacle):
			return false
	return true


func _segment_hits_rectangle(start: Vector2, end: Vector2, rectangle: Rect2) -> bool:
	var direction := end - start
	var first := 0.0
	var last := 1.0
	for axis: int in 2:
		if is_zero_approx(direction[axis]):
			if start[axis] < rectangle.position[axis] or start[axis] > rectangle.end[axis]:
				return false
		else:
			var a := (rectangle.position[axis] - start[axis]) / direction[axis]
			var b := (rectangle.end[axis] - start[axis]) / direction[axis]
			first = maxf(first, minf(a, b))
			last = minf(last, maxf(a, b))
			if first > last:
				return false
	return true


func _point(id: Vector2i, height: float) -> Vector3:
	var point := _grid.get_point_position(id)
	return Vector3(point.x, height, point.y)


func _candidate_cells(position: Vector3, radius: float, preference: Vector3) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var coordinate := (Vector2(position.x, position.z) - _grid.offset) / _grid.cell_size
	var center := Vector2i(roundi(coordinate.x), roundi(coordinate.y))
	var reach := ceili(radius / _config.navigation_cell_size) + 1
	for x: int in range(center.x - reach, center.x + reach + 1):
		for z: int in range(center.y - reach, center.y + reach + 1):
			var id := Vector2i(x, z)
			if not _grid.is_in_boundsv(id) or _grid.is_point_solid(id):
				continue
			if _point(id, position.y).distance_to(position) <= radius:
				cells.append(id)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var point_a := _point(a, position.y)
		var point_b := _point(b, position.y)
		var distance_a := point_a.distance_squared_to(position)
		var distance_b := point_b.distance_squared_to(position)
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		var preference_a := point_a.distance_squared_to(preference)
		var preference_b := point_b.distance_squared_to(preference)
		if not is_equal_approx(preference_a, preference_b):
			return preference_a < preference_b
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return cells


func nearest_walkable_position(position: Vector3) -> Variant:
	if not _initialized:
		return null
	if is_position_walkable(position):
		return position
	var candidates := _candidate_cells(position, _config.target_search_radius, position)
	return null if candidates.is_empty() else _point(candidates[0], position.y)


func _slot_available(position: Vector3, reserved: Array[Vector3], separation: float) -> bool:
	for other: Vector3 in reserved:
		if position.distance_to(other) < separation - 0.0001:
			return false
	return true


func find_path(start: Vector3, destination: Vector3, reserved: Array[Vector3] = [], separation: float = 0.0) -> PackedVector3Array:
	if not _initialized or not is_position_walkable(start):
		return PackedVector3Array()
	if is_position_walkable(destination) and _slot_available(destination, reserved, separation):
		# A valid but disconnected destination is not replaced by a distant partial route.
		return _path_to_exact_point(start, destination)
	for id: Vector2i in _candidate_cells(destination, _config.target_search_radius, start):
		var candidate := _point(id, start.y)
		if not _slot_available(candidate, reserved, separation):
			continue
		var path := _path_to_exact_point(start, candidate)
		if not path.is_empty():
			return path
	return PackedVector3Array()


func _path_to_exact_point(start: Vector3, destination: Vector3) -> PackedVector3Array:
	if segment_is_walkable(start, destination):
		return PackedVector3Array([start, destination])
	var anchor_radius := _config.navigation_cell_size * sqrt(2.0)
	var start_cells := _candidate_cells(start, anchor_radius, start)
	var end_cells := _candidate_cells(destination, anchor_radius, destination)
	for start_id: Vector2i in start_cells:
		if not segment_is_walkable(start, _point(start_id, start.y)):
			continue
		for end_id: Vector2i in end_cells:
			if not segment_is_walkable(_point(end_id, start.y), destination):
				continue
			var ids := _grid.get_id_path(start_id, end_id, false)
			if ids.is_empty():
				continue
			var points := PackedVector3Array([start])
			for id: Vector2i in ids:
				points.append(_point(id, start.y))
			points.append(destination)
			return _simplify(points)
	return PackedVector3Array()


func _simplify(points: PackedVector3Array) -> PackedVector3Array:
	var simplified := PackedVector3Array([points[0]])
	var index := 0
	while index < points.size() - 1:
		var next := points.size() - 1
		while next > index + 1 and not segment_is_walkable(points[index], points[next]):
			next -= 1
		if not segment_is_walkable(points[index], points[next]):
			return PackedVector3Array()
		simplified.append(points[next])
		index = next
	return simplified
