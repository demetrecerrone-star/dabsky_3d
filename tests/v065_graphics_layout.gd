extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.call("_enter_workspace")
	await process_frame
	await process_frame
	var rect: Control = editor.get("viewport_container")
	var graphics: VBoxContainer = editor.get("graphics_diagnostics")
	var overlay: Control = editor.get("graphics_overlay")
	var button: Button = editor.get("graphics_button")
	var fps_label: Label = editor.get("graphics_fps_label")
	if rect == null or graphics == null or overlay == null or button == null or fps_label == null:
		_fail("Graphics overlay or live FPS label was not created")
		return
	if graphics.get_parent() != overlay:
		_fail("Graphics diagnostics is still inside the workspace vertical layout")
		return
	var before := rect.size.y
	if before < 160:
		_fail("3D view already collapsed before opening diagnostics: %d" % before)
		return
	button.pressed.emit()
	await process_frame
	await process_frame
	var after := rect.size.y
	if absf(after - before) > 2.0:
		_fail("Opening Graphics reduced 3D viewport height: %.1f -> %.1f" % [before, after])
		return
	if not graphics.get("detail_panel").visible:
		_fail("Graphics report did not open")
		return
	graphics.call("sample_fps", 120.0)
	if fps_label.text != "FPS 120":
		_fail("Always-visible FPS label failed to update")
		return
	# Godot forbids directly resizing a SubViewport when its parent stretches it.
	# Substitute an independent viewport to reproduce the real phone's dimensions.
	var original: SubViewport = graphics.get("scene_viewport")
	var simulated := SubViewport.new()
	simulated.size = Vector2i(1461, 78)
	graphics.set("scene_viewport", simulated)
	graphics.call("refresh_report")
	if button.text != "Graphics !":
		_fail("Thin 1461 by 78 viewport should trigger Graphics warning")
		return
	if not (graphics.call("get_report") as String).contains("OBSERVED WARNING"):
		_fail("Collapsed viewport was not included in copyable report")
		return
	graphics.set("scene_viewport", original)
	graphics.call("refresh_report")
	print("DABSKY RESPONSIVE GRAPHICS OVERLAY / VIEWPORT SIZE / LIVE FPS PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY GRAPHICS LAYOUT TEST FAILED: " + message)
	quit(1)
