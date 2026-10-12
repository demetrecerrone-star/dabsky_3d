extends RefCounted

# Dabsky AI Core v0.6: fully offline, deterministic natural-language command
# interpreter. No server calls, no downloaded models, and no code execution.
# Other providers can later produce this same whitelisted action schema.
const MAX_ACTIONS := 8
const MAX_ABS_NUMBER := 1000.0
const HELP := "Try: create a cube and make it red; move it up 2; rotate y 45; set position x to 3; scale it by 1.5; set metallic to 0.8; duplicate; save project."

static func interpret(prompt: String) -> Dictionary:
	var cleaned := prompt.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned.length() > 500:
		return _fail("Enter a request of up to 500 characters.")
	if cleaned in ["help", "examples", "what can you do", "what can you do?"]:
		return {"ok": true, "actions": [], "message": HELP}
	cleaned = cleaned.replace(" then ", " and ").replace("; ", " and ").replace(";", " and ")
	cleaned = cleaned.replace(", then ", " and ")
	var clauses := cleaned.split(" and ", false)
	if clauses.size() > MAX_ACTIONS:
		return _fail("Use eight or fewer actions per request.")
	var actions: Array[Dictionary] = []
	for clause in clauses:
		var parsed: Dictionary = _parse_one(clause.strip_edges().trim_suffix(".").trim_suffix("!"))
		if not bool(parsed.get("ok", false)):
			return parsed
		var action: Dictionary = parsed.get("action", {})
		actions.append(action)
	return {"ok": true, "actions": actions, "message": "Understood."}

static func _parse_one(words: String) -> Dictionary:
	if words in ["undo", "undo that", "undo last change"]:
		return _ok({"op": "undo"})
	if words in ["redo", "redo that"]:
		return _ok({"op": "redo"})
	if words in ["save", "save project", "save the project", "save my project"]:
		return _ok({"op": "save"})
	if words in ["duplicate", "duplicate it", "duplicate the selected object", "copy it", "copy object"]:
		return _ok({"op": "duplicate"})
	if words in ["delete", "delete it", "delete selected", "delete the selected object", "remove it"]:
		return _ok({"op": "delete"})
	if words in ["reset camera", "reset view", "center camera"]:
		return _ok({"op": "reset_view"})
	var m: Array = _capture(words, r"^(?:please )?(?:create|add|make|spawn) (?:(\d+) )?(?:a |an )?(cube|box|sphere|ball|cylinder|plane|cone)s?$")
	if not m.is_empty():
		var amount: int = int(m[1]) if not str(m[1]).is_empty() else 1
		if amount < 1 or amount > 5:
			return _fail("Create between one and five shapes at a time.")
		var kind: String = str(m[2])
		if kind == "box": kind = "cube"
		if kind == "ball": kind = "sphere"
		return _ok({"op": "create", "kind": kind.capitalize(), "count": amount})
	m = _capture(words, r"^(?:please )?(?:select|choose) (?:the )?(?:object )?(.+)$")
	if not m.is_empty():
		return _ok({"op": "select", "name": str(m[1]).strip_edges()})
	m = _capture(words, r"^(?:please )?(?:move|shift|translate) (?:(?:it|the object|the selected object) )?(up|down|left|right|forward|back|backward|x|y|z) (?:by )?(-?\d+(?:\.\d+)?)$")
	if not m.is_empty():
		var amount: float = float(m[2])
		if not _valid_number(amount):
			return _fail("Movement must be within ±1,000 units.")
		var direction: String = str(m[1])
		var vector := Vector3.ZERO
		match direction:
			"up", "y": vector = Vector3.UP
			"down": vector = Vector3.DOWN
			"left": vector = Vector3.LEFT
			"right", "x": vector = Vector3.RIGHT
			"forward": vector = Vector3.FORWARD
			"back", "backward", "z": vector = Vector3.BACK
		return _ok({"op": "move", "delta": vector * amount})
	m = _capture(words, r"^(?:please )?rotate (?:(?:it|the object) )?(?:around )?(x|y|z) (?:by )?(-?\d+(?:\.\d+)?)(?: degrees?)?$")
	if not m.is_empty():
		var degrees: float = float(m[2])
		if not _valid_number(degrees):
			return _fail("Rotation must be within ±1,000 degrees.")
		return _ok({"op": "rotate", "axis": str(m[1]), "degrees": degrees})
	m = _capture(words, r"^(?:please )?(?:scale|resize) (?:(?:it|the object) )?(?:by |to )?(\d+(?:\.\d+)?)$")
	if not m.is_empty():
		var factor: float = float(m[1])
		if factor < 0.01 or factor > 100.0:
			return _fail("Scale factor must be between 0.01 and 100.")
		return _ok({"op": "scale", "factor": factor})
	m = _capture(words, r"^(?:please )?set (position|rotation|scale) (x|y|z) to (-?\d+(?:\.\d+)?)$")
	if not m.is_empty():
		var n: float = float(m[3])
		if not _valid_number(n) or (str(m[1]) == "scale" and n < 0.01):
			return _fail("Choose a finite value within ±1,000; scale must stay positive.")
		return _ok({"op": "set_transform", "property": str(m[1]).capitalize(), "axis": str(m[2]).to_upper(), "value": n})
	m = _capture(words, r"^(?:please )?(?:set )?(?:the )?(?:object )?(?:color|colour) (?:(?:it |to )?)([a-z]+|#[0-9a-f]{6})$")
	if m.is_empty():
		m = _capture(words, r"^(?:please )?(?:make|paint) (?:(?:it|the object) )?(red|blue|green|purple|white|black|yellow|orange|pink|gray|grey|brown|cyan|gold|silver)$")
	if not m.is_empty():
		var color_name: String = str(m[1])
		var colors := {
			"red": "#e74c58", "blue": "#498ee7", "green": "#43be85",
			"purple": "#a065ed", "white": "#ffffff", "black": "#22202b",
			"yellow": "#f5d656", "orange": "#f2a14d", "pink": "#f38ccc",
			"gray": "#858d9d", "grey": "#858d9d", "brown": "#986945",
			"cyan": "#55d5e7", "gold": "#f4c75b", "silver": "#bac6d8"
		}
		if not color_name.begins_with("#") and not colors.has(color_name):
			return _fail("Try a basic color (red, blue, purple, gold) or a #RRGGBB hex color.")
		return _ok({"op": "color", "color": Color.html(str(colors.get(color_name, color_name)))})
	m = _capture(words, r"^(?:please )?set (metallic|roughness) to (0(?:\.\d+)?|1(?:\.0+)?)$")
	if not m.is_empty():
		return _ok({"op": "material", "property": str(m[1]), "value": float(m[2])})
	m = _capture(words, r"^(?:please )?rename (?:(?:it|the selected object) )?to (.{1,48})$")
	if not m.is_empty():
		return _ok({"op": "rename", "name": str(m[1]).strip_edges()})
	return _fail("I don't know how to do: \"" + words.substr(0, 90) + "\". " + HELP)

static func _capture(input: String, pattern: String) -> Array:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return []
	var found := regex.search(input)
	if found == null:
		return []
	var groups: Array = []
	for group in range(found.get_group_count() + 1):
		groups.append(found.get_string(group))
	return groups

static func _ok(action: Dictionary) -> Dictionary:
	return {"ok": true, "action": action}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "actions": [], "message": message}

static func _valid_number(value: float) -> bool:
	return is_finite(value) and absf(value) <= MAX_ABS_NUMBER
