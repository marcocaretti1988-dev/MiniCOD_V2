extends RefCounted
## Joins many small static meshes into a few big ones so
## the level costs far fewer draw calls. Looks the same:
## vertices, normals, tangents and UVs are kept.
##
## Meshes are grouped by material, shadow setting and map
## cell. Materials mapped in object space (local triplanar)
## are left alone, unless the mesh has the meta
## "merge_local": those are joined inside their parent.
## Used through:
## const MeshMerger := preload("res://scripts/mesh_merger.gd")

const CELL := 20.0  # metres: keeps culling and light limits


## Merges every suitable MeshInstance3D below root.
## Returns the number of meshes removed.
## cell: size of the map squares used for grouping;
## 0 = one group per material (for a single object).
## whole: root is one rigid object (a soldier, a gun),
## so every part can be joined in its space.
static func merge_tree(root: Node3D, cell: float = CELL,
		whole: bool = false) -> int:
	var groups: Dictionary = {}
	var opts := [cell, whole]
	_collect(root, root, groups, opts)
	var removed := 0
	for key in groups:
		var group: Dictionary = groups[key]
		var items: Array = group["items"]
		if items.size() < 2:
			continue
		_build(group)
		for item in items:
			var old: MeshInstance3D = item[0]
			old.get_parent().remove_child(old)
			old.queue_free()
		removed += items.size() - 1
	return removed


static func _collect(node: Node, root: Node3D,
		groups: Dictionary, opts: Array) -> void:
	for child in node.get_children():
		_collect(child, root, groups, opts)
	var size: float = opts[0]
	var whole: bool = opts[1]
	var inst := node as MeshInstance3D
	if inst == null or not _can_merge(inst):
		return
	var mat := inst.material_override as StandardMaterial3D
	var parent := root
	var xform := _relative(inst, root)
	var cell := ""
	if whole or size <= 0.0:
		if _is_local(mat) and not whole:
			return
	elif _is_local(mat):
		if not inst.has_meta("merge_local"):
			return
		parent = inst.get_parent() as Node3D
		if parent == null:
			return
		xform = inst.transform
		cell = str(parent.get_instance_id())
	else:
		var p := xform.origin
		cell = "%d_%d" % [
			floori(p.x / size), floori(p.z / size)]
	var key := "%d|%d|%s" % [
		mat.get_instance_id(), inst.cast_shadow, cell]
	if not groups.has(key):
		groups[key] = {
			"items": [], "parent": parent,
			"material": mat, "shadow": inst.cast_shadow,
		}
	groups[key]["items"].append([inst, xform])


## Transform of node in the space of root (an ancestor).
## Works even before the nodes enter the scene tree.
static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform


static func _can_merge(inst: MeshInstance3D) -> bool:
	if inst.mesh == null or not inst.visible:
		return false
	if inst.mesh.get_surface_count() != 1:
		return false
	if inst.get_child_count() > 0 or inst.get_script() != null:
		return false
	if inst.has_meta("no_merge"):
		return false
	if inst.visibility_range_end > 0.0:
		return false
	var mat := inst.material_override as StandardMaterial3D
	if mat == null:
		return false
	return mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED


## True when the texture is mapped in object space, so
## moving the mesh into another space would shift it.
static func _is_local(mat: StandardMaterial3D) -> bool:
	if mat.uv1_triplanar and not mat.uv1_world_triplanar:
		return true
	return mat.detail_enabled and mat.uv2_triplanar \
		and not mat.uv2_world_triplanar


static func _build(group: Dictionary) -> void:
	var sources := []
	for item in group["items"]:
		var inst: MeshInstance3D = item[0]
		sources.append(
			[inst.mesh.surface_get_arrays(0), item[1]])
	var merged := MeshInstance3D.new()
	merged.name = "Merged"
	merged.mesh = _join(sources)
	merged.material_override = group["material"]
	merged.cast_shadow = group["shadow"]
	(group["parent"] as Node3D).add_child(merged)


## Joins surfaces into one mesh.
## sources: [[surface arrays, Transform3D], ...]
static func _join(sources: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for source in sources:
		var arrays: Array = source[0]
		var t: Transform3D = source[1]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var count := v.size()
		var tg := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			tg = arrays[Mesh.ARRAY_TANGENT]
		var uv := PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			uv = arrays[Mesh.ARRAY_TEX_UV]
		var base := verts.size()
		var nb := t.basis.inverse().transposed()
		for i in count:
			verts.append(t * v[i])
			normals.append((nb * n[i]).normalized())
			uvs.append(uv[i] if i < uv.size() else Vector2.ZERO)
			var tan := Vector3(1, 0, 0)
			var w := 1.0
			if tg.size() >= (i + 1) * 4:
				tan = Vector3(
					tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])
				w = tg[i * 4 + 3]
			tan = (t.basis * tan).normalized()
			tangents.append(tan.x)
			tangents.append(tan.y)
			tangents.append(tan.z)
			tangents.append(w)
		if arrays[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in idx:
				indices.append(base + i)
		else:
			for i in count:
				indices.append(base + i)

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TANGENT] = tangents
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


# ---------------------------------------------------------
# Imported models (glb / fbx)
# ---------------------------------------------------------

static var _models: Dictionary = {}


## Turns an imported model into one mesh per material,
## standing on the origin: x and z centred, bottom at y = 0.
## Returns {"parts": [[ArrayMesh, Material], ...],
## "size": Vector3}. The result is cached per scene.
## detail: 1 = full model; 0.25 = about a quarter of the
## triangles, taken from the simplified versions (LODs)
## that Godot builds when it imports the model.
static func flatten_scene(scene: PackedScene,
		detail: float = 1.0) -> Dictionary:
	var key := "%s|%.2f" % [scene.resource_path, detail]
	if _models.has(key):
		return _models[key]
	var inst := scene.instantiate()
	var by_mat: Dictionary = {}
	var bounds := [Vector3.INF, -Vector3.INF, detail]
	_gather(inst, inst, by_mat, bounds)
	var low: Vector3 = bounds[0]
	var high: Vector3 = bounds[1]
	var centre := (low + high) * 0.5
	var shift := Transform3D(
		Basis(), -Vector3(centre.x, low.y, centre.z))
	var parts := []
	for id in by_mat:
		var entry: Array = by_mat[id]
		var sources := []
		for source in entry[1]:
			sources.append([source[0], shift * source[1]])
		parts.append([_join(sources), entry[0]])
	inst.free()
	var model := {"parts": parts, "size": high - low}
	_models[key] = model
	return model


static func _gather(node: Node, root: Node, by_mat: Dictionary,
		bounds: Array) -> void:
	var inst := node as MeshInstance3D
	if inst != null and inst.mesh != null:
		var xform := Transform3D.IDENTITY
		if node != root:
			xform = _relative(inst, root as Node3D)
		for s in inst.mesh.get_surface_count():
			var mat := inst.get_active_material(s)
			var arrays := inst.mesh.surface_get_arrays(s)
			var detail: float = bounds[2]
			if detail < 1.0:
				_use_lod(inst.mesh, s, arrays, detail)
			var id := 0 if mat == null else mat.get_instance_id()
			if not by_mat.has(id):
				by_mat[id] = [mat, []]
			by_mat[id][1].append([arrays, xform])
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for p in v:
				var q := xform * p
				bounds[0] = (bounds[0] as Vector3).min(q)
				bounds[1] = (bounds[1] as Vector3).max(q)
	for child in node.get_children():
		_gather(child, root, by_mat, bounds)


## Swaps the triangle list for the smallest LOD that still
## keeps at least `detail` of the triangles.
static func _use_lod(mesh: Mesh, surface: int, arrays: Array,
		detail: float) -> void:
	if arrays[Mesh.ARRAY_INDEX] == null:
		return
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var data: Dictionary = RenderingServer.mesh_get_surface(
		mesh.get_rid(), surface)
	var wide: bool = int(data.get("vertex_count", 0)) > 65535
	var step := 4 if wide else 2
	var best := PackedByteArray()
	for lod in data.get("lods", []):
		var bytes: PackedByteArray = lod["index_data"]
		var count := bytes.size() / step
		if float(count) < float(full.size()) * detail:
			break
		best = bytes
	if best.is_empty():
		return
	var indices := PackedInt32Array()
	indices.resize(best.size() / step)
	for i in indices.size():
		if wide:
			indices[i] = best.decode_u32(i * 4)
		else:
			indices[i] = best.decode_u16(i * 2)
	arrays[Mesh.ARRAY_INDEX] = indices


## Adds a flattened model under parent. Returns the new
## MeshInstance3D nodes (one per material).
static func place_model(parent: Node3D, model: Dictionary,
		xform: Transform3D, shadows: bool = true) -> Array:
	var placed := []
	for part in model["parts"]:
		var inst := MeshInstance3D.new()
		inst.mesh = part[0]
		inst.material_override = part[1]
		inst.transform = xform
		if not shadows:
			inst.cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inst)
		placed.append(inst)
	return placed


## Box whose six faces each show the whole texture (UV 0-1),
## like a local triplanar material scaled to the box, but
## with real UVs: boxes of any size can share one material
## and be merged.
static func face_box(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	# normal, U axis, V axis (V points down the texture)
	var faces := [
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN],
		[Vector3.LEFT, Vector3.BACK, Vector3.DOWN],
		[Vector3.BACK, Vector3.RIGHT, Vector3.DOWN],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var base := verts.size()
		var w := 1.0 if n.cross(u).dot(v) > 0.0 else -1.0
		for corner in [[0, 0], [1, 0], [1, 1], [0, 1]]:
			var cu: float = float(corner[0]) * 2.0 - 1.0
			var cv: float = float(corner[1]) * 2.0 - 1.0
			verts.append((n + u * cu + v * cv) * h)
			normals.append(n)
			uvs.append(Vector2(corner[0], corner[1]))
			tangents.append(u.x)
			tangents.append(u.y)
			tangents.append(u.z)
			tangents.append(w)
		# Front faces are clockwise in Godot.
		var a := verts[base]
		var b := verts[base + 1]
		var c := verts[base + 2]
		var order := [0, 1, 2, 0, 2, 3]
		if (b - a).cross(c - a).dot(n) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for i in order:
			indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
