extends SceneTree

const MeshEdit = preload("res://scripts/mesh_edit.gd")

func _initialize() -> void:
	call_deferred("_verify")

func touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event

func drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.call("_enter_workspace")
	await process_frame
	var selected: MeshInstance3D = editor.get("selected")
	if selected == null:
		_fail("Missing default mesh")
		return
	var old_position := selected.position
	selected.position = Vector3(11, 2, -7)
	editor.call("_fit_model_to_view")
	var target: Vector3 = editor.get("orbit_target")
	if target.distance_to(selected.global_position) > 0.5:
		_fail("Fit Model did not center the selected mesh: %s" % target)
		return
	if selected.position != Vector3(11, 2, -7):
		_fail("Fit Model changed the mesh instead of the camera")
		return
	var distance: float = editor.get("orbit_distance")
	if distance <= 0.65 or distance >= 80.0:
		_fail("Fit Model camera distance outside allowed range")
		return
	var rect: Rect2 = (editor.get("viewport_container") as Control).get_global_rect()
	var p1 := rect.position + rect.size * Vector2(0.40, 0.5)
	var p2 := rect.position + rect.size * Vector2(0.60, 0.5)
	var yaw: float = editor.get("orbit_yaw")
	var pitch: float = editor.get("orbit_pitch")
	editor.call("_input", touch(0, p1, true))
	editor.call("_input", touch(1, p2, true))
	var delta := Vector2(40, 28)
	editor.call("_input", drag(0, p1 + delta))
	editor.call("_input", drag(1, p2 + delta))
	var panned: Vector3 = editor.get("orbit_target")
	if panned.distance_to(target) < 0.02:
		_fail("Two-finger translation did not pan the camera target")
		return
	if not is_equal_approx(float(editor.get("orbit_yaw")), yaw) or not is_equal_approx(float(editor.get("orbit_pitch")), pitch):
		_fail("Panning should not rotate the camera")
		return
	if selected.position != Vector3(11, 2, -7):
		_fail("Panning changed the selected mesh transform")
		return
	editor.call("_input", touch(1, p2 + delta, false))
	editor.call("_input", touch(0, p1 + delta, false))
	if not (editor.get("active_touches") as Dictionary).is_empty():
		_fail("Touch pointers leaked after pan")
		return
	# Moving a tap a few pixels away from a corner should still snap to it.
	editor.call("_set_mesh_mode", "Vertex")
	var data: Dictionary = MeshEdit._surface_data(selected.mesh, 0)
	if data.is_empty():
		_fail("Cube surface has no pickable vertices")
		return
	var vertices: PackedVector3Array = data["positions"]
	var point: Vector3 = selected.global_transform * vertices[0]
	var camera: Camera3D = editor.get("camera")
	var uv: Vector2 = camera.unproject_position(point)
	var subviewport: SubViewport = editor.get("viewport")
	var click: Vector2 = rect.position + uv * rect.size / Vector2(subviewport.size) + Vector2(12, 0)
	var snapped: Dictionary = editor.call("_nearest_touch_vertex", click)
	if snapped.is_empty():
		_fail("Touch-tolerant vertex selection missed a nearby corner")
		return
	var picked: Vector3 = snapped["vertex"]
	if picked.distance_to(vertices[0]) > 1.8:
		_fail("Nearest screen-space vertex was not located")
		return
	selected.position = old_position
	print("DABSKY TWO FINGER PAN / FIT MODEL / VERTEX TOUCH TARGET PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY VIEWPORT UX TEST FAILED: " + message)
	quit(1)
