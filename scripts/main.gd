extends Control

var selected: MeshInstance3D
var viewport: SubViewport
var scene_root: Node3D
var command_input: LineEdit
var status: Label
var previous_transform: Transform3D
var preview_active := false
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var objects: Array[MeshInstance3D] = []
var object_list: ItemList
var object_panel: VBoxContainer
var object_name_input: LineEdit
var selected_label: Label
var transform_mode := "Move"
var preview_snapshot: Dictionary = {}
var editing_tap := Vector2.ZERO
var pointer_moved := false
var highlight_material: StandardMaterial3D
const PROJECT_FILE := "user://dabsky-project.json"
const OBJECT_LIMIT := 100
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
	var titlebar := HBoxContainer.new()
	layout.add_child(titlebar)
	selected_label = Label.new()
	selected_label.text = "Dabsky 3D • No object"
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.add_theme_font_size_override("font_size", 17)
	titlebar.add_child(selected_label)
	_add_button(titlebar, "Menu", _leave_workspace)
	var shapes := HBoxContainer.new()
	_add_scrolling_toolbar(layout, shapes)
	for kind in ["Cube", "Sphere", "Cylinder", "Plane", "Cone"]:
		_add_button(shapes, "+ " + kind, _add_primitive.bind(kind))
	_add_button(shapes, "Objects", _toggle_object_panel)
	_add_button(shapes, "New", _new_project)
	_add_button(shapes, "Save", _save_project)
	_add_button(shapes, "Load", _load_project)
	object_panel = VBoxContainer.new()
	object_panel.visible = false
	layout.add_child(object_panel)
	var object_row := HBoxContainer.new()
	object_panel.add_child(object_row)
	object_list = ItemList.new()
	object_list.custom_minimum_size = Vector2(240, 100)
	object_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_list.select_mode = ItemList.SELECT_SINGLE
	object_list.item_selected.connect(_select_list_item)
	object_row.add_child(object_list)
	var actions := VBoxContainer.new()
	object_row.add_child(actions)
	_add_button(actions, "Duplicate", _duplicate_selected)
	_add_button(actions, "Delete", _delete_selected)
	var rename_row := HBoxContainer.new()
	object_panel.add_child(rename_row)
	object_name_input = LineEdit.new()
	object_name_input.placeholder_text = "Object name"
	object_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_row.add_child(object_name_input)
	_add_button(rename_row, "Rename", _rename_selected)
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
	var editbar := HBoxContainer.new()
	_add_scrolling_toolbar(layout, editbar)
	for mode in ["Move", "Rotate", "Scale"]:
		_add_button(editbar, mode, _set_transform_mode.bind(mode))
	for axis in ["X", "Y", "Z"]:
		_add_button(editbar, axis + "-", _nudge.bind(axis, -1))
		_add_button(editbar, axis + "+", _nudge.bind(axis, 1))
	_add_button(editbar, "Undo", _undo)
	_add_button(editbar, "Redo", _redo)
	_add_button(editbar, "Reset View", _reset_view)
	_add_button(editbar, "Fit -", func(): _adjust_screen_fit(-SCREEN_FIT_STEP))
	_add_button(editbar, "Fit +", func(): _adjust_screen_fit(SCREEN_FIT_STEP))
	var command_row := HBoxContainer.new()
	layout.add_child(command_row)
	command_input = LineEdit.new()
	command_input.placeholder_text = "move up 2 • rotate y 45 • scale 2"
	command_input.custom_minimum_size.y = 45
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_row.add_child(command_input)
	_add_button(command_row, "Preview", _preview)
	_add_button(command_row, "Apply", _apply)
	_add_button(command_row, "Cancel", _cancel)
	status = Label.new()
	status.text = "Tap an object to select. Drag to orbit. Choose Move / Rotate / Scale and tap an axis."
	status.add_theme_font_size_override("font_size", 16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	layout.add_child(status)
	highlight_material = StandardMaterial3D.new()
	highlight_material.albedo_color = Color(0.64, 0.3, 1.0, 0.20)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_primitive("Cube", false)
	get_viewport().size_changed.connect(_refresh_screen_fit)
	call_deferred("_refresh_screen_fit")

func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(90, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_scrolling_toolbar(parent: VBoxContainer, contents: HBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 53
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	contents.add_theme_constant_override("separation", 7)
	scroll.add_child(contents)

func _make_mesh(kind: String) -> Mesh:
	match kind:
		"Sphere": return SphereMesh.new()
		"Cylinder": return CylinderMesh.new()
		"Plane":
			var plane := PlaneMesh.new()
			plane.size = Vector2(2, 2)
			return plane
		"Cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			return cone
		_: return BoxMesh.new()

func _add_primitive(kind: String, track_undo: bool = true) -> void:
	if objects.size() >= OBJECT_LIMIT:
		status.text = "Scene limit: 100 objects."
		return
	_cancel()
	if track_undo:
		_record_change()
	var obj := MeshInstance3D.new()
	obj.mesh = _make_mesh(kind)
	obj.name = "%s_%d" % [kind, objects.size() + 1]
	obj.set_meta("kind", kind)
	var material := StandardMaterial3D.new()
	var palette := {
		"Cube": Color(0.55, 0.69, 0.86),
		"Sphere": Color(0.72, 0.52, 0.95),
		"Cylinder": Color(0.49, 0.8, 0.78),
		"Plane": Color(0.76, 0.71, 0.58),
		"Cone": Color(0.94, 0.67, 0.47)
	}
	material.albedo_color = palette.get(kind, Color.WHITE)
	obj.material_override = material
	scene_root.add_child(obj)
	obj.position.x = float(objects.size() % 5) * 1.6 - 1.6 if track_undo else 0.0
	objects.append(obj)
	_select_object(obj)
	status.text = "%s created. Tap an axis or drag to orbit." % kind

func _select_object(obj: MeshInstance3D) -> void:
	if selected != null and is_instance_valid(selected):
		selected.material_overlay = null
	selected = obj
	if selected != null:
		selected.material_overlay = highlight_material
	_refresh_object_list()
	if object_name_input != null:
		object_name_input.text = selected.name if selected != null else ""
	if selected_label != null:
		selected_label.text = ("Selected: " + selected.name + " • " + transform_mode) if selected != null else "Dabsky 3D • No object"

func _refresh_object_list() -> void:
	if object_list == null:
		return
	object_list.clear()
	for obj in objects:
		object_list.add_item("%s  ·  %s" % [obj.name, obj.get_meta("kind", "Cube")])
		if obj == selected:
			object_list.select(object_list.item_count - 1)

func _select_list_item(index: int) -> void:
	if index >= 0 and index < objects.size():
		_cancel()
		_select_object(objects[index])

func _toggle_object_panel() -> void:
	object_panel.visible = not object_panel.visible
	status.text = "Object list opened." if object_panel.visible else "Object list hidden."

func _rename_selected() -> void:
	if selected == null:
		status.text = "Select an object first."
		return
	var requested := object_name_input.text.strip_edges()
	if requested.is_empty():
		status.text = "Enter an object name first."
		return
	_cancel()
	_record_change()
	selected.name = requested.substr(0, 48)
	_select_object(selected)
	status.text = "Object renamed."

func _duplicate_selected() -> void:
	if selected == null or objects.size() >= OBJECT_LIMIT:
		status.text = "Select an object (maximum 100)."
		return
	_cancel()
	_record_change()
	var source := selected
	var kind: String = str(source.get_meta("kind", "Cube"))
	var duplicate := MeshInstance3D.new()
	duplicate.mesh = _make_mesh(kind)
	duplicate.material_override = source.material_override
	duplicate.name = source.name + "_copy"
	duplicate.set_meta("kind", kind)
	scene_root.add_child(duplicate)
	duplicate.transform = source.transform
	duplicate.position.x += 0.8
	objects.append(duplicate)
	_select_object(duplicate)
	status.text = "Object duplicated."

func _delete_selected() -> void:
	if selected == null:
		status.text = "Select an object first."
		return
	_cancel()
	_record_change()
	var removed := selected
	objects.erase(removed)
	removed.queue_free()
	selected = null
	_select_object(objects.back() if not objects.is_empty() else null)
	status.text = "Object deleted. Undo can restore it."

func _set_transform_mode(mode: String) -> void:
	transform_mode = mode
	_select_object(selected)
	status.text = "%s: axis buttons adjust X, Y, or Z." % mode

func _nudge(axis: String, direction: int) -> void:
	if selected == null:
		status.text = "Select an object first."
		return
	_cancel()
	var vec := Vector3.ZERO
	match axis:
		"X": vec = Vector3.RIGHT
		"Y": vec = Vector3.UP
		"Z": vec = Vector3.BACK
	_record_change()
	match transform_mode:
		"Rotate":
			selected.rotate_object_local(vec, deg_to_rad(15.0 * direction))
		"Scale":
			var delta := vec * (0.1 * direction)
			selected.scale = Vector3(
				maxf(0.1, selected.scale.x + delta.x),
				maxf(0.1, selected.scale.y + delta.y),
				maxf(0.1, selected.scale.z + delta.z)
			)
		_:
			selected.position += vec * (0.25 * direction)
	status.text = "%s %s %s" % [transform_mode, axis, "+" if direction > 0 else "-"]

func _vec_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _read_vec(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return fallback
	for number in value:
		if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT:
			return fallback
		if not is_finite(float(number)) or absf(float(number)) > 10000.0:
			return fallback
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _snapshot() -> Dictionary:
	var entries := []
	for obj in objects:
		entries.append({
			"kind": obj.get_meta("kind", "Cube"),
			"name": obj.name,
			"position": _vec_array(obj.position),
			"rotation": _vec_array(obj.rotation),
			"scale": _vec_array(obj.scale)
		})
	return {"objects": entries, "selected_index": objects.find(selected)}

func _restore(snapshot: Dictionary) -> void:
	if selected != null and is_instance_valid(selected):
		selected.material_overlay = null
	selected = null
	for obj in objects:
		obj.queue_free()
	objects.clear()
	var entries: Array = snapshot.get("objects", [])
	for entry in entries:
		if not entry is Dictionary or objects.size() >= OBJECT_LIMIT:
			continue
		var kind: String = str(entry.get("kind", "Cube"))
		if kind not in ["Cube", "Sphere", "Cylinder", "Plane", "Cone"]:
			continue
		_add_primitive(kind, false)
		var obj: MeshInstance3D = objects.back()
		obj.name = str(entry.get("name", kind)).substr(0, 48)
		obj.position = _read_vec(entry.get("position"), Vector3.ZERO)
		obj.rotation = _read_vec(entry.get("rotation"), Vector3.ZERO)
		obj.scale = _read_vec(entry.get("scale"), Vector3.ONE)
		obj.scale = Vector3(maxf(0.1, obj.scale.x), maxf(0.1, obj.scale.y), maxf(0.1, obj.scale.z))
	var selected_index: int = int(snapshot.get("selected_index", -1))
	_select_object(objects[selected_index] if selected_index >= 0 and selected_index < objects.size() else null)

func _record_change() -> void:
	undo_stack.append(_snapshot())
	if undo_stack.size() > 50:
		undo_stack.pop_front()
	redo_stack.clear()

func _redo() -> void:
	_cancel()
	if redo_stack.is_empty():
		status.text = "Nothing to redo."
		return
	undo_stack.append(_snapshot())
	_restore(redo_stack.pop_back())
	status.text = "Redone."

func _save_project() -> void:
	_cancel()
	var file := FileAccess.open(PROJECT_FILE, FileAccess.WRITE)
	if file == null:
		status.text = "Cannot save project: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"format": 1, "scene": _snapshot()}))
	file.close()
	status.text = "Project saved on this device."

func _load_project() -> void:
	_cancel()
	if not FileAccess.file_exists(PROJECT_FILE):
		status.text = "No saved project yet. Tap Save first."
		return
	var file := FileAccess.open(PROJECT_FILE, FileAccess.READ)
	if file == null:
		status.text = "Could not read saved project."
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("scene") is Dictionary:
		status.text = "Project data is invalid."
		return
	_record_change()
	_restore(data["scene"])
	status.text = "Project loaded."

func _preview() -> void:
	if selected == null:
		status.text = "Select or add an object first."
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
	preview_snapshot = _snapshot()
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
		undo_stack.append(preview_snapshot)
		redo_stack.clear()
		preview_active = false
		status.text = "Change applied."

func _cancel() -> void:
	if preview_active and selected != null and is_instance_valid(selected):
		selected.transform = previous_transform
	preview_active = false

func _undo() -> void:
	if preview_active:
		_cancel()
		status.text = "Preview canceled."
	elif not undo_stack.is_empty():
		redo_stack.append(_snapshot())
		_restore(undo_stack.pop_back())
		status.text = "Undone."
	else:
		status.text = "Nothing to undo."

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
		if event.pressed:
			dragging = viewport_container.get_global_rect().has_point(event.position)
			editing_tap = event.position
			pointer_moved = false
		else:
			if dragging and not pointer_moved:
				_pick_object(event.position)
			dragging = false
		last_touch = event.position
	elif event is InputEventScreenDrag and dragging:
		if event.position.distance_to(editing_tap) > 12.0:
			pointer_moved = true
		if pointer_moved:
			orbit_yaw -= event.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.008, -1.25, 1.25)
			_update_camera()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = viewport_container.get_global_rect().has_point(event.position)
				editing_tap = event.position
				pointer_moved = false
			else:
				if dragging and not pointer_moved:
					_pick_object(event.position)
				dragging = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(2.0, orbit_distance - 0.7)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(25.0, orbit_distance + 0.7)
			_update_camera()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(editing_tap) > 12.0:
			pointer_moved = true
		if pointer_moved:
			orbit_yaw -= event.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.008, -1.25, 1.25)
			_update_camera()

func _pick_object(screen_position: Vector2) -> void:
	var rect := viewport_container.get_global_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0 or not rect.has_point(screen_position):
		return
	var viewport_position := (screen_position - rect.position) * Vector2(viewport.size) / rect.size
	var ray_origin := camera.project_ray_origin(viewport_position)
	var ray_direction := camera.project_ray_normal(viewport_position)
	var nearest := INF
	var target: MeshInstance3D = null
	for obj in objects:
		var inverse := obj.global_transform.affine_inverse()
		var local_from := inverse * ray_origin
		var local_dir := (inverse.basis * ray_direction).normalized()
		var hit: Variant = obj.get_aabb().grow(0.10).intersects_ray(local_from, local_dir)
		if hit is Vector3:
			var distance := ray_origin.distance_to(obj.global_transform * hit)
			if distance < nearest:
				nearest = distance
				target = obj
	if target != null:
		_cancel()
		_select_object(target)
		status.text = "Selected %s." % target.name

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

func _leave_workspace() -> void:
	_cancel()
	workspace_layer.visible = false
	menu_layer.visible = true
	if menu_video != null:
		menu_video.play()

func _new_project() -> void:
	_cancel()
	_record_change()
	_restore({"objects": [], "selected_index": -1})
	status.text = "New empty project. Tap + Cube, + Sphere, or another shape."

func _enter_workspace() -> void:
	if menu_video != null:
		menu_video.stop()
	menu_layer.visible = false
	workspace_layer.visible = true
