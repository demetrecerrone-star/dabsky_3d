extends SceneTree

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
	var rows: Array = editor.get("touch_scroll_toolbars")
	if rows.size() != 4:
		_fail("Expected four swipeable toolbars (Create, Project, Transform, Edit)")
		return
	for scroll in rows:
		if scroll.scroll_deadzone != 18:
			_fail("Missing finger-drag deadzone")
			return
		var contents: HBoxContainer = scroll.get_child(0) as HBoxContainer
		if contents == null or contents.mouse_filter != Control.MOUSE_FILTER_PASS:
			_fail("Toolbar row must pass swipe events to ScrollContainer")
			return
		for child in contents.get_children():
			if child is Button and child.mouse_filter != Control.MOUSE_FILTER_PASS:
				_fail("Toolbar button consumes touch drag events: " + child.text)
				return
	var top: ScrollContainer = rows[0]
	var first_button: Button = top.get_child(0).get_child(0)
	var original_count: int = editor.get("objects").size()
	var p := top.get_global_rect().get_center()
	editor.call("_input", touch(0, p, true))
	editor.call("_input", drag(0, p + Vector2(-75, 0)))
	editor.call("_input", touch(0, p + Vector2(-75, 0), false))
	first_button.pressed.emit()
	if editor.get("objects").size() != original_count:
		_fail("Swiping triggered a modeling action")
		return
	editor.call("_input", touch(0, p, true))
	editor.call("_input", touch(0, p, false))
	first_button.pressed.emit()
	if editor.get("objects").size() != original_count + 1:
		_fail("A tap after a swipe no longer activates a button")
		return
	var pointers: Dictionary = editor.get("active_touches")
	if not pointers.is_empty():
		_fail("Toolbar swipe leaked into camera gesture state")
		return
	print("DABSKY ANDROID TOOLBAR SWIPE / BUTTON TAP PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY TOOLBAR SCROLL TEST FAILED: " + message)
	quit(1)
