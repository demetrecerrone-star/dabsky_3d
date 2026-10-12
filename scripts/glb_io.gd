extends RefCounted

# GLB-only interchange. Android's native document picker returns content:// URIs,
# which FileAccess supports; do not pass those URIs to GLTFDocument directly.
const MAX_IMPORT_BYTES := 80 * 1024 * 1024
const MAX_IMPORT_MESHES := 100

static func encode_meshes(meshes: Array[MeshInstance3D]) -> PackedByteArray:
	if meshes.is_empty():
		return PackedByteArray()
	var root := Node3D.new()
	root.name = "DabskyModel"
	for source in meshes:
		if source == null or not is_instance_valid(source) or source.mesh == null:
			continue
		var output := MeshInstance3D.new()
		output.name = source.name
		output.mesh = source.mesh
		output.transform = source.transform
		output.material_override = source.material_override
		root.add_child(output)
		output.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	var bytes := PackedByteArray()
	if err == OK:
		bytes = doc.generate_buffer(state)
	else:
		push_error("GLB export scene conversion: " + error_string(err))
	root.free()
	return bytes

static func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	if bytes.size() < 20:
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var err := file.get_error()
	file.close()
	return err

static func read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	if file.get_length() < 20 or file.get_length() > MAX_IMPORT_BYTES:
		file.close()
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

static func decode_meshes(bytes: PackedByteArray) -> Array[MeshInstance3D]:
	var output: Array[MeshInstance3D] = []
	if bytes.size() < 20 or bytes.size() > MAX_IMPORT_BYTES:
		return output
	# GLB header: magic "glTF" (0x46546c67).
	if bytes.decode_u32(0) != 0x46546c67:
		return output
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		push_error("GLB input could not be parsed: " + error_string(err))
		return output
	var imported := doc.generate_scene(state)
	if imported == null:
		return output
	_collect_meshes(imported, output)
	imported.free()
	return output

static func _collect_meshes(root: Node, output: Array[MeshInstance3D]) -> void:
	if output.size() >= MAX_IMPORT_MESHES:
		return
	if root is MeshInstance3D:
		var source: MeshInstance3D = root
		if source.mesh != null:
			var copy := MeshInstance3D.new()
			copy.name = source.name
			copy.mesh = source.mesh
			copy.transform = source.global_transform
			copy.material_override = source.material_override
			copy.set_meta("kind", "Imported")
			output.append(copy)
	for child in root.get_children():
		if output.size() >= MAX_IMPORT_MESHES:
			return
		_collect_meshes(child, output)
