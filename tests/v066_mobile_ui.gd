extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error("DABSKY MOBILE UI TEST FAILED: " + message)
	quit(1)

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.call("_enter_workspace")
	await process_frame
	await process_frame
	var view: Control = editor.get("viewport_container")
	var create_tools: ScrollContainer = editor.get("create_tools")
	var project_tools: ScrollContainer = editor.get("project_tools")
	var transform_tools: ScrollContainer = editor.get("transform_tools")
	var edit_tools: ScrollContainer = editor.get("mesh_tools_container")
	var categories: Dictionary = editor.get("category_buttons")
	if categories.size() != 6:
		_fail("Expected six clearly labeled tool categories")
		return
	var initial_zoom: float = editor.get("orbit_distance")
	if initial_zoom >= 8.0 or initial_zoom <= 0.65:
		_fail("Starting camera failed to fit starter cube: %0.2f" % initial_zoom)
		return
	for name in ["Create", "Project", "Transform", "Edit", "Materials", "AI"]:
		editor.call("_set_tool_category", name)
		await process_frame
		var actual := [create_tools.visible, project_tools.visible, transform_tools.visible, edit_tools.visible]
		var expected := [name == "Create", name == "Project", name == "Transform", name == "Edit"]
		if actual != expected:
			_fail("Multiple toolbars visible under " + name + ": " + str(actual))
			return
		var active_button: Button = categories[name]
		if not active_button.button_pressed:
			_fail("Active category not highlighted: " + name)
			return
		if (editor.get("material_panel") as Control).visible != (name == "Materials"):
			_fail("Materials inspector visibility wrong for " + name)
			return
		if (editor.get("ai_panel") as Control).visible != (name == "AI"):
			_fail("AI inspector visibility wrong for " + name)
			return
		if view.size.y < 160.0:
			_fail("Modeling viewport squeezed by " + name)
			return
	editor.call("_set_tool_category", "Create")
	await process_frame
	var graphics: VBoxContainer = editor.get("graphics_diagnostics")
	var button: Button = editor.get("graphics_button")
	var before_height := view.size.y
	button.pressed.emit()
	await process_frame
	await process_frame
	if absf(view.size.y - before_height) > 2.0:
		_fail("Graphics panel stole viewport height")
		return
	var origin := graphics.position
	graphics.call("_move_panel_by", Vector2(-100.0, 22.0))
	if graphics.position.distance_to(origin) < 10.0:
		_fail("Floating Graphics panel could not move")
		return
	if not bool(graphics.get("panel_was_moved")):
		_fail("Moved floating panel did not record drag")
		return
	graphics.call("_move_panel_by", Vector2(-10000.0, 10000.0))
	var overlay: Control = editor.get("graphics_overlay")
	if graphics.position.x < -0.5 or graphics.position.y < -0.5 or graphics.position.x + graphics.size.x > overlay.size.x + 1.0 or graphics.position.y + graphics.size.y > overlay.size.y + 1.0:
		_fail("Graphics panel escaped usable screen boundaries")
		return
	if absf(view.size.y - before_height) > 2.0:
		_fail("Moving diagnostics changed viewport dimensions")
		return
	button.pressed.emit()
	print("DABSKY CATEGORIZED TOOLBARS / START FIT / DRAGGABLE REPORT / VIEWPORT PRIORITY PASSED")
	quit(0)
