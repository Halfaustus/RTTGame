extends Node3D

var armed := false
var unit_id: int = 0
var owner_peer_id: int = 0
var team_id: int = 1
var maximum_health: float = 100.0
var health: float = 100.0
var unit_type: int = UnitDefinition.UnitType.INFANTRY
var _health_fill: MeshInstance3D
var _nose: MeshInstance3D


func _ready() -> void:
	var background := _bar(Color(0.15, 0.15, 0.15), Vector3(1.15, 0.08, 0.22))
	background.position = Vector3(0, 0.85, 0)
	add_child(background)
	_health_fill = _bar(Color(0.2, 1, 0.2), Vector3(1.0, 0.09, 0.18))
	_health_fill.position = Vector3(0, 0.86, 0)
	add_child(_health_fill)
	_refresh_combat_visual()
	display_unit_type(unit_type)


func display_unit_type(kind: int) -> void:
	unit_type = kind
	if not is_node_ready():
		return
	if _nose == null:
		_nose = _bar(Color(1.0, 0.9, 0.15), Vector3(0.3, 0.08, 0.18))
		_nose.name = "FrontMarker"
		_nose.position = Vector3(0, 0.3, -0.38)
		$MeshInstance3D.add_child(_nose)
	_nose.visible = true
	if kind == UnitDefinition.UnitType.ARMORED_VEHICLE:
		var box := BoxMesh.new()
		# Rotated corners stay inside the existing one-metre navigation footprint.
		box.size = Vector3(0.6, 0.5, 0.8)
		$MeshInstance3D.mesh = box
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.35
		sphere.height = 0.9
		$MeshInstance3D.mesh = sphere


func display_yaw(yaw: float) -> void:
	# Only rotate the body and nose, leaving health bars and selection readable.
	$MeshInstance3D.rotation.y = yaw


func _bar(color: Color, size: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual


func display_combat_state(team: int, maximum: float, current: float) -> void:
	if team >= 0:
		team_id = team
	if maximum > 0.0:
		maximum_health = maximum
	health = current
	if is_node_ready():
		_refresh_combat_visual()


func _refresh_combat_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.6, 1.0) if team_id == 1 else Color(1.0, 0.25, 0.15)
	$MeshInstance3D.material_override = material
	var fraction := clampf(health / maximum_health, 0.0, 1.0)
	_health_fill.scale.x = maxf(0.001, fraction)
	_health_fill.position.x = (fraction - 1.0) * 0.5


func set_selected(selected: bool) -> void:
	$SelectionIndicator.visible = selected


func setup(new_unit_id: int, new_owner_peer_id: int) -> void:
	unit_id = new_unit_id
	owner_peer_id = new_owner_peer_id

	print(
		"Unit %d initialized. Owner peer: %d"
		% [unit_id, owner_peer_id]
	)
