class_name PrototypeMapDefinition
extends Resource

# Axis-aligned rectangles in world X/Z, shared by navigation and map geometry.
@export var obstacles: Array[Rect2] = []
@export var obstacle_height: float = 2.5
@export var hardened_surfaces: Array[Rect2] = []
@export var route_test_points: Array[Vector3] = []
