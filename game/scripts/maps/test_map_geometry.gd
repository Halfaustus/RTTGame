extends Node3D

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const DEFINITION: PrototypeMapDefinition = preload("res://data/prototype_map.tres")


func _ready() -> void:
	var bounds := Rect2(CONFIG.minimum_xz, CONFIG.maximum_xz - CONFIG.minimum_xz)
	_add_box("Ground", bounds, 0.1, CONFIG.ground_height - 0.05, Color(0.16, 0.2, 0.23))
	for index: int in DEFINITION.obstacles.size():
		_add_box("Obstacle_%d" % index, DEFINITION.obstacles[index], DEFINITION.obstacle_height,
			CONFIG.ground_height + DEFINITION.obstacle_height * 0.5, Color(0.65, 0.45, 0.3))


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
