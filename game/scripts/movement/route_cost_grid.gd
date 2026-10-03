extends AStar2D

var surface: TerrainSurface
var unit: UnitState
var fallback_speed: float = 4.0
var time_cost: bool = false
var static_point_count: int = 0
var _edge_costs: Dictionary[Vector2i, float] = {}
var _profile := Vector3(-1, -1, -1)
var _maximum_speed: float = 4.0


func configure_costs(new_unit: UnitState, use_time: bool, fallback: float) -> void:
	unit = new_unit
	time_cost = use_time
	fallback_speed = fallback
	var paved := unit.speed_on(true, fallback) if unit != null else fallback
	var unpaved := unit.speed_on(false, fallback) if unit != null else fallback
	var profile := Vector3(paved, unpaved, 1.0 if use_time else 0.0)
	if profile != _profile:
		_edge_costs.clear()
		_profile = profile
	_maximum_speed = maxf(paved, unpaved)


func _compute_cost(from_id: int, to_id: int) -> float:
	# Only static edges are cached; virtual start/end positions change per request.
	var key := Vector2i(mini(from_id, to_id), maxi(from_id, to_id))
	var cacheable := from_id < static_point_count and to_id < static_point_count
	if cacheable and _edge_costs.has(key):
		return _edge_costs[key]
	var a := get_point_position(from_id)
	var b := get_point_position(to_id)
	var start := Vector3(a.x, 0.0, a.y)
	var end := Vector3(b.x, 0.0, b.y)
	# Connections have already passed the continuous footprint-clearance check.
	var cost := surface.segment_time(start, end, unit, fallback_speed) if time_cost else a.distance_to(b)
	if cacheable:
		_edge_costs[key] = cost
	return cost


func _estimate_cost(from_id: int, to_id: int) -> float:
	var distance := get_point_position(from_id).distance_to(get_point_position(to_id))
	if time_cost:
		# Admissible lower bound, never assume the whole route uses the slower surface.
		return distance / _maximum_speed
	return distance
