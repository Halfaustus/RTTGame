class_name WeaponDefinition
extends Resource

enum TargetType { INFANTRY, GROUND_VEHICLE, HELICOPTER, FIXED_WING, FORTIFICATION }

# -1 / empty explicitly mean undefined, never a zero-time/8-metre fallback.
@export var definition_id: String = ""
@export var required_operators: int = -1
@export var maximum_squad_count: int = -1 # DATA constraint; -1 means not specified.
@export var squad_weapon := false
@export var preparation_cadence := false # Existing per-round preparation, not rpm.
@export var data_source: String = ""
@export var range_m: float = -1.0
@export var allowed_target_types: Array[int] = []
@export var aim_min_seconds: float = -1.0
@export var aim_max_seconds: float = -1.0
@export var moving_aim_qualification: int = -1 # -1 unknown, 0 prohibited, 1 allowed
@export var indoor_qualification: int = -1
@export var ammo_definitions: Array[AmmoDefinition] = []
@export var capacity: int = 0
@export var consumption_per_projectile: int = 1
@export var actual_round_interval: float = -1.0
@export var game_projectile_interval: float = -1.0
@export var preparation_seconds: float = -1.0
@export var spread_policy: String = "fixed_world_radius"
@export var spread_radius_m: float = -1.0
@export var temporary_fields: Array[String] = []
@export var mechanical_loading := false
@export var reduction_ignore := -1.0
@export var attack_top := false # Existing confirmed weapon tag; not guidance.
@export var projectile: ProjectileDefinition
# Old isolated prototype compatibility only; runtime aiming never reads these.
@export var damage: float = 10.0
@export var firing_interval: float = 1.0
@export var can_fire_while_moving: bool = true


# DB40 24A: effective rpm counts ammunition/minute, not mechanical cycles.
# Single interval = consumption * actual_round_interval (=60/rpm).
# RuntimeWeaponInstance then divides by fixed N exactly once.
# AT4/CG preparation cadence is exempt; mechanical loading is NOT exempt.
# Unknown values stay unknown. Tolerance is floating arithmetic only:
# 1e-9 seconds absolute + 1e-9 relative, not a balance tolerance.
const CADENCE_ABSOLUTE_TOLERANCE := 1e-9
const CADENCE_RELATIVE_TOLERANCE := 1e-9

func cadence_issues() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if preparation_cadence: return issues
	if not is_finite(actual_round_interval) or actual_round_interval < 0.0: return issues
	if actual_round_interval == 0.0:
		issues.append({"code":"invalid_actual_interval","path":"actual_round_interval","message":"Applicable actual round interval must be positive"})
		return issues
	if not is_finite(game_projectile_interval) or game_projectile_interval < 0.0: return issues
	var expected := consumption_per_projectile * actual_round_interval
	if not cadence_valid():
		issues.append({"code":"cadence_conflict","path":"game_projectile_interval","related_fields":["actual_round_interval","consumption_per_projectile"],"definition_id":definition_id,"expected_seconds":expected,"actual_seconds":game_projectile_interval,"message":"Single interval conflicts with effective rpm/consumption"})
	return issues


# Allocation-free defensive check for the scheduler hot path; same tolerance.
func cadence_valid() -> bool:
	if preparation_cadence or not is_finite(actual_round_interval) or actual_round_interval < 0: return true
	if actual_round_interval == 0: return false
	if not is_finite(game_projectile_interval) or game_projectile_interval < 0: return true
	var expected := consumption_per_projectile * actual_round_interval
	var tolerance := CADENCE_ABSOLUTE_TOLERANCE + CADENCE_RELATIVE_TOLERANCE * maxf(absf(expected),absf(game_projectile_interval))
	return consumption_per_projectile > 0 and absf(expected-game_projectile_interval) <= tolerance
