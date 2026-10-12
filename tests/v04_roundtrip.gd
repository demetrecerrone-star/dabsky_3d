extends SceneTree

const GlbIO = preload("res://scripts/glb_io.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if app.get("objects").size() != 1:
		_fail("Starter mesh missing")
		return
	app.call("_toggle_material_panel")
	app.call("_change_material_color", Color(0.27, 0.55, 0.87))
	app.call("_change_material_scalar", 0.67, "Metallic")
	app.call("_change_material_scalar", 0.21, "Roughness")
	app.call("_toggle_transform_panel")
	app.call("_change_transform_field", 3.25, "Position", "Y")
	app.call("_change_transform_field", 32.0, "Rotation", "Z")
	app.call("_change_transform_field", 1.75, "Scale", "X")
	var selected: MeshInstance3D = app.get("selected")
	if not is_equal_approx(selected.position.y, 3.25) or not is_equal_approx(selected.rotation_degrees.z, 32.0) or not is_equal_approx(selected.scale.x, 1.75):
		_fail("Precise X/Y/Z fields did not update scene")
		return
	var mat: StandardMaterial3D = selected.material_override
	if mat == null or not is_equal_approx(mat.metallic, 0.67) or not is_equal_approx(mat.roughness, 0.21):
		_fail("Material controls did not update the selected object")
		return
	var exported: Error = app.call("_export_glb_to_path", "user://dabsky-glb-roundtrip.glb")
	if exported != OK:
		_fail("GLB export failed: " + error_string(exported))
		return
	var bytes: PackedByteArray = GlbIO.read_bytes("user://dabsky-glb-roundtrip.glb")
	if bytes.size() < 500 or bytes.decode_u32(0) != 0x46546c67:
		_fail("Export not a valid nonempty GLB container")
		return
	app.call("_new_project")
	if app.get("objects").size() != 0:
		_fail("New project failed to clear objects")
		return
	var count: int = app.call("_import_glb_bytes", bytes)
	if count != 1 or app.get("objects").size() != 1:
		_fail("GLB import failed to recover mesh")
		return
	selected = app.get("selected")
	if selected == null or selected.mesh == null or not is_equal_approx(selected.position.y, 3.25):
		_fail("GLB import lost mesh or position")
		return
	var imported_mat: StandardMaterial3D = app.call("_get_selected_material")
	if imported_mat == null or absf(imported_mat.albedo_color.b - 0.87) > 0.1:
		_fail("GLB import lost material color")
		return
	app.call("_duplicate_selected")
	if app.get("objects").size() != 2:
		_fail("Imported mesh cannot be duplicated")
		return
	app.call("_undo")
	if app.get("objects").size() != 1 or app.get("selected").mesh == null:
		_fail("Undo lost imported mesh")
		return
	app.call("_redo")
	if app.get("objects").size() != 2:
		_fail("Redo lost imported mesh")
		return
	app.call("_save_project")
	if not FileAccess.file_exists("user://dabsky-project.glb") or not FileAccess.file_exists("user://dabsky-project.json"):
		_fail("Local project did not save GLB and metadata")
		return
	app.call("_new_project")
	app.call("_load_project")
	if app.get("objects").size() != 2 or app.get("objects")[0].mesh == null:
		_fail("Saved project did not reload imported GLB geometry")
		return
	print("DABSKY V0.4 MATERIAL / PRECISE / GLB ROUNDTRIP TEST PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY V0.4 FAILED: " + message)
	quit(1)
