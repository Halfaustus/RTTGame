class_name AttackTarget
extends RefCounted

enum Kind { UNIT, FORCED_GROUND }
var kind := Kind.UNIT
var unit_id := 0
var entity: WeakRef
var ground_position := Vector3.ZERO

static func unit(state: UnitState) -> AttackTarget:
	var result := AttackTarget.new()
	result.unit_id = state.unit_id
	result.entity = weakref(state)
	return result

static func ground(position: Vector3) -> AttackTarget:
	var result := AttackTarget.new()
	result.kind = Kind.FORCED_GROUND
	result.ground_position = position
	return result

func state() -> UnitState:
	return entity.get_ref() if entity != null else null

func valid(units: Dictionary) -> bool:
	if kind == Kind.FORCED_GROUND: return ground_position.is_finite()
	var value := state()
	return value != null and units.get(unit_id) == value and value.health > 0.0 and value.position.is_finite()

func position() -> Vector3:
	return ground_position if kind == Kind.FORCED_GROUND else state().position

func target_type() -> int:
	return WeaponDefinition.TargetType.INFANTRY if state().unit_type() == UnitDefinition.UnitType.INFANTRY else WeaponDefinition.TargetType.GROUND_VEHICLE

func same(other: AttackTarget) -> bool:
	return other != null and kind == other.kind and (ground_position == other.ground_position if kind == Kind.FORCED_GROUND else state() == other.state())
