class_name ProjectileDefinition
extends Resource

@export var trajectory := "direct"
@export var speed_mps := -1.0
@export var radius_m := -1.0
@export var lifetime_seconds := -1.0
@export var spread_radius_m := -1.0
@export var spread_policy := "fixed_world_radius"
@export var moving_spread_multiplier := 1.0
@export var temporary := true

func valid() -> bool:
	return trajectory == "direct" and is_finite(speed_mps) and speed_mps > 0 and is_finite(radius_m) and radius_m >= 0 and is_finite(lifetime_seconds) and lifetime_seconds > 0 and is_finite(spread_radius_m) and spread_radius_m >= 0 and moving_spread_multiplier >= 1

func snapshot() -> Dictionary:
	return {"trajectory":trajectory,"speed_mps":speed_mps,"radius_m":radius_m,"lifetime_seconds":lifetime_seconds}
