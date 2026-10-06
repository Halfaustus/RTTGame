class_name ProjectileVisuals
extends MeshInstance3D

# Client cosmetics only. No simulation constants or collision queries.
const HALF_WIDTH := 0.035
const TERMINAL_FLASH_SECONDS := 0.12
const FADE_SEGMENTS := 8
var tracer_visual_time := 0.012
var tracer_min_length := 0.2
var tracer_max_length := 15.0
var tracer_fade_time := 0.012
var tracer_fade_max_length := 15.0
var tracer_alpha := 1.0
var feed: PresentationFeed
var _flashes: Array[Dictionary] = []

func setup(source: PresentationFeed) -> void:
	feed = source
	feed.projectile_spawn_received.connect(_on_spawn)
	feed.projectile_terminal_received.connect(_on_terminal)
	feed.reset_received.connect(clear)
	mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_process(not feed.live_projectiles.is_empty())

func tracer_profile(speed: float) -> Dictionary:
	var bright := clampf(speed*maxf(0,tracer_visual_time),maxf(0,tracer_min_length),maxf(tracer_min_length,tracer_max_length))
	var fade := clampf(speed*maxf(0,tracer_fade_time),0,maxf(0,tracer_fade_max_length))
	return {"bright_length":bright,"fade_length":fade,"length":bright+fade}

func visual_segment(head: Vector3, velocity: Vector3) -> Dictionary:
	var result := tracer_profile(velocity.length())
	result.head = head
	result.direction = velocity.normalized()
	result.alpha = clampf(tracer_alpha,0,1)
	return result

func _on_spawn(_event: Dictionary) -> void:
	set_process(true)

func clear() -> void:
	_flashes.clear()
	if mesh != null: mesh.clear_surfaces()
	set_process(false)

func _on_terminal(event: Dictionary) -> void:
	if not event.has("time_seconds") or not event.has("position"): return
	var segment := visual_segment(event.position,feed.projectile_velocity(event.projectile_id,event.time_seconds))
	segment.points = feed.projectile_buffers[event.projectile_id].trail_points(event.position,event.time_seconds,segment.length,true)
	if segment.points.size() < 2: return
	segment.remaining = TERMINAL_FLASH_SECONDS
	_flashes.append(segment)
	set_process(true)

func _process(delta: float) -> void:
	if feed == null: return
	feed.advance_projectile_display(delta)
	mesh.clear_surfaces()
	var segments: Array[Dictionary] = []
	for id: String in feed.live_projectiles:
		var visual_state := feed.projectile_visual_state(id,delta)
		var segment := visual_segment(visual_state.position,visual_state.velocity)
		segment.points = feed.projectile_buffers[id].trail_points(visual_state.position,feed.projectile_display_time-feed.interpolation_delay,segment.length)
		segments.append(segment)
	for index in range(_flashes.size()-1,-1,-1):
		var segment: Dictionary = _flashes[index].duplicate()
		segment.alpha *= clampf(segment.remaining/TERMINAL_FLASH_SECONDS,0,1)
		segments.append(segment)
		_flashes[index].remaining -= delta
		if _flashes[index].remaining <= 0: _flashes.remove_at(index)
	segments = segments.filter(func(segment): return segment.points.size() > 1)
	if segments.is_empty():
		set_process(not feed.live_projectiles.is_empty())
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: Dictionary in segments:
		_draw_segment(segment)
	mesh.surface_end()

func _draw_segment(segment: Dictionary) -> void:
	var points: PackedVector3Array = segment.points
	var length := 0.0
	for index in range(1,points.size()): length += points[index-1].distance_to(points[index])
	if length <= 0.000001: return
	var travelled := 0.0
	var bright_fraction: float = segment.bright_length/maxf(segment.length,0.000001)
	for index in range(1,points.size()):
		var start: Vector3 = points[index-1]
		var end: Vector3 = points[index]
		var distance := start.distance_to(end)
		var side := (end-start).cross(Vector3.UP).normalized()*HALF_WIDTH
		if side.is_zero_approx(): side = Vector3.RIGHT*HALF_WIDTH
		for subdivision in range(FADE_SEGMENTS):
			var a := float(subdivision)/FADE_SEGMENTS
			var b := float(subdivision+1)/FADE_SEGMENTS
			var pa := start.lerp(end,a)
			var pb := start.lerp(end,b)
			for vertex: Dictionary in [{"point":pa-side,"t":a},{"point":pa+side,"t":a},{"point":pb+side,"t":b},{"point":pa-side,"t":a},{"point":pb+side,"t":b},{"point":pb-side,"t":b}]:
				var fraction: float = (travelled+distance*vertex.t)/length
				mesh.surface_set_color(Color(1,0.9,0.2,segment.alpha*trail_alpha(fraction,bright_fraction)))
				mesh.surface_add_vertex(vertex.point)
		travelled += distance
static func trail_alpha(fraction: float, bright_fraction: float) -> float:
	if fraction <= bright_fraction: return lerpf(1.0,0.5,fraction/maxf(bright_fraction,0.000001))
	return 0.5*pow(clampf((1.0-fraction)/maxf(1.0-bright_fraction,0.000001),0,1),2)
