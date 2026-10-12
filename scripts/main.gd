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
var workspace_layer: Control
var menu_video: VideoStreamPlayer
var dragging := false
var last_touch := Vector2.ZERO

func _ready() -> void:
	get_viewport().gui_embed_subwindows = true
	_build_menu()
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace_layer = layout
	add_child(layout)
	layout.visible = false
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	_add_button(toolbar, "Add Cube", _add_cube)
	_add_button(toolbar, "Undo", _undo)
	_add_button(toolbar, "Reset View", _reset_view)
	var container := SubViewportContainer.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	layout.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
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
	var controls := HBoxContainer.new()
	layout.add_child(controls)
	command_input = LineEdit.new()
	command_input.placeholder_text = "Example: move up 2" 
	command_input.custom_minimum_size.y = 54
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(command_input)
	_add_button(controls, "Preview", _preview)
	_add_button(controls, "Apply", _apply)
	_add_button(controls, "Cancel", _cancel)
	status = Label.new()
	status.text = "Drag to orbit the view. Try: move up 2, rotate y 45, scale 2."
	status.add_theme_font_size_override("font_size", 18)
	layout.add_child(status)
	_add_cube()

func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(115, 54)
	button.add_theme_font_size_override("font_size", 18)
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
	if event is InputEventScreenTouch:
		dragging = event.pressed
		last_touch = event.position
	elif event is InputEventScreenDrag and dragging:
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.008, -1.25, 1.25)
		_update_camera()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
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
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.custom_minimum_size = Vector2(380, 374)
	center.position = Vector2(-190, -187)
	center.add_theme_constant_override("separation", 22)
	menu_layer.add_child(center)
	if ResourceLoader.exists("res://assets/dabsky-icon.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/dabsky-icon.png")
		logo.custom_minimum_size = Vector2(154, 154)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(logo)
	var heading := Label.new()
	heading.text = "DABSKY 3D STUDIO"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 38)
	center.add_child(heading)
	var start := Button.new()
	start.text = "START MODELING"
	start.custom_minimum_size.y = 76
	start.add_theme_font_size_override("font_size", 26)
	start.pressed.connect(_enter_workspace)
	center.add_child(start)

func _enter_workspace() -> void:
	if menu_video != null:
		menu_video.stop()
	menu_layer.visible = false
	workspace_layer.visible = true
