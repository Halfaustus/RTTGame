extends Node3D

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const DEFINITION: PrototypeMapDefinition = preload("res://data/prototype_map.tres")


@export var movement_config: MovementConfig = CONFIG

func _ready() -> void:
	var bounds := Rect2(movement_config.minimum_xz, movement_config.maximum_xz - movement_config.minimum_xz)
	_add_box("Ground", bounds, 0.1, movement_config.ground_height - 0.05, Color(0.16, 0.2, 0.23))
	for index: int in DEFINITION.hardened_surfaces.size():
		var road := MeshInstance3D.new()
		road.name = "Road_%d" % index
		var rectangle := DEFINITION.hardened_surfaces[index]
		var box := BoxMesh.new()
		box.size = Vector3(rectangle.size.x, 0.02, rectangle.size.y)
		road.mesh = box
		road.position = Vector3(rectangle.get_center().x, movement_config.ground_height + 0.01, rectangle.get_center().y)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.52, 0.55)
		road.material_override = material
		add_child(road)
	for index: int in DEFINITION.route_test_points.size():
		var marker := Label3D.new()
		marker.name = "RouteMarker_%d" % index
		marker.text = "A" if index == 0 else ("B" if index == 1 else "C")
		marker.position = DEFINITION.route_test_points[index]
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.font_size = 64
		add_child(marker)
	for index: int in DEFINITION.obstacles.size():
		_add_box("Obstacle_%d" % index, DEFINITION.obstacles[index], DEFINITION.obstacle_height,
			movement_config.ground_height + DEFINITION.obstacle_height * 0.5, Color(0.65, 0.45, 0.3))


func _add_box(box_name: String, footprint: Rect2, height: float, center_y: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = 1
	body.collision_mask = 0
	var center := footprint.get_center()
	body.position = Vector3(center.x, center_y, center.y)
	var size := Vector3(footprint.size.x, height, footprint.size.y)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
