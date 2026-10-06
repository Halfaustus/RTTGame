class_name CameraConfig
extends Resource

@export_range(0.1, 100.0) var movement_speed: float = 18.0
@export_range(0.01, 2.0) var rotation_degrees_per_pixel: float = 0.2
@export_range(0.1, 20.0) var zoom_step: float = 2.0
@export_range(1.0, 89.0) var minimum_pitch_degrees: float = 20.0
@export_range(1.0, 89.0) var maximum_pitch_degrees: float = 80.0
@export_range(1.0, 100.0) var minimum_distance: float = 6.0
@export_range(1.0, 1000.0) var maximum_distance: float = 60.0
@export var ground_height: float = 0.0

# Opt-in client map experience; legacy resources retain constant speed/zoom.
@export var height_scaled_pan := false
@export_range(0.1, 300.0) var maximum_pan_speed := 18.0
@export_range(0.0, 0.5) var zoom_distance_fraction := 0.0

@export var zoom_scaled_markers := false
@export_range(1.0, 1000.0) var marker_reference_distance := 60.0
@export_range(0.1, 1.0) var minimum_marker_scale := 0.6
