class_name TemporaryExplosionVisual
extends MeshInstance3D

# TEST ONLY range visualization; replace with authored effects later.
const LIFETIME := 1.2
const SEGMENTS := 64
var flashes: Array[Dictionary] = []

func _ready() -> void:
	mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_process(false)

func show_event(event: Dictionary) -> void:
	flashes.append({"point":event.position,"radius":event.radius,"remaining":LIFETIME})
	set_process(true)

func clear() -> void:
	flashes.clear()
	if mesh != null: mesh.clear_surfaces()
	set_process(false)

func _process(delta: float) -> void:
	mesh.clear_surfaces()
	for i in range(flashes.size()-1,-1,-1):
		flashes[i].remaining -= delta
		if flashes[i].remaining <= 0: flashes.remove_at(i)
	if flashes.is_empty(): set_process(false); return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for event: Dictionary in flashes:
		var point: Vector3 = event.point
		var ground := Vector3(point.x,0.06,point.z)
		mesh.surface_set_color(Color(1,0.55,0.1,event.remaining/LIFETIME))
		mesh.surface_add_vertex(ground)
		mesh.surface_add_vertex(point+Vector3.UP*0.2)
		for i: int in SEGMENTS:
			for angle: float in [TAU*i/SEGMENTS,TAU*(i+1)/SEGMENTS]:
				mesh.surface_add_vertex(ground+Vector3(cos(angle),0,sin(angle))*event.radius)
	mesh.surface_end()
