extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.call("_enter_workspace")
	await process_frame
	var graphics: VBoxContainer = editor.get("graphics_diagnostics")
	var button: Button = editor.get("graphics_button")
	if graphics == null or button == null:
		_fail("Graphics indicator was not created")
		return
	var report: String = graphics.call("get_report")
	for word in ["DABSKY 3D GRAPHICS REPORT", "Renderer:", "Driver:", "GPU:", "Frames/second:", "Native Android shader errors"]:
		if not report.contains(word):
			_fail("Report missing: " + word)
			return
	var detail_panel: PanelContainer = graphics.get("detail_panel")
	if detail_panel == null or detail_panel.visible:
		_fail("Diagnostics report should start collapsed")
		return
	button.pressed.emit()
	if not detail_panel.visible:
		_fail("Graphics button did not open report")
		return
	graphics.call("sample_fps", 10.0)
	graphics.call("sample_fps", 10.0)
	graphics.call("sample_fps", 10.0)
	if button.text != "Graphics":
		_fail("Single short performance drop must not be flagged")
		return
	graphics.call("sample_fps", 10.0)
	if button.text != "Graphics !":
		_fail("Sustained low FPS did not show in-app warning")
		return
	if not (graphics.call("get_report") as String).contains("sustained low frame rate"):
		_fail("Sustained low FPS warning omitted from report")
		return
	graphics.call("sample_fps", 35.0)
	graphics.call("sample_fps", 35.0)
	if button.text != "Graphics":
		_fail("Recovered FPS did not clear current warning")
		return
	if not (graphics.call("get_report") as String).contains("Recent symptoms"):
		_fail("Past performance symptom was not retained")
		return
	button.pressed.emit()
	if detail_panel.visible:
		_fail("Graphics button did not close report")
		return
	print("DABSKY GRAPHICS REPORT / FPS WARNING / RECOVERY / COLLAPSIBLE PANEL PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY GRAPHICS DIAGNOSTICS TEST FAILED: " + message)
	quit(1)
