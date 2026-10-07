class_name TemporaryUnitBadge
extends RefCounted

# Independently authored, replaceable geometry; no external artwork or unit data.
static func role_for(definition: String) -> String:
	for role: String in ["suppression","modules","top","normal","manual","mechanical"]:
		if definition == "res://data/units/acceptance_06c_%s.tres" % role: return role
	return ""

static func caption(role: String) -> String:
	return {"normal":"HE","top":"TOP","suppression":"SUP","modules":"MOD","manual":"MAN","mechanical":"MEC"}.get(role,"")

static func draw_badge(canvas: CanvasItem, center: Vector2, armored: bool) -> void:
	if armored:
		canvas.draw_rect(Rect2(center-Vector2(10,5),Vector2(20,10)),Color.WHITE,false,2)
		canvas.draw_line(center,center+Vector2(0,-10),Color.WHITE,2)
	else:
		canvas.draw_circle(center+Vector2(0,-6),3,Color.WHITE)
		canvas.draw_line(center+Vector2(-8,7),center+Vector2(0,-1),Color.WHITE,2)
		canvas.draw_line(center+Vector2(0,-1),center+Vector2(8,7),Color.WHITE,2)
