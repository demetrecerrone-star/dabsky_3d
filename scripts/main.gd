extends Control

var selected: MeshInstance3D
var viewport: SubViewport
var scene_root: Node3D
var command_input: LineEdit
var status: Label
var previous_transform: Transform3D
var preview_active := false
var undo_stack: Array[Transform3D] = []
var orbit_yaw := 0.55
var orbit_pitch := 0.35
var orbit_distance := 8.0
var camera: Camera3D
var menu_layer: Control
var workspace_layer: MarginContainer
var menu_safe: MarginContainer
var menu_logo: TextureRect
var menu_heading: Label
var menu_start: Button
var menu_box: VBoxContainer
var menu_fit_label: Label
var viewport_container: SubViewportContainer
var screen_fit_extra := 0
const SCREEN_FIT_STEP := 8
const SCREEN_FIT_MAX := 80
var menu_video: VideoStreamPlayer
var dragging := false
var last_touch := Vector2.ZERO

func _ready() -> void:
	get_viewport().gui_embed_subwindows = true
	_load_screen_fit()
	_build_menu()
	workspace_layer = MarginContainer.new()
	workspace_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(workspace_layer)
	workspace_layer.visible = false
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	workspace_layer.add_child(layout)
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 7)
	toolbar.add_theme_constant_override("v_separation", 5)
	layout.add_child(toolbar)
	_add_button(toolbar, "Add Cube", _add_cube)
	_add_button(toolbar, "Undo", _undo)
	_add_button(toolbar, "Reset View", _reset_view)
	_add_button(toolbar, "Fit -", func(): _adjust_screen_fit(-SCREEN_FIT_STEP))
	_add_button(toolbar, "Fit +", func(): _adjust_screen_fit(SCREEN_FIT_STEP))
	viewport_container = SubViewportContainer.new()
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	layout.add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	scene_root = Node3D.new()
	viewport.add_child(scene_root)
	camera = Camera3D.new()
	scene_root.add_child(camera)
	_update_camera()
	camera.current = true
	var light := DirectionalLight3D.new()
	scene_root.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	_add_grid()
	command_input = LineEdit.new()
	command_input.placeholder_text = "Example: move up 2"
	command_input.custom_minimum_size.y = 48
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(command_input)
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 7)
	controls.add_theme_constant_override("v_separation", 5)
	layout.add_child(controls)
	_add_button(controls, "Preview", _preview)
	_add_button(controls, "Apply", _apply)
	_add_button(controls, "Cancel", _cancel)
	status = Label.new()
	status.text = "Drag to orbit the view. Try: move up 2, rotate y 45, scale 2."
	status.add_theme_font_size_override("font_size", 16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	layout.add_child(status)
	_add_cube()
	get_viewport().size_changed.connect(_refresh_screen_fit)
	call_deferred("_refresh_screen_fit")

func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(90, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_cube() -> void:
	_cancel()
	selected = MeshInstance3D.new()
	selected.mesh = BoxMesh.new()
	scene_root.add_child(selected)
	undo_stack.clear()
	status.text = "Cube selected. Drag the viewport to orbit."

func _preview() -> void:
	if selected == null:
		status.text = "Add a cube first."
		return
	_cancel()
	var words := command_input.text.strip_edges().to_lower().split(" ", false)
	if words.size() < 2 or not words[words.size() - 1].is_valid_float():
		status.text = "Use a command ending with a number."
		return
	var value := float(words[words.size() - 1])
	if not is_finite(value) or absf(value) > 1000.0:
		status.text = "Invalid number."
		return
	var axis := Vector3.UP
	if words.size() >= 3:
		match words[1]:
			"x", "right": axis = Vector3.RIGHT
			"y", "up": axis = Vector3.UP
			"z", "forward": axis = Vector3.FORWARD
			"down": axis = Vector3.DOWN
	previous_transform = selected.transform
	var valid := true
	match words[0]:
		"move": selected.position += axis * value
		"rotate": selected.rotate_object_local(axis, deg_to_rad(value))
		"scale":
			if value <= 0.0: valid = false
			else: selected.scale *= value
		"height":
			if value <= 0.0: valid = false
			else: selected.scale.y *= value
		_: valid = false
	if not valid:
		selected.transform = previous_transform
		status.text = "Unsupported command."
		return
	preview_active = true
	status.text = "Preview active. Apply or Cancel."

func _apply() -> void:
	if preview_active:
		undo_stack.append(previous_transform)
		preview_active = false
		status.text = "Change applied."

func _cancel() -> void:
	if preview_active and selected != null:
		selected.transform = previous_transform
	preview_active = false

func _undo() -> void:
	if preview_active:
		_cancel()
		status.text = "Preview canceled."
	elif selected != null and not undo_stack.is_empty():
		selected.transform = undo_stack.pop_back()
		status.text = "Undone."

func _add_grid() -> void:
	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = Color(0.36, 0.41, 0.47)
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for i in range(-10, 11):
		mesh.surface_add_vertex(Vector3(i, -0.52, -10))
		mesh.surface_add_vertex(Vector3(i, -0.52, 10))
		mesh.surface_add_vertex(Vector3(-10, -0.52, i))
		mesh.surface_add_vertex(Vector3(10, -0.52, i))
	mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = mesh
	scene_root.add_child(grid)

func _update_camera() -> void:
	if camera == null:
		return
	camera.position = Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * orbit_distance
	camera.look_at(Vector3.ZERO)

func _reset_view() -> void:
	orbit_yaw = 0.55
	orbit_pitch = 0.35
	orbit_distance = 8.0
	_update_camera()

func _input(event: InputEvent) -> void:
	if workspace_layer == null or not workspace_layer.visible:
		dragging = false
		return
	if event is InputEventScreenTouch:
		dragging = event.pressed and viewport_container.get_global_rect().has_point(event.position)
		last_touch = event.position
	elif event is InputEventScreenDrag and dragging:
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.008, -1.25, 1.25)
		_update_camera()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed and viewport_container.get_global_rect().has_point(event.position)
			last_touch = event.position
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(2.0, orbit_distance - 0.7)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(25.0, orbit_distance + 0.7)
			_update_camera()
	elif event is InputEventMouseMotion and dragging:
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.008, -1.25, 1.25)
		_update_camera()

func _build_menu() -> void:
	menu_layer = Control.new()
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_layer)
	var background := ColorRect.new()
	background.color = Color(0.075, 0.035, 0.14)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(background)
	if ResourceLoader.exists("res://assets/dabsky-menu-loop.ogv"):
		menu_video = VideoStreamPlayer.new()
		menu_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		menu_video.expand = true
		menu_video.volume_db = -80.0
		menu_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu_video.stream = load("res://assets/dabsky-menu-loop.ogv")
		menu_video.finished.connect(func(): menu_video.play())
		menu_layer.add_child(menu_video)
		menu_video.play()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.46)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(shade)
	menu_safe = MarginContainer.new()
	menu_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(menu_safe)
	var centered := CenterContainer.new()
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centered.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_safe.add_child(centered)
	menu_box = VBoxContainer.new()
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_theme_constant_override("separation", 12)
	centered.add_child(menu_box)
	if ResourceLoader.exists("res://assets/dabsky-icon.png"):
		menu_logo = TextureRect.new()
		menu_logo.texture = load("res://assets/dabsky-icon.png")
		menu_logo.custom_minimum_size = Vector2(110, 110)
		menu_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		menu_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		menu_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu_box.add_child(menu_logo)
	menu_heading = Label.new()
	menu_heading.text = "DABSKY 3D STUDIO"
	menu_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_heading.add_theme_font_size_override("font_size", 30)
	menu_box.add_child(menu_heading)
	menu_start = Button.new()
	menu_start.text = "START MODELING"
	menu_start.custom_minimum_size = Vector2(280, 60)
	menu_start.add_theme_font_size_override("font_size", 22)
	menu_start.pressed.connect(_enter_workspace)
	menu_box.add_child(menu_start)
	var fit_row := HBoxContainer.new()
	fit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fit_row.add_theme_constant_override("separation", 6)
	menu_box.add_child(fit_row)
	_add_fit_button(fit_row, "-", -SCREEN_FIT_STEP)
	menu_fit_label = Label.new()
	menu_fit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_fit_label.custom_minimum_size.x = 120
	menu_fit_label.add_theme_font_size_override("font_size", 15)
	fit_row.add_child(menu_fit_label)
	_add_fit_button(fit_row, "+", SCREEN_FIT_STEP)
	_update_fit_label()

func _add_fit_button(parent: Control, label: String, amount: int) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(48, 42)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(func(): _adjust_screen_fit(amount))
	parent.add_child(button)

func _load_screen_fit() -> void:
	var config := ConfigFile.new()
	if config.load("user://screen_fit.cfg") == OK:
		screen_fit_extra = clampi(int(config.get_value("layout", "extra_padding", 0)), 0, SCREEN_FIT_MAX)

func _adjust_screen_fit(amount: int) -> void:
	screen_fit_extra = clampi(screen_fit_extra + amount, 0, SCREEN_FIT_MAX)
	var config := ConfigFile.new()
	config.set_value("layout", "extra_padding", screen_fit_extra)
	config.save("user://screen_fit.cfg")
	_refresh_screen_fit()

func _update_fit_label() -> void:
	if menu_fit_label != null:
		if screen_fit_extra == 0:
			menu_fit_label.text = "Screen Fit: Auto"
		else:
			menu_fit_label.text = "Screen Fit: +%d" % screen_fit_extra

func _refresh_screen_fit() -> void:
	if menu_safe == null or workspace_layer == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# Godot reports Android cutouts/system-bar-safe bounds in physical pixels.
	# Intersect with the app's actual native window: OS bars already outside the
	# window must not be subtracted twice.
	var native_insets := Vector4.ZERO
	if OS.get_name() == "Android":
		var window_position := DisplayServer.window_get_position()
		var window_size := DisplayServer.window_get_size()
		var safe_area := DisplayServer.get_display_safe_area()
		if window_size.x > 0 and window_size.y > 0 and safe_area.has_area():
			var screen_origin := DisplayServer.screen_get_position()
			var physical_safe := Rect2i(safe_area.position + screen_origin, safe_area.size)
			var window_rect := Rect2i(window_position, window_size)
			var visible_safe := physical_safe.intersection(window_rect)
			if visible_safe.has_area():
				var sx := viewport_size.x / float(window_size.x)
				var sy := viewport_size.y / float(window_size.y)
				native_insets = Vector4(
					maxf(0.0, float(visible_safe.position.x - window_position.x) * sx),
					maxf(0.0, float(visible_safe.position.y - window_position.y) * sy),
					maxf(0.0, float(window_rect.end.x - visible_safe.end.x) * sx),
					maxf(0.0, float(window_rect.end.y - visible_safe.end.y) * sy)
				)
	# Keep a basic corner cushion even when the OS has no safe-area data.
	var base_padding := maxf(18.0, minf(viewport_size.x, viewport_size.y) * 0.03)
	var left := ceili(base_padding + screen_fit_extra + native_insets.x)
	var top := ceili(base_padding + screen_fit_extra + native_insets.y)
	var right := ceili(base_padding + screen_fit_extra + native_insets.z)
	var bottom := ceili(base_padding + screen_fit_extra + native_insets.w)
	# Avoid pathological reported insets collapsing the entire workspace.
	var max_horizontal := maxi(0, int(viewport_size.x) - 260)
	var max_vertical := maxi(0, int(viewport_size.y) - 230)
	var h_total := left + right
	if h_total > max_horizontal and h_total > 0:
		left = int(float(left) * float(max_horizontal) / float(h_total))
		right = max_horizontal - left
	var v_total := top + bottom
	if v_total > max_vertical and v_total > 0:
		top = int(float(top) * float(max_vertical) / float(v_total))
		bottom = max_vertical - top
	for panel in [menu_safe, workspace_layer]:
		panel.add_theme_constant_override("margin_left", left)
		panel.add_theme_constant_override("margin_top", top)
		panel.add_theme_constant_override("margin_right", right)
		panel.add_theme_constant_override("margin_bottom", bottom)
	var available := viewport_size - Vector2(left + right, top + bottom)
	_resize_menu_content(available)
	_update_fit_label()

func _resize_menu_content(available: Vector2) -> void:
	if menu_box == null:
		return
	var short_side := minf(available.x, available.y)
	var logo_size := clampf(short_side * 0.23, 48.0, 150.0)
	if menu_logo != null:
		menu_logo.custom_minimum_size = Vector2(logo_size, logo_size)
	menu_heading.add_theme_font_size_override("font_size", clampi(int(available.x / 20.0), 18, 36))
	menu_start.add_theme_font_size_override("font_size", clampi(int(available.x / 28.0), 16, 24))
	menu_start.custom_minimum_size = Vector2(clampf(available.x * 0.65, 170.0, 320.0), clampf(available.y * 0.13, 44.0, 66.0))
	menu_box.add_theme_constant_override("separation", clampi(int(available.y * 0.025), 4, 16))

func _enter_workspace() -> void:
	if menu_video != null:
		menu_video.stop()
	menu_layer.visible = false
	workspace_layer.visible = true
