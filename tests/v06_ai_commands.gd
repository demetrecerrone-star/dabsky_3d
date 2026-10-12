extends SceneTree

const DabskyAI = preload("res://scripts/dabsky_ai.gd")
const GlbIO = preload("res://scripts/glb_io.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	var ai_panel: VBoxContainer = editor.get("ai_panel")
	if ai_panel == null or ai_panel.visible:
		_fail("AI panel must start hidden")
		return
	editor.call("_toggle_ai_panel")
	if not ai_panel.visible:
		_fail("AI panel cannot be opened")
		return
	var start_count: int = editor.get("objects").size()
	var result: Dictionary = editor.call("_run_ai_prompt", "create a cube and make it red and move it up 2")
	if not result.get("ok", false):
		_fail("Compound instruction was rejected: " + str(result.get("message", "")))
		return
	if editor.get("objects").size() != start_count + 1:
		_fail("Object not created")
		return
	var obj: MeshInstance3D = editor.get("selected")
	if absf(obj.position.y - 2.0) > 0.001:
		_fail("Movement failed")
		return
	var mat: StandardMaterial3D = obj.material_override
	if mat == null or mat.albedo_color.r < 0.75 or mat.albedo_color.g > 0.55:
		_fail("Color editing failed")
		return
	result = editor.call("_run_ai_prompt", "rotate y 45 and scale it by 1.5 and set position x to 3.25")
	obj = editor.get("selected")
	if not result.get("ok", false) or absf(obj.position.x - 3.25) > 0.001 or absf(obj.scale.x - 1.5) > 0.001:
		_fail("Transform commands failed")
		return
	var position_before := obj.position
	result = editor.call("_run_ai_prompt", "make it blue and teleport it to mars")
	obj = editor.get("selected")
	mat = obj.material_override
	if result.get("ok", true) or obj.position != position_before or mat.albedo_color.b > 0.6:
		_fail("Unsupported compound command mutated the scene")
		return
	result = editor.call("_run_ai_prompt", "move it right 999999")
	if result.get("ok", true):
		_fail("Unbounded commands must be rejected")
		return
	var parsed: Dictionary = DabskyAI.interpret("create 3 spheres")
	if not parsed.get("ok", false) or parsed["actions"][0].get("count") != 3:
		_fail("Quantity parser failed")
		return
	result = editor.call("_run_ai_prompt", "set metallic to 0.7 and set roughness to 0.4")
	obj = editor.get("selected")
	mat = obj.material_override
	if not result.get("ok", false) or absf(mat.metallic - 0.7) > 0.01 or absf(mat.roughness - 0.4) > 0.01:
		_fail("Material editing failed")
		return
	result = editor.call("_run_ai_prompt", "duplicate")
	if not result.get("ok", false) or editor.get("objects").size() != start_count + 2:
		_fail("Duplicate failed")
		return
	result = editor.call("_run_ai_prompt", "undo")
	if not result.get("ok", false) or editor.get("objects").size() != start_count + 1:
		_fail("Undo failed")
		return
	result = editor.call("_run_ai_prompt", "redo")
	if not result.get("ok", false) or editor.get("objects").size() != start_count + 2:
		_fail("Redo failed")
		return
	result = editor.call("_run_ai_prompt", "save project")
	if not result.get("ok", false) or not FileAccess.file_exists("user://dabsky-project.glb"):
		_fail("Project save failed")
		return
	var bytes: PackedByteArray = GlbIO.read_bytes("user://dabsky-project.glb")
	if bytes.size() < 200 or bytes.decode_u32(0) != 0x46546c67:
		_fail("Project was not saved as a valid GLB")
		return
	if DabskyAI.interpret("build an entire medieval city with AI").get("ok", true):
		_fail("Must not claim unsupported generation capabilities")
		return
	print("DABSKY V0.6 AI OFFLINE COMMANDS / UNDO / GLB SMOKE TEST PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY V0.6 FAILED: " + message)
	quit(1)
