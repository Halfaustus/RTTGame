class_name AmmoDefinition
extends Resource

@export var ammo_id: String = ""
@export var initial_speed_mps: float = NAN # Direct DATA speed only; missing/N.A. stays NaN.
var distance_selected_launch := false # Adapter provenance from existing Weapon Class; not a DATA field.
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
var confirmed_decay_coefficient := NAN # Cached implementation value, not DATA.

func configure_confirmed_curve() -> void:
	confirmed_decay_coefficient = NAN
	if damage_type == "kinetic" and is_finite(penetration_upper) and is_finite(anchor_penetration) and is_finite(anchor_distance_m) and anchor_distance_m > 0 and penetration_upper >= anchor_penetration and anchor_penetration >= 5:
		confirmed_decay_coefficient = (penetration_upper-anchor_penetration)/log(1.0+anchor_distance_m/100.0)
