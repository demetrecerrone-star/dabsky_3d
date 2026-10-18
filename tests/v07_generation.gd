extends SceneTree

const Generator = preload("res://scripts/dabsky_generator.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var recipe: Dictionary = Generator.generate("a stylized red sword")
	if not recipe.get("ok", false):
		_fail("Sword prompt was rejected")
		return
	var parts: Array = recipe.get("parts", [])
	if parts.size() < 4:
		_fail("Sword recipe needs multiple editable parts")
		return
	if recipe.get("kind") != "sword":
		_fail("Sword prompt classified incorrectly")
		return

	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	var before: int = editor.get("objects").size()
	var prompt: LineEdit = editor.get("ai_prompt")
	prompt.text = "a stylized red sword"
	editor.call("_generate_from_prompt")
	await process_frame
	var after: int = editor.get("objects").size()
	if after != before + parts.size():
		_fail("Generated parts were not added to the editable scene")
		return
	var selected: MeshInstance3D = editor.get("selected")
	if selected == null or selected.name != "Blade":
		_fail("Generation did not select the first generated part")
		return
	var material: StandardMaterial3D = selected.material_override
	if material == null or material.metallic < 0.7:
		_fail("Generated blade material settings were not preserved")
		return
	editor.call("_undo")
	await process_frame
	if editor.get("objects").size() != before:
		_fail("Generated asset is not undoable as one operation")
		return

	var tree_recipe: Dictionary = Generator.generate("low-poly green pine tree")
	if not tree_recipe.get("ok", false) or tree_recipe.get("kind") != "tree":
		_fail("Tree prompt classification failed")
		return
	if tree_recipe.get("style") != "low_poly":
		_fail("Low-poly style was not preserved")
		return
	print("DABSKY V0.7 PROMPT GENERATION / MULTI-PART EDITING / UNDO TEST PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY V0.7 GENERATION FAILED: " + message)
	quit(1)
