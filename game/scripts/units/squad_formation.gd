class_name SquadFormation
extends RefCounted

static func slots(count: int, spacing: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	if count <= 0: return result
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(count / float(columns))
	for index: int in count:
		var row := index / columns
		var row_count := mini(columns,count-row*columns)
		result.append(Vector3((index % columns-(row_count-1)*0.5)*spacing,0,(row-(rows-1)*0.5)*spacing))
	return result
