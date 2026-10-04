class_name Prototype05FConfig
extends RefCounted

# Explicit prototype values, never formal balance or range overrides.
const RANDOM_SEED := 50506
const CONTACT_EPSILON_M := 0.0001
const SOLDIER_MUZZLE := Vector3(0,0.15,-0.15)
const MAIN_MUZZLE := Vector3(0,0.2,-0.6)
const COMMANDER_MUZZLE := Vector3(0,0.35,-0.4)
const HULL_MUZZLE := Vector3(0,0.05,-0.5)

static func configure(weapons: Dictionary) -> void:
	for id: String in weapons:
		if id == "shotgun": continue
		var definition := ProjectileDefinition.new()
		definition.speed_mps = 400 if id.begins_with("cannon_") else (200 if id in ["rocket","recoilless"] else 600)
		definition.radius_m = 0.025
		definition.lifetime_seconds = 8
		definition.spread_radius_m = 0.15 if id in ["pdw","rifle","lmg","vehicle_mg"] else 0.2
		if id.begins_with("cannon_"):
			definition.spread_policy = "radius_at_1000m"
			definition.spread_radius_m = 2 # Existing baseline temporary cannon policy.
			definition.moving_spread_multiplier = 2
		weapons[id].projectile = definition
		weapons[id].temporary_fields.append("projectile_test_configuration")
