class_name UnitStatusProjection
extends RefCounted

# Display-only projection. Never expose Q, member IDs, inventory or weapon data.
static func project(structure: Dictionary, own: bool = false) -> Dictionary:
	var id: Variant = structure.get("unit_id")
	var personnel: Variant = structure.get("personnel")
	if not id is int or not personnel is Dictionary or personnel.get("state") not in ["calm","panic","disabled","dead"]: return {}
	var result := {"unit_id":id,"personnel_state":personnel.state}
	if structure.has("modules"):
		var modules: Variant = structure.modules
		if not modules is Array or modules.size() != 4: return {}
		for grade: Variant in modules:
			if not grade is int or grade < 0 or grade > 2: return {}
		result.modules = modules.duplicate()
	if structure.has("marker_status"):
		var marker: Variant = structure.marker_status
		if not marker is Dictionary: return {}
		for field: String in ["hold_fire","engaged","mixed_cargo"]:
			if not marker.get(field,false) is bool: return {}
			result[field] = marker.get(field,false)
		var count: Variant = marker.get("carried_personnel",0)
		if not count is int or count < 0: return {}
		result.carried_personnel = 0 if result.mixed_cargo else count
		var progress: Variant = marker.get("fire_progress",{})
		if not progress is Dictionary: return {}
		if not progress.is_empty():
			if not ImpactDamageRules.number(progress.get("remaining_seconds"),0.0) or not ImpactDamageRules.number(progress.get("progress"),0.0) or progress.progress > 1: return {}
			result.fire_progress = {"remaining_seconds":progress.remaining_seconds,"progress":progress.progress}
		else: result.fire_progress = {}
		if own:
			if not UnitMarkerStatus.valid_activity({"laser":marker.get("laser","inactive"),"return_fire_only":marker.get("return_fire_only",false)}): return {}
			result.laser = marker.get("laser","inactive")
			result.return_fire_only = marker.get("return_fire_only",false)
	return result
