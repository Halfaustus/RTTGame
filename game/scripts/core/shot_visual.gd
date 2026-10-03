extends MeshInstance3D


func show_shot(start: Vector3, end: Vector3) -> void:
	var line := ImmediateMesh.new()
	var side := (end - start).cross(Vector3.UP).normalized() * 0.035
	line.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in [start - side, start + side, end + side, start - side, end + side, end - side]:
		line.surface_add_vertex(vertex)
	line.surface_end()
	mesh = line
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.9, 0.2)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().create_timer(0.12).timeout.connect(queue_free)
