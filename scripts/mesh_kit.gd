extends RefCounted
## Small mesh helpers: merge many primitive meshes into one ArrayMesh so a
## detailed prop or viewmodel costs a single draw call per material.
## Used through: const MeshKit := preload("res://scripts/mesh_kit.gd")


static func box(size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Array:
	var mesh := BoxMesh.new()
	mesh.size = size
	return [mesh, xform(pos, rot_deg)]


## Cylinder along Y by default; pass rot_deg = (90, 0, 0) to lay it along Z.
static func cylinder(radius: float, height: float, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, segments: int = 12, top_radius: float = -1.0) -> Array:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return [mesh, xform(pos, rot_deg)]


static func capsule(radius: float, height: float, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Array:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 3
	var t := xform(pos, rot_deg)
	t.basis = t.basis.scaled_local(scale)
	return [mesh, t]


static func sphere(radius: float, pos: Vector3, scale: Vector3 = Vector3.ONE) -> Array:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var t := Transform3D(Basis().scaled(scale), pos)
	return [mesh, t]


static func torus(inner: float, outer: float, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Array:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 8
	return [mesh, xform(pos, rot_deg)]


static func xform(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(basis, pos)


## parts: Array of [Mesh, Transform3D]. Returns one mesh with a single surface.
static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for part in parts:
		var source: Mesh = part[0]
		var t: Transform3D = part[1]
		var arrays: Array = source.surface_get_arrays(0) if source is ArrayMesh else (source as PrimitiveMesh).get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var normal_basis := t.basis.inverse().transposed()
		for i in v.size():
			verts.append(t * v[i])
			normals.append((normal_basis * n[i]).normalized())
			uvs.append(uv[i] if i < uv.size() else Vector2.ZERO)
		for i in idx:
			indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## Adds a merged mesh as a MeshInstance3D child of parent.
static func add(parent: Node, parts: Array, material: Material, cast_shadow: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = merge(parts)
	instance.material_override = material
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
