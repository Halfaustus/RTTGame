extends "res://tests/db29_projectile_test.gd"

func run() -> void:
	var world=load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	root.add_child(world)
	var camera=world.get_node("Units/Camera3D")
	camera.set_process(false)
	check(camera.config==preload("res://data/db37_active_test_camera.tres"),"activity opts into independent test camera")
	check(camera.config.maximum_distance==500 and camera.config.resource_name.begins_with("TEST ONLY"),"higher zoom limit remains test-only")
	camera._distance=6
	camera._pitch=deg_to_rad(20)
	camera._apply_view()
	check(absf(camera.pan_speed()-18)<0.0001,"lowest altitude retains fine 18m/s control")
	camera._distance=500
	camera._pitch=deg_to_rad(80)
	camera._apply_view()
	check(absf(camera.pan_speed()-140)<0.0001 and camera.global_position.y>490,"highest altitude reaches 140m/s and over 490m height")
	for corner in [Vector3(-200,0,-200),Vector3(-200,0,200),Vector3(200,0,-200),Vector3(200,0,200)]:
		check(not camera.is_position_behind(corner) and camera.get_viewport().get_visible_rect().has_point(camera.unproject_position(corner)),"highest view contains map corner %s" % corner)
	camera._movement_keys[KEY_D]=true
	camera._center=Vector3(-200,0,0)
	camera._advance_pan(400.0/140)
	check(absf(camera._center.x-200)<0.0001,"high camera crosses 400m in 2.86s")
	camera._movement_keys.clear()
	for axis in [KEY_W,KEY_A,KEY_S,KEY_D]:
		camera._center=Vector3.ZERO
		camera._movement_keys[axis]=true
		camera._advance_pan(100)
		camera._movement_keys.clear()
		check(absf(camera._center.x)<=200 and absf(camera._center.z)<=200,"ground focus clamps at activity boundary %s" % axis)
	camera._center=Vector3.ZERO
	camera._distance=6
	camera._pitch=deg_to_rad(20)
	camera._movement_keys[KEY_D]=true
	camera._advance_pan(1.0/60)
	check(absf(camera._center.x-0.3)<0.0001,"low camera fine per-frame displacement")
	camera._movement_keys.clear()
	camera._distance=250
	camera._pitch=deg_to_rad(45)
	check(camera.pan_speed()>50 and camera.pan_speed()<80,"medium altitude has tactical speed")
	camera._distance=6
	for notch in range(40): camera._zoom(1)
	check(camera._distance==500,"scaled zoom reaches full map range without hundreds of notches")
	for notch in range(40): camera._zoom(-1)
	check(camera._distance==6,"zoom remains clamped at minimum")
	camera._distance=500
	camera._pitch=deg_to_rad(80)
	camera._center=Vector3(25,0,-25)
	camera._apply_view()
	var screen: Vector2=camera.get_viewport().get_visible_rect().size*0.5
	var ground: Variant=world._ground_at(screen)
	check(ground is Vector3 and ground.distance_to(camera._center)<0.001,"highest camera ground pick still hits focus")
	var pick:=Vector3(100,0,-100)
	var picked: Variant=world._ground_at(camera.unproject_position(pick))
	check(picked is Vector3 and picked.distance_to(pick)<0.001,"high camera preserves arbitrary world ground coordinates")
	check(world._deployment_ui._camera==camera and camera.battlefield_config==world.movement_config,"deployment and combat share bounded map camera")
	var old=load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(old)
	var legacy=old.get_node("Units/Camera3D")
	legacy.set_process(false)
	check(legacy.config==preload("res://data/prototype_camera.tres") and not legacy.config.height_scaled_pan,"old scene retains old camera resource")
	legacy._distance=60
	legacy._pitch=deg_to_rad(80)
	check(legacy.pan_speed()==18,"legacy speed remains independent of pitch/zoom")
	legacy._zoom(-1)
	check(legacy._distance==58,"legacy fixed 2m zoom remains unchanged")
	check(world.movement_config.minimum_xz==Vector2(-200,-200) and world.movement_config.maximum_xz==Vector2(200,200),"map geometry size unchanged")
	old.free()
	world.free()
	print("Activity camera: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
