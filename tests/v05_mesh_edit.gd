extends SceneTree

const MeshEdit = preload("res://scripts/mesh_edit.gd")
const GlbIO = preload("res://scripts/glb_io.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var selected: MeshInstance3D = app.get("selected")
	if selected == null or selected.mesh == null:
		_fail("Missing initial editable cube")
		return
	var face_count: int = MeshEdit.triangle_count(selected.mesh, 0)
	if face_count < 2:
		_fail("Original cube has no triangle faces")
		return
	app.call("_set_mesh_mode", "Face")
	app.set("picked_surface", 0)
	app.set("picked_face", 0)
	app.call("_refresh_mesh_visual")
	app.call("_extrude_picked_face", 0.35)
	if MeshEdit.triangle_count(selected.mesh, 0) != face_count + 6:
		_fail("Extrude did not add six side triangles")
		return
	var cap: PackedVector3Array = MeshEdit.face_vertices(selected.mesh, 0, 0)
	if cap.size() != 3:
		_fail("Extruded face is no longer selectable")
		return
	app.call("_inset_picked_face")
	if MeshEdit.triangle_count(selected.mesh, 0) != face_count + 12:
		_fail("Inset did not create the face's rim")
		return
	app.call("_set_mesh_mode", "Vertex")
	app.set("picked_surface", 0)
	app.set("picked_face", 0)
	app.set("picked_vertex", cap[0].lerp((cap[0] + cap[1] + cap[2]) / 3.0, 0.2))
	app.set("has_picked_vertex", true)
	app.call("_refresh_mesh_visual")
	var before: Vector3 = app.get("picked_vertex")
	app.call("_nudge_picked_vertex", "Y", 1)
	var after: Vector3 = app.get("picked_vertex")
	if not is_equal_approx(after.y - before.y, 0.15):
		_fail("Vertex position was not edited")
		return
	var edited: Mesh = selected.mesh
	var has_vertex := false
	var face_data: PackedVector3Array = MeshEdit.face_vertices(edited, 0, 0)
	for point in face_data:
		if point.distance_to(after) < 0.001:
			has_vertex = true
	if not has_vertex:
		_fail("Vertex movement did not alter the actual mesh geometry")
		return
	app.call("_undo")
	if app.get("selected") == null:
		_fail("Undo did not restore selection")
		return
	app.call("_redo")
	selected = app.get("selected")
	if MeshEdit.triangle_count(selected.mesh, 0) != face_count + 12:
		_fail("Redo lost edited geometry")
		return
	var export_path := "user://dabsky-v05-model.glb"
	var result: Error = app.call("_export_glb_to_path", export_path)
	if result != OK:
		_fail("Edited mesh GLB export failed: " + error_string(result))
		return
	var bytes: PackedByteArray = GlbIO.read_bytes(export_path)
	if bytes.size() < 100:
		_fail("Edited GLB is missing")
		return
	var meshes: Array[MeshInstance3D] = GlbIO.decode_meshes(bytes)
	if meshes.size() != 1 or MeshEdit.triangle_count(meshes[0].mesh, 0) != face_count + 12:
		_fail("GLB round trip lost edited triangle geometry")
		return
	for mesh in meshes:
		mesh.free()
	app.call("_save_project")
	app.call("_new_project")
	app.call("_load_project")
	if app.get("objects").size() != 1 or MeshEdit.triangle_count(app.get("objects")[0].mesh, 0) != face_count + 12:
		_fail("Saving and reloading a project lost face edits")
		return
	print("DABSKY V0.5 FACE EXTRUDE / INSET / VERTEX / GLB ROUNDTRIP PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY V0.5 FAILED: " + message)
	quit(1)
