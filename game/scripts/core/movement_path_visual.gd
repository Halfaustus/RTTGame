extends MeshInstance3D

const DASH_LENGTH: float = 0.5
const GAP_LENGTH: float = 0.3
const PATH_WIDTH: float = 0.06

var _path_mesh := ImmediateMesh.new()


func _init() -> void:
	mesh = _path_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.25, 0.9, 1.0)
	material_override = material


func update_path(start: Vector3, destination: Vector3) -> void:
	update_route(PackedVector3Array([start, destination]))


func update_route(points: PackedVector3Array) -> void:
	_path_mesh.clear_surfaces()
	var begun := false
	for index: int in points.size() - 1:
		if points[index].distance_to(points[index + 1]) <= 0.001:
			continue
		if not begun:
			_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		_append_segment(points[index], points[index + 1])
	if begun:
		_path_mesh.surface_end()


func _append_segment(start: Vector3, destination: Vector3) -> void:
	var distance := start.distance_to(destination)
	var direction := (destination - start) / distance
	var side := direction.cross(Vector3.UP).normalized() * PATH_WIDTH * 0.5
	var offset := 0.0
	while offset < distance:
		var a := start + direction * offset
		var b := start + direction * minf(offset + DASH_LENGTH, distance)
		for vertex: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
			_path_mesh.surface_add_vertex(vertex)
		offset += DASH_LENGTH + GAP_LENGTH
