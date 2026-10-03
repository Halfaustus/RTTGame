class_name DeploymentConfig
extends Resource

# Map deployment metadata is separate from the frozen v1 presentation map.
# Dictionaries have explicit schemas validated by DeploymentEconomy.initialize.
@export var map_id: String = "prototype-map-0.2"
@export var temporary_test_values: bool = true
@export var catalog: Array[Dictionary] = []
@export var points: Array[Dictionary] = []
@export var initial_points: float = 1000.0
@export var income_seconds: float = 5.0
@export var income_points: float = 25.0
@export var ground_upkeep_fraction_per_minute: float = 0.05
@export var air_upkeep_fraction_per_minute: float = 0.025 # Reserved; no air catalog/spawning.
# Ground duration runs on server ticks; air duration remains reserved.
@export var ground_countdown_seconds: float = 3.0
@export var air_countdown_seconds: float = 6.0
@export var spawn_search_radius: float = 3.0
@export var spawn_search_step: float = 0.5
@export var waiting_retry_seconds: float = 0.25
