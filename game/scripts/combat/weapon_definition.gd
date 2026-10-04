class_name WeaponDefinition
extends Resource

enum TargetType { INFANTRY, GROUND_VEHICLE, HELICOPTER, FIXED_WING, FORTIFICATION }

# -1 / empty explicitly mean undefined, never a zero-time/8-metre fallback.
@export var definition_id: String = ""
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
@export var projectile: ProjectileDefinition
# Old isolated prototype compatibility only; runtime aiming never reads these.
@export var damage: float = 10.0
@export var firing_interval: float = 1.0
@export var can_fire_while_moving: bool = true
