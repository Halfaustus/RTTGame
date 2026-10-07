class_name UnitTaskQueue
extends RefCounted

# Server-only storage. Callers validate identity and eligibility before mutation.
var tasks: Dictionary = {}
var revision := 0

func submit(id: int, command: Dictionary, append: bool) -> void:
	if not append: tasks.erase(id)
	if not tasks.has(id): tasks[id] = []
	tasks[id].append(command.duplicate(true))
	revision += 1

func current(id: int) -> Dictionary:
	return tasks[id][0] if tasks.has(id) and not tasks[id].is_empty() else {}

func finish(id: int) -> void:
	if not tasks.has(id): return
	tasks[id].pop_front()
	if tasks[id].is_empty(): tasks.erase(id)
	revision += 1

func cancel(id: int) -> void:
	if tasks.erase(id): revision += 1

func projection(id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task: Dictionary in tasks.get(id, []):
		result.append({"type":task.type,"target":task.target,"mode":task.mode,"path":task.get("path",PackedVector3Array()).duplicate()})
	return result
