extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func touch(index: int, where: Vector2, down: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = where
	e.pressed = down
	return e

func drag(index: int, where: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = where
	return e

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.call("_enter_workspace")
	await process_frame
	var container: Control = editor.get("viewport_container")
	var rect := container.get_global_rect()
	if rect.size.x < 150 or rect.size.y < 100:
		_fail("3D viewport did not lay out for headless gesture test")
		return

	editor.call("_reset_view")
	var initial_distance: float = editor.get("orbit_distance")
	var initial_yaw: float = editor.get("orbit_yaw")
	var initial_pitch: float = editor.get("orbit_pitch")
	var p1 := rect.position + Vector2(rect.size.x * 0.40, rect.size.y * 0.48)
	var p2 := rect.position + Vector2(rect.size.x * 0.60, rect.size.y * 0.48)
	editor.call("_input", touch(0, p1, true))
	editor.call("_input", touch(1, p2, true))
	var p2_out := rect.position + Vector2(rect.size.x * 0.73, rect.size.y * 0.48)
	editor.call("_input", drag(1, p2_out))
	var closer: float = editor.get("orbit_distance")
	if not (closer < initial_distance):
		_fail("Pinch-out must zoom in: %s -> %s" % [initial_distance, closer])
		return
	if not is_equal_approx(float(editor.get("orbit_yaw")), initial_y) or not is_equal_approx(float(editor.get("orbit_pitch")), initial_pitch):
		_fail("Two finger zoom must not orbit camera")
		return
	var p2_in := rect.position + Vector2(rect.size.x * 0.46, rect.size.y * 0.48)
	editor.call("_input", drag(1, p2_in))
	if float(editor.get("orbit_distance")) <= closer:
		_fail("Pinch-in must zoom out")
		return

	# Releasing a finger after a pinch should NOT select objects.
	editor.call("_select_object", null)
	editor.call("_input", touch(1, p2_in, false))
	editor.call("_input", touch(0, p1, false))
	if editor.get("selected") != null:
		_fail("Pinch release accidentally selected an object")
		return
	var active: Dictionary = editor.get("active_touches")
	if not active.is_empty():
		_fail("Touch pointer tracking was not cleared")
		return

	# A new single-finger drag should orbit without changing zoom.
	editor.call("_input", touch(0, p1, true))
	var p1_move := p1 + Vector2(52, 22)
	editor.call("_input", drag(0, p1_move))
	editor.call("_input", touch(0, p1_move, false))
	if is_equal_approx(float(editor.get("orbit_yaw")), initial_yaw):
		_fail("Single finger dragging stopped orbiting")
		return

	# Zoom buttons and scroll input clamp the distance and preserve transforms.
	editor.call("_reset_view")
	for i in range(200):
		editor.call("_zoom_by_ratio", 0.5)
	if not is_equal_approx(float(editor.get("orbit_distance")), 0.65):
		_fail("Zoom in cap does not work")
		return
	for i in range(200):
		editor.call("_zoom_by_ratio", 2.0)
	if not is_equal_approx(float(editor.get("orbit_distance")), 80.0):
		_fail("Zoom out cap does not work")
		return
	var zoom_before: float = editor.get("orbit_distance")
	editor.call("_zoom_by_ratio", -3.0)
	if not is_equal_approx(float(editor.get("orbit_distance")), zoom_before):
		_fail("Invalid zoom ratio must be ignored")
		return
	editor.call("_reset_view")
	if not is_equal_approx(float(editor.get("orbit_distance")), initial_distance):
		_fail("Reset View no longer resets camera zoom")
		return
	var selected: MeshInstance3D = editor.get("selected")
	if selected != null and selected.position != Vector3.ZERO:
		_fail("Pinch zoom modified the mesh position")
		return
	print("DABSKY TOUCH PINCH / ORBIT / ZOOM LIMITS / TAP SUPPRESSION PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY TOUCH CAMERA TEST FAILED: " + message)
	quit(1)
