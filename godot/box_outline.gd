extends MeshInstance3D
## Zeichnet die 12 Kanten eines Einheitswuerfels (-0.5..0.5) als Linien.
## Als Kind der Volumen-Node erbt es deren Skalierung.

@export var color := Color(0.85, 0.9, 1.0, 1.0)


func _ready() -> void:
	var verts := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if i & bit == 0:
				verts.append(_corner(i))
				verts.append(_corner(i | bit))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = m

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _corner(i: int) -> Vector3:
	return Vector3(
		0.5 if i & 1 else -0.5,
		0.5 if i & 2 else -0.5,
		0.5 if i & 4 else -0.5)
