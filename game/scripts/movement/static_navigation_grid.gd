class_name StaticNavigationGrid
extends RefCounted

const POSITION_EPSILON: float = 0.00001

var _grid := AStarGrid2D.new()
var _routes := preload("res://scripts/movement/route_cost_grid.gd").new()
var surface: TerrainSurface
var _config: MovementConfig
var _blocked: Array[Rect2] = []
var _clearance: float
var _initialized: bool = false


func initialize(config: MovementConfig, definition: PrototypeMapDefinition) -> bool:
	_initialized = false
	_config = config
	surface = TerrainSurface.new(definition)
	_routes.surface = surface
	_routes.configure_costs(null, false, config.speed)
	_routes.clear()
	_routes._edge_costs.clear()
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
	_build_route_connections()
	_initialized = true
	return true


func _cell_index(cell: Vector2i) -> int:
	return cell.y * _grid.region.size.x + cell.x


func _build_route_connections() -> void:
	# Reuse the occupancy grid, but connect all start/end anchors into one A* query.
	_routes.static_point_count = _grid.region.size.x * _grid.region.size.y
	for x: int in _grid.region.size.x:
		for z: int in _grid.region.size.y:
			var cell := Vector2i(x, z)
			if not _grid.is_point_solid(cell):
				_routes.add_point(_cell_index(cell), _grid.get_point_position(cell))
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for x: int in _grid.region.size.x:
		for z: int in _grid.region.size.y:
			var cell := Vector2i(x, z)
			if _grid.is_point_solid(cell):
				continue
			for direction: Vector2i in directions:
				var next := cell + direction
				if not _grid.is_in_boundsv(next) or _grid.is_point_solid(next):
					continue
				if direction.x != 0 and direction.y != 0:
					if _grid.is_point_solid(cell + Vector2i(direction.x, 0)) or _grid.is_point_solid(cell + Vector2i(0, direction.y)):
						continue
				if segment_is_walkable(_point(cell, 0.0), _point(next, 0.0)):
					_routes.connect_points(_cell_index(cell), _cell_index(next))


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


func find_path(start: Vector3, destination: Vector3, reserved: Array[Vector3] = [], separation: float = 0.0, fast: bool = false, unit: UnitState = null) -> PackedVector3Array:
	if not _initialized or not is_position_walkable(start):
		return PackedVector3Array()
	if is_position_walkable(destination) and _slot_available(destination, reserved, separation):
		# A valid but disconnected destination is not replaced by a distant partial route.
		return _path_to_exact_point(start, destination, fast, unit)
	for id: Vector2i in _candidate_cells(destination, _config.target_search_radius, start):
		var candidate := _point(id, start.y)
		if not _slot_available(candidate, reserved, separation):
			continue
		var path := _path_to_exact_point(start, candidate, fast, unit)
		if not path.is_empty():
			return path
	return PackedVector3Array()


func _path_to_exact_point(start: Vector3, destination: Vector3, fast: bool = false, unit: UnitState = null) -> PackedVector3Array:
	var time_cost := fast and unit != null and not is_equal_approx(unit.speed_on(true, _config.speed), unit.speed_on(false, _config.speed))
	_routes.configure_costs(unit, time_cost, _config.speed)
	if not time_cost and segment_is_walkable(start, destination):
		return PackedVector3Array([start, destination])
	var best := PackedVector3Array()
	var best_cost := INF
	if segment_is_walkable(start, destination):
		best = PackedVector3Array([start, destination])
		best_cost = path_cost(best, time_cost, unit)
	var anchor_radius := _config.navigation_cell_size * sqrt(2.0)
	var start_cells := _candidate_cells(start, anchor_radius, start)
	var end_cells := _candidate_cells(destination, anchor_radius, destination)
	var start_index: int = _routes.static_point_count
	var end_index := start_index + 1
	_routes.add_point(start_index, Vector2(start.x, start.z))
	_routes.add_point(end_index, Vector2(destination.x, destination.z))
	for cell: Vector2i in start_cells:
		if segment_is_walkable(start, _point(cell, start.y)):
			_routes.connect_points(start_index, _cell_index(cell))
	for cell: Vector2i in end_cells:
		if segment_is_walkable(_point(cell, start.y), destination):
			_routes.connect_points(_cell_index(cell), end_index)
	var ids := _routes.get_id_path(start_index, end_index, false)
	if not ids.is_empty():
		var points := PackedVector3Array()
		for id: int in ids:
			var point := _routes.get_point_position(id)
			points.append(Vector3(point.x, start.y, point.y))
		var simplified := _simplify(points, time_cost, unit)
		if not simplified.is_empty() and path_cost(simplified, time_cost, unit) < best_cost - 0.000001:
			best = simplified
	_routes.remove_point(start_index)
	_routes.remove_point(end_index)
	return best


func path_cost(points: PackedVector3Array, time_cost: bool, unit: UnitState = null) -> float:
	var cost := 0.0
	for index: int in points.size() - 1:
		cost += surface.segment_time(points[index], points[index + 1], unit, _config.speed) if time_cost else points[index].distance_to(points[index + 1])
	return cost


# Deployment only: ordinary commands keep their existing unreachable behavior.
func deployment_path(start: Vector3, destination: Vector3, fast: bool, unit: UnitState) -> PackedVector3Array:
	if not _initialized or not is_position_walkable(start):
		return PackedVector3Array()
	if is_position_walkable(destination):
		var exact := _path_to_exact_point(start, destination, fast, unit)
		if not exact.is_empty(): return exact
	# Flood only the start-connected static graph, then pick the nearest grid
	# position to the requested point. No A* query for every candidate.
	var visited := {}
	var queue: Array[int] = []
	for cell: Vector2i in _candidate_cells(start, _config.navigation_cell_size * sqrt(2.0), start):
		if segment_is_walkable(start, _point(cell, start.y)):
			var id := _cell_index(cell)
			if not visited.has(id):
				visited[id] = true
				queue.append(id)
	var best := start
	var distance := start.distance_squared_to(destination)
	var index := 0
	while index < queue.size():
		var id := queue[index]
		index += 1
		var xz := _routes.get_point_position(id)
		var point := Vector3(xz.x, start.y, xz.y)
		var d := point.distance_squared_to(destination)
		if d < distance - 0.000001 or (is_equal_approx(d, distance) and (point.x < best.x or (point.x == best.x and point.z < best.z))):
			best = point
			distance = d
		for next: int in _routes.get_point_connections(id):
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
	if best.is_equal_approx(start): return PackedVector3Array([start])
	return _path_to_exact_point(start, best, fast, unit)


func _simplify(points: PackedVector3Array, time_cost: bool = false, unit: UnitState = null) -> PackedVector3Array:
	var cumulative: Array[float] = [0.0]
	for point_index: int in points.size() - 1:
		var cost := surface.segment_time(points[point_index], points[point_index + 1], unit, _config.speed) if time_cost else points[point_index].distance_to(points[point_index + 1])
		cumulative.append(cumulative[-1] + cost)
	var simplified := PackedVector3Array([points[0]])
	var index := 0
	while index < points.size() - 1:
		var next := points.size() - 1
		while next > index + 1:
			if segment_is_walkable(points[index], points[next]):
				var shortcut := surface.segment_time(points[index], points[next], unit, _config.speed) if time_cost else points[index].distance_to(points[next])
				if shortcut <= cumulative[next] - cumulative[index] + 0.000001:
					break
			next -= 1
		if not segment_is_walkable(points[index], points[next]):
			return PackedVector3Array()
		simplified.append(points[next])
		index = next
	return simplified
