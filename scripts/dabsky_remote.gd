extends RefCounted
## Safe, provider-neutral contract for remote Dabsky generation.
## This helper never stores credentials and caps reference uploads before encoding.

const MAX_PROMPT_CHARS := 500
const MAX_REFERENCE_BYTES := 6 * 1024 * 1024
const SUPPORTED_MIME := ["image/png", "image/jpeg", "image/webp"]

static func join_url(endpoint: String, path: String) -> String:
	var base := endpoint.strip_edges().trim_suffix("/")
	var suffix := path.strip_edges()
	if suffix.is_empty():
		return base
	if suffix.begins_with("http://") or suffix.begins_with("https://"):
		return suffix
	if not suffix.begins_with("/"):
		suffix = "/" + suffix
	return base + suffix

static func build_payload(prompt: String, reference_path: String = "") -> Dictionary:
	var clean_prompt := prompt.strip_edges()
	if clean_prompt.is_empty():
		return {"ok": false, "message": "Describe the model you want first."}
	if clean_prompt.length() > MAX_PROMPT_CHARS:
		return {"ok": false, "message": "Keep the prompt under %d characters." % MAX_PROMPT_CHARS}
	var payload := {
		"prompt": clean_prompt,
		"output_format": "glb",
		"client": "dabsky-3d-studio",
		"client_version": "0.8.0"
	}
	if not reference_path.strip_edges().is_empty():
		var reference := _encode_reference(reference_path)
		if not bool(reference.get("ok", false)):
			return reference
		payload["reference_image"] = reference.get("image")
	return {"ok": true, "payload": payload}

static func parse_job_response(body: PackedByteArray) -> Dictionary:
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "message": "The generation service returned invalid JSON."}
	var data: Dictionary = parsed
	var job_id := str(data.get("id", data.get("job_id", ""))).strip_edges()
	var status := str(data.get("status", "queued")).to_lower()
	var model_path := str(data.get("model_path", data.get("model_url", ""))).strip_edges()
	var retry_after := maxf(0.5, float(data.get("retry_after_seconds", 1.0)))
	if not job_id.is_empty() or not model_path.is_empty():
		return {
			"ok": true,
			"job_id": job_id,
			"status": status,
			"model_path": model_path,
			"progress": clampf(float(data.get("progress", 0.0)), 0.0, 100.0),
			"retry_after": retry_after,
			"message": str(data.get("message", "Generation request accepted."))
		}
	return {"ok": false, "message": str(data.get("message", "The generation service returned no job id."))}

static func parse_error(body: PackedByteArray, fallback: String) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		var message := str(parsed.get("message", parsed.get("error", ""))).strip_edges()
		if not message.is_empty():
			return message
	var raw := body.get_string_from_utf8().strip_edges()
	return raw.substr(0, 180) if not raw.is_empty() else fallback

static func _encode_reference(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "Reference image could not be opened."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Reference image could not be opened."}
	var length := file.get_length()
	if length <= 0 or length > MAX_REFERENCE_BYTES:
		file.close()
		return {"ok": false, "message": "Reference images must be between 1 byte and 6 MB."}
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "message": "Reference image read was incomplete."}
	var mime := _mime_for_path(path)
	if mime.is_empty():
		return {"ok": false, "message": "Use a PNG, JPG, JPEG, or WebP reference image."}
	return {
		"ok": true,
		"image": {
			"filename": path.get_file().substr(0, 96),
			"mime_type": mime,
			"data_base64": Marshalls.raw_to_base64(bytes)
		}
	}

static func _mime_for_path(path: String) -> String:
	var extension := path.get_extension().to_lower()
	match extension:
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"webp":
			return "image/webp"
		_:
			return ""
