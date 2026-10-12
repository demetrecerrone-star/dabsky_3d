extends Control

var selected: MeshInstance3D
var viewport: SubViewport
var scene_root: Node3D
var command_input: LineEdit
var status: Label
var previous_transform: Transform3D
var preview_active := false
var undo_stack: Array[Transform3D] = []

func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	_add_button(toolbar, "Add Cube", _add_cube)
	_add_button(toolbar, "Undo", _undo)
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
	var camera := Camera3D.new()
	scene_root.add_child(camera)
	camera.position = Vector3(4, 3, 6)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	scene_root.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	var controls := HBoxContainer.new()
	layout.add_child(controls)
	command_input = LineEdit.new()
	command_input.placeholder_text = "move up 2 | rotate y 45 | scale 2 | height 1.5"
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(command_input)
	_add_button(controls, "Preview", _preview)
	_add_button(controls, "Apply", _apply)
	_add_button(controls, "Cancel", _cancel)
	status = Label.new()
	status.text = "Add a cube to begin."
	layout.add_child(status)

func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_cube() -> void:
	_cancel()
	selected = MeshInstance3D.new()
	selected.mesh = BoxMesh.new()
	scene_root.add_child(selected)
	undo_stack.clear()
	status.text = "Cube selected."

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
