extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.get("objects").size() != 1:
		_fail("Expected a starter cube")
		return
	scene.call("_add_primitive", "Sphere")
	if scene.get("objects").size() != 2:
		_fail("Sphere creation failed")
		return
	scene.call("_set_transform_mode", "Move")
	scene.call("_nudge", "X", 1)
	var item: MeshInstance3D = scene.get("selected")
	if not is_equal_approx(item.position.x, 0.25):
		_fail("Touch-friendly transform failed")
		return
	scene.call("_undo")
	item = scene.get("selected")
	if not is_equal_approx(item.position.x, 0.0):
		_fail("Undo failed")
		return
	scene.call("_redo")
	item = scene.get("selected")
	if not is_equal_approx(item.position.x, 0.25):
		_fail("Redo failed")
		return
	scene.call("_save_project")
	if not FileAccess.file_exists("user://dabsky-project.json"):
		_fail("Save failed")
		return
	scene.call("_new_project")
	if scene.get("objects").size() != 0:
		_fail("New project failed")
		return
	scene.call("_load_project")
	if scene.get("objects").size() != 2:
		_fail("Load failed")
		return
	scene.call("_delete_selected")
	if scene.get("objects").size() != 1:
		_fail("Delete failed")
		return
	print("DABSKY EDITOR SMOKE TEST PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY EDITOR SMOKE TEST FAILED: " + message)
	quit(1)
