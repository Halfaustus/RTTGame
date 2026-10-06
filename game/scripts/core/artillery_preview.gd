class_name ArtilleryPreview
extends MeshInstance3D

# Local nominal preview only: never samples scatter, changes ammo, or predicts hits.
const SEGMENTS := 128
const HALF_WIDTH := 0.05
var data := ConfirmedGameData.new()
var _definitions: Dictionary = {}
var descriptions: Array[Dictionary] = []

func _init() -> void:
	mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = Color.RED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_process(false)

func describe(weapon: Dictionary,point: Vector3,indirect: bool = true) -> Dictionary:
	var id := str(weapon.get("definition_id",""))
	var record := data.record("Weapons",id)
	if record.is_empty() or (record.get("Class","") == "迫击炮") != indirect: return {}
	if not weapon.get("weapon_position") is Vector3 or not weapon.get("muzzle_position") is Vector3 or not point.is_finite(): return {}
	if not _definitions.has(id): _definitions[id] = data.weapon(id)
	var definition: WeaponDefinition = _definitions[id]
	if definition == null: return {}
	var distance: float = weapon.weapon_position.distance_to(point)
	var minimum := data.number(record,"Min_Range_m") if indirect else 0.0
	var result := {"origin":weapon.muzzle_position,"point":point,"distance":distance,"minimum":minimum,"maximum":definition.range_m,"valid":false,"reason":"configuration_missing"}
	if not is_finite(minimum) or not is_finite(definition.range_m): return result
	result.reason = "below_minimum_range" if distance < minimum else ("above_maximum_range" if distance > definition.range_m else "eligible")
	if result.reason != "eligible": return result
	var selection := AmmoSelection.ground_selection_values(definition,weapon.get("inventory",{}))
	if selection.reason != "eligible": result.reason = selection.reason; return result
	if selection.ammo.distance_selected_launch != indirect: return result
	var solution := GravityBallistics.indirect(weapon.muzzle_position,point) if indirect else GravityBallistics.direct(weapon.muzzle_position,point,Vector3.ZERO,selection.ammo.initial_speed_mps)
	result.valid = solution.valid
	result.reason = solution.reason
	if solution.valid: result.velocity = solution.velocity; result.seconds = solution.seconds
	return result

func clear() -> void:
	descriptions.clear()
	mesh.clear_surfaces()

func show_targets(structures: Array[Dictionary],point: Vector3,indirect: bool = true) -> String:
	clear()
	var messages: PackedStringArray = []
	for structure: Dictionary in structures:
		for weapon: Dictionary in structure.get("weapons",[]):
			var result := describe(weapon,point,indirect)
			if result.is_empty(): continue
			descriptions.append(result)
			var status: String = {"eligible":"可炮击" if indirect else "可开火","below_minimum_range":"低于最小射程","above_maximum_range":"超出当前射程","ammunition_insufficient":"无可用弹药"}.get(result.reason,"无法解算")
			messages.append("#%s 距离 %.1f 米 · 射程 %.0f–%.0f 米 · %s" % [structure.unit_id,result.distance,result.minimum,result.maximum,status])
	var valid := descriptions.filter(func(row): return row.valid)
	if not valid.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for result: Dictionary in valid:
			var previous: Vector3 = result.origin
			for index in range(1,SEGMENTS+1):
				var time: float = result.seconds*index/float(SEGMENTS)
				var point_at: Vector3 = result.origin+result.velocity*time+GravityBallistics.GRAVITY*(0.5*time*time)
				var side := (point_at-previous).cross(Vector3.UP).normalized()*HALF_WIDTH
				if side.is_zero_approx(): side = Vector3.RIGHT*HALF_WIDTH
				for vertex: Vector3 in [previous-side,previous+side,point_at+side,previous-side,point_at+side,point_at-side]: mesh.surface_add_vertex(vertex)
				previous = point_at
		mesh.surface_end()
	return ("请选择己方火炮，等待武器状态同步" if indirect else "请选择己方直射单位，等待武器状态同步") if messages.is_empty() else "\n".join(messages)+"\n红线为预测弹道，不包含散布及实际碰撞"
