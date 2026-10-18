extends RefCounted

# Dabsky Generation Core v0.7
# Local-first, deterministic prompt-to-asset recipes. Each recipe produces
# ordinary editable MeshInstance3D parts, so every result remains transparent,
# undoable, and exportable as GLB. A future hosted model can return this same
# recipe schema without changing the editor.

const MAX_PROMPT_LENGTH := 240
const MAX_PARTS := 24

static func generate(prompt: String) -> Dictionary:
	var cleaned := prompt.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned.length() > MAX_PROMPT_LENGTH:
		return _fail("Describe an asset in 240 characters or fewer.")
	var accent := _color_for(cleaned)
	var style := "stylized"
	if cleaned.contains("realistic") or cleaned.contains("detailed"):
		style = "detailed"
	elif cleaned.contains("low poly") or cleaned.contains("low-poly"):
		style = "low_poly"
	var parts: Array = []
	var title := "Generated Prop"
	var kind := "prop"
	if _has_any(cleaned, ["sword", "blade", "katana", "greatsword"]):
		title = "Generated Sword"
		kind = "sword"
		parts = _sword_recipe(accent)
	elif _has_any(cleaned, ["staff", "wand", "magic wand"]):
		title = "Generated Staff"
		kind = "staff"
		parts = _staff_recipe(accent)
	elif _has_any(cleaned, ["bow", "longbow"]):
		title = "Generated Bow"
		kind = "bow"
		parts = _bow_recipe(accent)
	elif _has_any(cleaned, ["shield", "buckler"]):
		title = "Generated Shield"
		kind = "shield"
		parts = _shield_recipe(accent)
	elif _has_any(cleaned, ["tree", "pine", "evergreen"]):
		title = "Generated Tree"
		kind = "tree"
		parts = _tree_recipe(accent)
	elif _has_any(cleaned, ["house", "cottage", "building", "hut"]):
		title = "Generated House"
		kind = "house"
		parts = _house_recipe(accent)
	elif _has_any(cleaned, ["chest", "crate", "box"]):
		title = "Generated Chest"
		kind = "chest"
		parts = _chest_recipe(accent)
	elif _has_any(cleaned, ["crystal", "gem", "rock"]):
		title = "Generated Crystal"
		kind = "crystal"
		parts = _crystal_recipe(accent)
	elif _has_any(cleaned, ["character", "hero", "person", "humanoid", "robot"]):
		title = "Generated Character Blockout"
		kind = "character"
		parts = _character_recipe(accent)
	else:
		parts = _prop_recipe(accent)
	if parts.size() > MAX_PARTS:
		parts.resize(MAX_PARTS)
	return {
		"ok": true,
		"name": title,
		"kind": kind,
		"style": style,
		"parts": parts,
		"message": "%s ready • %d editable parts • %s style. Select any part to refine it." % [title, parts.size(), style]
	}

static func _sword_recipe(accent: Color) -> Array:
	return [
		_part("Blade", "Cube", [0.0, 1.35, 0.0], [0.16, 1.25, 0.06], Color(0.72, 0.80, 0.92), [0.0, 0.0, 0.0], 0.82, 0.22),
		_part("Guard", "Cube", [0.0, 0.0, 0.0], [0.85, 0.10, 0.18], accent, [0.0, 0.0, 0.0], 0.25, 0.35),
		_part("Grip", "Cylinder", [0.0, -0.62, 0.0], [0.14, 0.48, 0.14], Color(0.20, 0.12, 0.10), [0.0, 0.0, 0.0], 0.0, 0.78),
		_part("Pommel", "Sphere", [0.0, -1.20, 0.0], [0.22, 0.22, 0.22], accent, [0.0, 0.0, 0.0], 0.35, 0.28)
	]

static func _staff_recipe(accent: Color) -> Array:
	return [
		_part("Staff Shaft", "Cylinder", [0.0, 0.0, 0.0], [0.12, 1.65, 0.12], Color(0.22, 0.12, 0.08), [0.0, 0.0, 0.0], 0.0, 0.82),
		_part("Staff Orb", "Sphere", [0.0, 1.78, 0.0], [0.38, 0.38, 0.38], accent, [0.0, 0.0, 0.0], 0.55, 0.20),
		_part("Staff Collar", "Cylinder", [0.0, 1.42, 0.0], [0.22, 0.10, 0.22], accent.lightened(0.18), [0.0, 0.0, 0.0], 0.45, 0.25),
		_part("Staff Cap", "Cone", [0.0, -1.70, 0.0], [0.22, 0.18, 0.22], Color(0.35, 0.20, 0.12), [0.0, 0.0, 0.0], 0.0, 0.75)
	]

static func _bow_recipe(accent: Color) -> Array:
	return [
		_part("Upper Limb", "Cylinder", [-0.48, 0.58, 0.0], [0.09, 0.72, 0.09], accent, [0.0, 0.0, -0.55], 0.1, 0.42),
		_part("Lower Limb", "Cylinder", [-0.48, -0.58, 0.0], [0.09, 0.72, 0.09], accent, [0.0, 0.0, 0.55], 0.1, 0.42),
		_part("Grip", "Cylinder", [0.0, 0.0, 0.0], [0.13, 0.35, 0.13], Color(0.25, 0.14, 0.09), [0.0, 0.0, 0.0], 0.0, 0.80),
		_part("Bow String", "Cube", [-0.96, 0.0, 0.0], [0.025, 1.22, 0.025], Color(0.90, 0.90, 0.78), [0.0, 0.0, 0.0], 0.0, 0.75),
		_part("Arrow Rest", "Cube", [0.22, 0.0, 0.0], [0.62, 0.035, 0.035], Color(0.78, 0.80, 0.86), [0.0, 0.0, 0.0], 0.5, 0.28)
	]

static func _shield_recipe(accent: Color) -> Array:
	return [
		_part("Shield Body", "Sphere", [0.0, 0.0, 0.0], [1.05, 1.25, 0.18], accent, [0.0, 0.0, 0.0], 0.12, 0.38),
		_part("Shield Boss", "Sphere", [0.0, 0.0, -0.22], [0.28, 0.28, 0.18], Color(0.82, 0.68, 0.22), [0.0, 0.0, 0.0], 0.72, 0.20),
		_part("Shield Grip", "Cylinder", [0.0, 0.0, 0.10], [0.14, 0.52, 0.14], Color(0.20, 0.12, 0.08), [1.5708, 0.0, 0.0], 0.0, 0.82),
		_part("Shield Rim", "Cylinder", [0.0, 0.0, 0.18], [1.12, 0.08, 1.12], Color(0.82, 0.68, 0.22), [0.0, 0.0, 0.0], 0.75, 0.20)
	]

static func _tree_recipe(accent: Color) -> Array:
	var foliage := accent if accent != Color(0.30, 0.70, 0.34) else Color(0.30, 0.70, 0.34)
	return [
		_part("Trunk", "Cylinder", [0.0, -0.45, 0.0], [0.34, 1.05, 0.34], Color(0.30, 0.16, 0.08), [0.0, 0.0, 0.0], 0.0, 0.90),
		_part("Lower Canopy", "Cone", [0.0, 0.72, 0.0], [1.25, 0.92, 1.25], foliage, [0.0, 0.0, 0.0], 0.0, 0.72),
		_part("Upper Canopy", "Cone", [0.0, 1.55, 0.0], [0.92, 0.85, 0.92], foliage.lightened(0.12), [0.0, 0.0, 0.0], 0.0, 0.68),
		_part("Tree Top", "Cone", [0.0, 2.22, 0.0], [0.56, 0.78, 0.56], foliage.lightened(0.20), [0.0, 0.0, 0.0], 0.0, 0.64)
	]

static func _house_recipe(accent: Color) -> Array:
	return [
		_part("House Body", "Cube", [0.0, 0.0, 0.0], [2.20, 1.45, 1.80], accent, [0.0, 0.0, 0.0], 0.0, 0.72),
		_part("Roof", "Cone", [0.0, 1.85, 0.0], [2.45, 1.05, 2.05], accent.darkened(0.28), [0.0, 0.0, 0.0], 0.0, 0.76),
		_part("Door", "Cube", [0.0, -0.48, -1.84], [0.38, 0.72, 0.10], Color(0.28, 0.14, 0.08), [0.0, 0.0, 0.0], 0.0, 0.84),
		_part("Window", "Cube", [-0.92, 0.18, -1.85], [0.34, 0.34, 0.08], Color(0.35, 0.72, 0.92), [0.0, 0.0, 0.0], 0.15, 0.22),
		_part("Chimney", "Cube", [1.25, 1.72, 0.40], [0.22, 0.65, 0.22], Color(0.44, 0.20, 0.16), [0.0, 0.0, 0.0], 0.0, 0.88)
	]

static func _chest_recipe(accent: Color) -> Array:
	return [
		_part("Chest Body", "Cube", [0.0, -0.25, 0.0], [1.40, 0.70, 0.90], accent.darkened(0.12), [0.0, 0.0, 0.0], 0.0, 0.76),
		_part("Chest Lid", "Cube", [0.0, 0.58, 0.0], [1.48, 0.22, 0.96], accent, [0.0, 0.0, 0.0], 0.0, 0.70),
		_part("Chest Lock", "Cube", [0.0, 0.08, -0.94], [0.18, 0.24, 0.08], Color(0.86, 0.66, 0.20), [0.0, 0.0, 0.0], 0.78, 0.22),
		_part("Chest Band", "Cube", [0.0, -0.25, -0.94], [0.10, 0.70, 0.08], Color(0.86, 0.66, 0.20), [0.0, 0.0, 0.0], 0.78, 0.22)
	]

static func _crystal_recipe(accent: Color) -> Array:
	return [
		_part("Crystal Base", "Cylinder", [0.0, -0.55, 0.0], [0.70, 0.22, 0.70], Color(0.26, 0.28, 0.35), [0.0, 0.0, 0.0], 0.35, 0.30),
		_part("Crystal", "Cone", [0.0, 0.62, 0.0], [0.62, 1.20, 0.62], accent, [0.0, 0.0, 0.0], 0.45, 0.18),
		_part("Crystal Shard", "Cone", [0.40, 0.25, 0.12], [0.24, 0.74, 0.24], accent.lightened(0.20), [0.0, 0.0, 0.28], 0.45, 0.16)
	]

static func _character_recipe(accent: Color) -> Array:
	return [
		_part("Body", "Sphere", [0.0, 0.45, 0.0], [0.72, 0.95, 0.46], accent, [0.0, 0.0, 0.0], 0.0, 0.60),
		_part("Head", "Sphere", [0.0, 1.75, 0.0], [0.52, 0.52, 0.52], Color(0.90, 0.68, 0.52), [0.0, 0.0, 0.0], 0.0, 0.72),
		_part("Left Arm", "Cylinder", [-0.90, 0.42, 0.0], [0.16, 0.62, 0.16], accent, [0.0, 0.0, -0.35], 0.0, 0.62),
		_part("Right Arm", "Cylinder", [0.90, 0.42, 0.0], [0.16, 0.62, 0.16], accent, [0.0, 0.0, 0.35], 0.0, 0.62),
		_part("Left Leg", "Cylinder", [-0.32, -0.82, 0.0], [0.20, 0.72, 0.20], Color(0.18, 0.22, 0.35), [0.0, 0.0, 0.0], 0.0, 0.82),
		_part("Right Leg", "Cylinder", [0.32, -0.82, 0.0], [0.20, 0.72, 0.20], Color(0.18, 0.22, 0.35), [0.0, 0.0, 0.0], 0.0, 0.82)
	]

static func _prop_recipe(accent: Color) -> Array:
	return [
		_part("Prop Body", "Cube", [0.0, 0.0, 0.0], [0.85, 0.85, 0.85], accent, [0.0, 0.0, 0.0], 0.15, 0.58),
		_part("Prop Accent", "Sphere", [0.0, 0.92, 0.0], [0.32, 0.32, 0.32], accent.lightened(0.20), [0.0, 0.0, 0.0], 0.35, 0.24),
		_part("Prop Base", "Cylinder", [0.0, -0.86, 0.0], [0.72, 0.12, 0.72], accent.darkened(0.25), [0.0, 0.0, 0.0], 0.15, 0.70)
	]

static func _part(part_name: String, shape: String, position: Array, scale: Array, color: Color, rotation: Array = [0.0, 0.0, 0.0], metallic: float = 0.0, roughness: float = 0.6) -> Dictionary:
	return {
		"name": part_name,
		"shape": shape,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"color": color,
		"metallic": metallic,
		"roughness": roughness
	}

static func _color_for(text: String) -> Color:
	if text.contains("red"): return Color(0.84, 0.24, 0.30)
	if text.contains("blue"): return Color(0.25, 0.48, 0.86)
	if text.contains("green"): return Color(0.30, 0.70, 0.34)
	if text.contains("purple"): return Color(0.56, 0.28, 0.86)
	if text.contains("gold"): return Color(0.90, 0.65, 0.18)
	if text.contains("silver"): return Color(0.68, 0.73, 0.82)
	if text.contains("black"): return Color(0.10, 0.11, 0.15)
	if text.contains("white"): return Color(0.90, 0.92, 0.96)
	if text.contains("orange"): return Color(0.90, 0.42, 0.18)
	return Color(0.30, 0.70, 0.34) if _has_any(text, ["tree", "pine", "evergreen"]) else Color(0.36, 0.56, 0.88)

static func _has_any(text: String, terms: Array) -> bool:
	for term in terms:
		if text.contains(str(term)):
			return true
	return false

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "parts": [], "message": message}
