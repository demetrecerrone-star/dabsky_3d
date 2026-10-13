extends VBoxContainer
# Non-invasive diagnostics for exported Android builds.
# Godot/Android native shader-driver errors are not exposed as catchable
# GDScript exceptions. This panel reports observable runtime symptoms and
# renderer/device metadata without claiming access to native logcat.

const LOW_FPS_LIMIT := 18.0
const FPS_RECOVER_LIMIT := 25.0
const LOW_FPS_SECONDS := 4
const WARNING_HISTORY_LIMIT := 6

var diagnostics_button: Button
var scene_viewport: SubViewport
var scene_camera: Camera3D
var detail_panel: PanelContainer
var report_label: Label
var copy_status: Label

var last_fps := -1.0
var seconds_running := 0.0
var sample_accumulator := 0.0
var consecutive_slow_samples := 0
var consecutive_recovered_samples := 0
var performance_warning := false
var warning_history: Array[String] = []
var last_event := ""

func _ready() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.visible = false
	add_child(detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	detail_panel.add_child(column)
	var caption := Label.new()
	caption.text = "Graphics Diagnostics · live device report"
	caption.add_theme_font_size_override("font_size", 16)
	column.add_child(caption)
	var info_scroll := ScrollContainer.new()
	info_scroll.custom_minimum_size.y = 132.0
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	info_scroll.scroll_deadzone = 15
	column.add_child(info_scroll)
	report_label = Label.new()
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_label.mouse_filter = Control.MOUSE_FILTER_PASS
	report_label.add_theme_font_size_override("font_size", 14)
	info_scroll.add_child(report_label)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var copy := Button.new()
	copy.text = "Copy Report"
	copy.custom_minimum_size = Vector2(110, 44)
	copy.pressed.connect(_copy_report)
	actions.add_child(copy)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.custom_minimum_size = Vector2(90, 44)
	refresh.pressed.connect(refresh_report)
	actions.add_child(refresh)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(90, 44)
	close.pressed.connect(toggle_panel)
	actions.add_child(close)
	copy_status = Label.new()
	copy_status.text = ""
	column.add_child(copy_status)
	refresh_report()

func configure(button: Button, target_viewport: SubViewport, target_camera: Camera3D) -> void:
	diagnostics_button = button
	scene_viewport = target_viewport
	scene_camera = target_camera
	refresh_report()

func toggle_panel() -> void:
	detail_panel.visible = not detail_panel.visible
	if detail_panel.visible:
		refresh_report()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or scene_viewport == null:
		return
	seconds_running += delta
	sample_accumulator += delta
	if sample_accumulator < 1.0:
		return
	sample_accumulator = 0.0
	# Ignore startup shader compilation/initialization when classifying stalls.
	if seconds_running >= 3.0:
		sample_fps(Engine.get_frames_per_second())
	else:
		refresh_report()

func sample_fps(fps: float) -> void:
	# A low FPS reading is a *performance symptom*, not proof of a shader error.
	if not is_finite(fps) or fps < 0.0:
		return
	last_fps = fps
	if fps < LOW_FPS_LIMIT:
		consecutive_slow_samples += 1
		consecutive_recovered_samples = 0
		if consecutive_slow_samples >= LOW_FPS_SECONDS and not performance_warning:
			performance_warning = true
			_record_warning("Sustained slow 3D display: below 18 FPS for 4 samples.")
	else:
		consecutive_slow_samples = 0
		if fps >= FPS_RECOVER_LIMIT:
			consecutive_recovered_samples += 1
			if consecutive_recovered_samples >= 2:
				performance_warning = false
		else:
			consecutive_recovered_samples = 0
	refresh_report()

func _record_warning(message: String) -> void:
	if warning_history.is_empty() or warning_history[-1] != message:
		warning_history.append(message)
		if warning_history.size() > WARNING_HISTORY_LIMIT:
			warning_history.pop_front()

func _viewport_problem() -> bool:
	if scene_viewport == null or not is_instance_valid(scene_viewport):
		return true
	if scene_viewport.size.x < 32 or scene_viewport.size.y < 32:
		return true
	if scene_camera == null or not is_instance_valid(scene_camera):
		return true
	return not scene_camera.current

func get_report() -> String:
	var engine_version := str(Engine.get_version_info().get("string", "unknown"))
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var gpu := RenderingServer.get_video_adapter_name()
	var gpu_vendor := RenderingServer.get_video_adapter_vendor()
	var api := RenderingServer.get_video_adapter_api_version()
	if gpu.is_empty():
		gpu = "Unavailable (headless or restricted)"
	if gpu_vendor.is_empty():
		gpu_vendor = "Unavailable"
	if api.is_empty():
		api = "Unavailable"
	var report := "DABSKY 3D GRAPHICS REPORT\n"
	report += "Godot: %s | OS: %s\n" % [engine_version, OS.get_name()]
	report += "Renderer: %s | Driver: %s\n" % [method, driver]
	report += "GPU: %s | Vendor: %s\n" % [gpu, gpu_vendor]
	report += "Graphics API: %s\n" % api
	if last_fps >= 0.0:
		report += "Frames/second (recent): %.0f\n" % last_fps
	else:
		report += "Frames/second: collecting samples\n"
	if scene_viewport != null and is_instance_valid(scene_viewport):
		report += "3D viewport size: %d x %d\n" % [scene_viewport.size.x, scene_viewport.size.y]
	else:
		report += "3D viewport: not configured\n"
	if _viewport_problem():
		report += "OBSERVED WARNING: 3D viewport or camera is unavailable.\n"
	if performance_warning:
		report += "OBSERVED WARNING: sustained low frame rate.\n"
	if not _viewport_problem() and not performance_warning:
		report += "No current in-app performance/viewport warning (not a shader validation).\n"
	if not warning_history.is_empty():
		report += "Recent symptoms: " + " | ".join(PackedStringArray(warning_history)) + "\n"
	report += "Native Android shader errors and GPU driver logs cannot be read here.\n"
	report += "If geometry is blank or flickers, capture a screenshot and Android logcat for investigation."
	return report

func refresh_report() -> void:
	if report_label != null:
		report_label.text = get_report()
	if diagnostics_button == null:
		return
	if _viewport_problem() or performance_warning:
		diagnostics_button.text = "Graphics !"
		diagnostics_button.tooltip_text = "Graphics Diagnostics detected a viewport or FPS warning"
	else:
		diagnostics_button.text = "Graphics"
		diagnostics_button.tooltip_text = "Open graphics report (cannot capture Android driver logs)"

func _copy_report() -> void:
	DisplayServer.clipboard_set(get_report())
	if copy_status != null:
		copy_status.text = "Graphics report copied. Paste it into our chat."
