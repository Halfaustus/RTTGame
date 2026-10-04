class_name DirectBallistics
extends RefCounted

static func lead(origin: Vector3, point: Vector3, velocity: Vector3, speed: float) -> Dictionary:
	var offset := point-origin
	if speed <= 0 or not is_finite(speed) or not velocity.is_finite(): return {"valid":false}
	var a := velocity.length_squared()-speed*speed
	var b := 2*offset.dot(velocity)
	var c := offset.length_squared()
	var time := 0.0
	if c > 0:
		if absf(a) < 0.000001:
			if b >= 0: return {"valid":false}
			time = -c/b
		else:
			var discriminant := b*b-4*a*c
			if discriminant < 0: return {"valid":false}
			var first := (-b-sqrt(discriminant))/(2*a)
			var second := (-b+sqrt(discriminant))/(2*a)
			time = minf(first,second) if first >= 0 and second >= 0 else maxf(first,second)
			if time < 0: return {"valid":false}
	return {"valid":true,"point":point+velocity*time,"seconds":time}

static func muzzle(weapon: RuntimeWeaponInstance, inputs: Dictionary = {}) -> Vector3:
	if inputs.has("house_center"): return inputs.house_center
	var offset := Prototype05FConfig.SOLDIER_MUZZLE
	if weapon.node_kind == WeaponAllocation.NodeKind.HULL: offset = Prototype05FConfig.HULL_MUZZLE
	elif weapon.node_kind == WeaponAllocation.NodeKind.MOUNT: offset = Prototype05FConfig.MAIN_MUZZLE if weapon.node_id == "main" else Prototype05FConfig.COMMANDER_MUZZLE
	return weapon.world_position()+offset.rotated(Vector3.UP,weapon.world_yaw())

static func spread_offset(random: RandomNumberGenerator, radius: float, direction: Vector3) -> Vector3:
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() == 0: right = Vector3.RIGHT
	var up := right.cross(direction).normalized()
	var angle := random.randf_range(0,TAU)
	var distance := sqrt(random.randf())*radius
	return (right*cos(angle)+up*sin(angle))*distance
