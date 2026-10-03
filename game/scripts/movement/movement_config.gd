class_name MovementConfig
extends Resource

@export var speed: float = 4.0
@export var replication_interval: float = 0.05
@export var spawn_origin: Vector3 = Vector3(-3.0, 0.5, 100.0)
@export var spawn_spacing: float = 3.0
@export var spawn_columns: int = 3
@export var units_per_peer: int = 3
# Current test cubes are one metre wide; leave half a metre between destinations.
@export var unit_width: float = 1.0
@export var destination_gap: float = 0.5
@export var navigation_cell_size: float = 0.5
@export var obstacle_margin: float = 0.05
@export var target_search_radius: float = 2.0
@export var ground_height: float = 0.0
@export var minimum_xz: Vector2 = Vector2(-20.0, 80.0)
@export var maximum_xz: Vector2 = Vector2(60.0, 120.0)


func spawn_position(unit_id: int) -> Vector3:
	var rows := maxi(1, floori((spawn_origin.z - minimum_xz.y) / spawn_spacing) + 1)
	var index := unit_id - 1
	var block := index / (spawn_columns * rows)
	var local_index := index % (spawn_columns * rows)
	return spawn_origin + Vector3(
		(local_index % spawn_columns + block * spawn_columns) * spawn_spacing,
		0.0, -(local_index / spawn_columns) * spawn_spacing
	)
