class_name AmmoDefinition
extends Resource

@export var ammo_id: String = ""
@export var damage_type: String = ""
@export var nominal_damage: float = -1.0
@export var penetration_upper: float = -1.0
@export var anchor_distance_m: float = -1.0
@export var anchor_penetration: float = -1.0
@export var minimum_penetration: float = 5.0
@export var curve_description: String = "undefined"
@export var explosion_radius_m: float = -1.0
@export var suppression: float = -1.0
@export var module_damage: float = -1.0
@export var test_curve: String = "" # Explicit temporary evaluator, never a formal curve.
@export var test_log_shape := -1.0
# Static anchors only: deliberately no penetration/damage evaluator.
