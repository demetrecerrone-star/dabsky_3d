extends SceneTree

const Remote = preload("res://scripts/dabsky_remote.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	if Remote.join_url("https://example.test/api/", "/v1/jobs") != "https://example.test/api/v1/jobs":
		_fail("URL joining duplicated or dropped a slash")
		return
	var empty_prompt: Dictionary = Remote.build_payload("")
	if empty_prompt.get("ok", true):
		_fail("Empty prompt was accepted")
		return
	var too_long: Dictionary = Remote.build_payload("x".repeat(Remote.MAX_PROMPT_CHARS + 1))
	if too_long.get("ok", true):
		_fail("Oversized prompt was accepted")
		return

	var prompt_only: Dictionary = Remote.build_payload("a red low-poly chest")
	if not prompt_only.get("ok", false):
		_fail("Prompt-only request was rejected")
		return
	var prompt_payload: Dictionary = prompt_only.get("payload", {})
	if prompt_payload.get("output_format") != "glb" or prompt_payload.get("client_version") != "0.8.0":
		_fail("Remote request metadata is incomplete")
		return

	var reference_path := "user://dabsky-v08-reference.png"
	var image_file := FileAccess.open(reference_path, FileAccess.WRITE)
	if image_file == null:
		_fail("Could not create reference fixture")
		return
	image_file.store_buffer(PackedByteArray([137, 80, 78, 71, 0, 1, 2, 3]))
	image_file.close()
	var with_reference: Dictionary = Remote.build_payload("a red low-poly chest", reference_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reference_path))
	if not with_reference.get("ok", false):
		_fail("Reference-image request was rejected")
		return
	var reference: Dictionary = with_reference.get("payload", {}).get("reference_image", {})
	if reference.get("mime_type") != "image/png" or str(reference.get("data_base64", "")).is_empty():
		_fail("Reference image was not encoded safely")
		return

	var accepted := PackedByteArray(JSON.stringify({
		"id": "job-123",
		"status": "queued",
		"model_path": "/v1/jobs/job-123/model",
		"retry_after_seconds": 2
	}).to_utf8_buffer())
	var parsed: Dictionary = Remote.parse_job_response(accepted)
	if not parsed.get("ok", false) or parsed.get("job_id") != "job-123" or parsed.get("retry_after") != 2.0:
		_fail("Queued job response was not parsed")
		return

	var editor: Control = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	if editor.get("remote_generate_button") == null or editor.get("remote_reference_dialog") == null:
		_fail("Remote generation controls were not created")
		return
	print("DABSKY V0.8 REMOTE CONTRACT / REFERENCE IMAGE / PROGRESS UI TEST PASSED")
	quit(0)

func _fail(message: String) -> void:
	push_error("DABSKY V0.8 REMOTE GENERATION FAILED: " + message)
	quit(1)
