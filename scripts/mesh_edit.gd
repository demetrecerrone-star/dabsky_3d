extends RefCounted

# Light mobile mesh editor for static triangle geometry.
# Each edited surface is de-indexed so a picked triangle can be inset/extruded,
# while vertex movement welds matching positions along shared edges.
const MAX_TRIANGLES := 20000
const EPSILON := 0.00001

static func _primitive_type(mesh: Mesh, surface: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(surface)
	return Mesh.PRIMITIVE_TRIANGLES

static func _surface_data(mesh: Mesh, surface: int) -> Dictionary:
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return {}
	if _primitive_type(mesh, surface) != Mesh.PRIMITIVE_TRIANGLES:
		return {}
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return {}
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var texcoords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var total := indices.size() if not indices.is_empty() else vertices.size()
	if total == 0 or total % 3 != 0 or total / 3 > MAX_TRIANGLES:
		return {}
	var positions := PackedVector3Array()
	var uv := PackedVector2Array()
	var tint := PackedColorArray()
	for i in range(total):
		var source: int = indices[i] if not indices.is_empty() else i
		if source < 0 or source >= vertices.size():
			return {}
		positions.append(vertices[source])
		uv.append(texcoords[source] if texcoords.size() == vertices.size() else Vector2.ZERO)
		tint.append(colors[source] if colors.size() == vertices.size() else Color.WHITE)
	return {"positions": positions, "uv": uv, "colors": tint}

static func triangle_count(mesh: Mesh, surface: int = 0) -> int:
	var data := _surface_data(mesh, surface)
	if data.is_empty():
		return 0
	var positions: PackedVector3Array = data["positions"]
	return positions.size() / 3

static func face_vertices(mesh: Mesh, surface: int, face: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	var data := _surface_data(mesh, surface)
	if data.is_empty():
		return result
	var vertices: PackedVector3Array = data["positions"]
	if face < 0 or face * 3 + 2 >= vertices.size():
		return result
	for j in range(3):
		result.append(vertices[face * 3 + j])
	return result

static func _assemble(mesh: Mesh, changed_surface: int, data: Dictionary) -> ArrayMesh:
	var output := ArrayMesh.new()
	for surface in range(mesh.get_surface_count()):
		if surface == changed_surface:
			var positions: PackedVector3Array = data["positions"]
			var uv: PackedVector2Array = data["uv"]
			var colors: PackedColorArray = data["colors"]
			var normals := PackedVector3Array()
			for i in range(0, positions.size(), 3):
				var normal := (positions[i + 1] - positions[i]).cross(positions[i + 2] - positions[i]).normalized()
				for k in range(3):
					normals.append(normal)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = positions
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_COLOR] = colors
			output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		else:
			output.add_surface_from_arrays(_primitive_type(mesh, surface), mesh.surface_get_arrays(surface))
		var material := mesh.surface_get_material(surface)
		if material != null:
			output.surface_set_material(surface, material)
	return output

static func move_vertex(mesh: Mesh, vertex: Vector3, delta: Vector3) -> ArrayMesh:
	if delta.length_squared() <= 0.0:
		return null
	var output := ArrayMesh.new()
	var changed := false
	for surface in range(mesh.get_surface_count()):
		var data := _surface_data(mesh, surface)
		if data.is_empty():
			output.add_surface_from_arrays(_primitive_type(mesh, surface), mesh.surface_get_arrays(surface))
		else:
			var positions: PackedVector3Array = data["positions"]
			var modified := false
			for index in range(positions.size()):
				if positions[index].distance_squared_to(vertex) <= EPSILON * EPSILON:
					positions[index] += delta
					modified = true
			if modified:
				changed = true
				data["positions"] = positions
				var partial := _assemble(mesh, surface, data)
				output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, partial.surface_get_arrays(surface))
			else:
				output.add_surface_from_arrays(_primitive_type(mesh, surface), mesh.surface_get_arrays(surface))
		var material := mesh.surface_get_material(surface)
		if material != null:
			output.surface_set_material(surface, material)
	if not changed:
		return null
	return output

static func ray_pick_face(mesh: Mesh, start: Vector3, direction: Vector3) -> Dictionary:
	var best_distance := INF
	var result := {}
	for surface in range(mesh.get_surface_count()):
		var data := _surface_data(mesh, surface)
		if data.is_empty():
			continue
		var vertices: PackedVector3Array = data["positions"]
		for index in range(0, vertices.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(start, direction,
				vertices[index], vertices[index + 1], vertices[index + 2])
			if hit is Vector3:
				var world_hit: Vector3 = hit
				var distance := start.distance_squared_to(world_hit)
				if distance < best_distance:
					best_distance = distance
					result = {"surface": surface, "face": index / 3, "point": world_hit}
	return result

static func extrude_face(mesh: Mesh, surface: int, face: int, distance: float) -> ArrayMesh:
	var data := _surface_data(mesh, surface)
	if data.is_empty() or is_zero_approx(distance):
		return null
	var positions: PackedVector3Array = data["positions"]
	var uv: PackedVector2Array = data["uv"]
	var colors: PackedColorArray = data["colors"]
	var base := face * 3
	if face < 0 or base + 2 >= positions.size() or positions.size() / 3 + 6 > MAX_TRIANGLES:
		return null
	var a: Vector3 = positions[base]
	var b: Vector3 = positions[base + 1]
	var c: Vector3 = positions[base + 2]
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < EPSILON:
		return null
	var offset: Vector3 = normal * distance
	for i in range(3):
		positions[base + i] += offset
	var sides := [
		[a, b, b + offset], [a, b + offset, a + offset],
		[b, c, c + offset], [b, c + offset, b + offset],
		[c, a, a + offset], [c, a + offset, c + offset]
	]
	for points in sides:
		for point in points:
			positions.append(point)
			uv.append(Vector2.ZERO)
			colors.append(Color.WHITE)
	data["positions"] = positions
	data["uv"] = uv
	data["colors"] = colors
	return _assemble(mesh, surface, data)

static func inset_face(mesh: Mesh, surface: int, face: int, fraction: float = 0.2) -> ArrayMesh:
	var data := _surface_data(mesh, surface)
	if data.is_empty() or fraction <= 0.0 or fraction >= 0.49:
		return null
	var positions: PackedVector3Array = data["positions"]
	var uv: PackedVector2Array = data["uv"]
	var colors: PackedColorArray = data["colors"]
	var base := face * 3
	if face < 0 or base + 2 >= positions.size() or positions.size() / 3 + 6 > MAX_TRIANGLES:
		return null
	var a: Vector3 = positions[base]
	var b: Vector3 = positions[base + 1]
	var c: Vector3 = positions[base + 2]
	var centroid := (a + b + c) / 3.0
	var inner := [a.lerp(centroid, fraction), b.lerp(centroid, fraction), c.lerp(centroid, fraction)]
	var original := [a, b, c]
	for i in range(3):
		positions[base + i] = inner[i]
	for edge in range(3):
		var nxt := (edge + 1) % 3
		var tris := [[original[edge], original[nxt], inner[nxt]], [original[edge], inner[nxt], inner[edge]]]
		for triangle in tris:
			for vertex in triangle:
				positions.append(vertex)
				uv.append(Vector2.ZERO)
				colors.append(Color.WHITE)
	data["positions"] = positions
	data["uv"] = uv
	data["colors"] = colors
	return _assemble(mesh, surface, data)
