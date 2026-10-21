extends Node3D
## Darstellung der empfangenen Frames (Port von udp/udpDrawnow.m).
##
## magic(1) Datentyp, magic(2) Dimension, magic(3) Darstellung, magic(4) Extra.
## Verschiedene Magics erzeugen getrennte Ebenen (S2i, S3i, V3q, P2p0, ...) in
## einer Plotbox von `box_size` Metern; jede Ebene wird nur bei geaenderter Form
## neu gebaut. Die Daten fuellen die Box (`stretch`) oder werden mit einem
## einheitlichen Faktor ohne Verzerrung eingepasst.
##
## Raum: Der Boden ist die x-y-Flaeche (x = box_size.x, y = box_size.y), z zeigt
## nach oben. 2D-Daten liegen auf dem Boden, 3D-Daten in einer Box, die `lift`
## Meter ueber dem Boden beginnt. Der Boden ist um den Ursprung zentriert.
##
## S2i Bild | S2s Hoehenflaeche | S3i<n> n Schnitte entlang z, S3i0 drei
## Mittelschnitte | S3v Volumen | V2q/V3q<k> Pfeile (k=0 automatisch)
## P2p<x> Partikelart x (+ Geschwindigkeitspfeile) | C2i Bild |
## C2m<0|1|2> Automat auf Ebene/Kugel/Torus.
##
## Koordinaten wie in MATLAB (x, y, z); die Node `Plot` dreht sie so, dass z in
## Godot nach oben zeigt. Texturen sind [ny nx nz] (Breite ny, Hoehe nx) und werden roh aus dem
## spaltenweisen Payload erzeugt; die Shader vertauschen x und y.

@export var receiver_path: NodePath
## Ausdehnung der Box in Metern: x, y (Bodenflaeche) und z (Hoehe der 3D-Box).
@export var box_size := Vector3(4.0, 8.0, 2.0)
## Hoehe der Unterkante der 3D-Box ueber dem Boden in Metern.
@export var lift: float = 0.5
## true: Daten fuellen die ganze Box (verzerrt bei anderem Seitenverhaeltnis).
@export var stretch: bool = true
## Radius der Partikelkugeln in Metern.
@export var particle_radius: float = 0.04
@export var outline_path: NodePath
@export var floor_outline_path: NodePath
## 0 rainbow, 1 hot, 2 gray, 3 viridis (Taste C wechselt).
@export var colormap: int = 0

const COLORMAP_NAMES := ["rainbow", "hot", "gray", "viridis"]
const SPECIES_COLORS := [
	Color(0.0, 0.447, 0.741), Color(0.85, 0.325, 0.098), Color(0.929, 0.694, 0.125),
	Color(0.494, 0.184, 0.556), Color(0.466, 0.674, 0.188), Color(0.301, 0.745, 0.933),
	Color(0.635, 0.078, 0.184),
]
const MAX_SURFACE_SEGMENTS := 255
const PACKED_TEX_WIDTH := 2048

var layers: Dictionary = {}
var current_magic: String = ""
var _session: int = -1
var _arrow_mesh: ArrayMesh
var _shaders: Dictionary = {}


func _ready() -> void:
	_arrow_mesh = _make_arrow_mesh()
	_apply_layout()
	var receiver := get_node_or_null(receiver_path)
	if receiver:
		receiver.frame_received.connect(show_frame)
	else:
		push_error("SceneView: receiver_path zeigt auf keine Node.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		colormap = (colormap + 1) % COLORMAP_NAMES.size()
		for layer: Dictionary in layers.values():
			for mat: ShaderMaterial in layer.mats:
				mat.set_shader_parameter("colormap", colormap)


func colormap_name() -> String:
	return COLORMAP_NAMES[colormap]


## Dreht `Plot` so, dass MATLAB-x nach +x, MATLAB-y nach -z (in den Raum) und
## MATLAB-z nach oben zeigt, und setzt die Rahmen von Box und Boden.
func _apply_layout() -> void:
	var plot := get_parent() as Node3D
	if plot:
		plot.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0),
				Vector3(-box_size.x / 2.0, 0.0, box_size.y / 2.0))
	var outline := get_node_or_null(outline_path) as Node3D
	if outline:
		outline.scale = box_size
		outline.position = box_size / 2.0 + Vector3(0.0, 0.0, lift)
	var floor_outline := get_node_or_null(floor_outline_path) as Node3D
	if floor_outline:
		floor_outline.scale = Vector3(box_size.x, box_size.y, 0.001)
		floor_outline.position = Vector3(box_size.x / 2.0, box_size.y / 2.0, 0.0)


## 2D-Daten liegen auf dem Boden, Kugel und Torus (C2m1, C2m2) in der 3D-Box.
func _on_floor(magic: String) -> bool:
	if magic[1] != "2":
		return false
	return not (magic.substr(1, 2) == "2m" and ["1", "2"].has(magic[3]))


func show_frame(magic: String, info: Dictionary, payload: PackedByteArray) -> void:
	# Eine neue Session verwirft alle Ebenen.
	if info.session_id != _session:
		_clear()
		_session = info.session_id
	current_magic = magic

	var key := magic.substr(0, 4) if magic[0] == "P" else magic.substr(0, 3)
	var dims: Array = info.dims
	var sig: Array = [dims[1]] if magic[0] == "P" else dims.duplicate()
	if magic[0] == "C":
		sig.append(info.nostates)
	var layer: Dictionary = layers.get(key, {})
	var rebuild: bool = layer.is_empty() or layer.magic != magic or layer.sig != sig
	if rebuild:
		if not layer.is_empty():
			layer.root.queue_free()
		layer = {"magic": magic, "sig": sig, "root": Node3D.new(), "mats": []}
		layer.root.position = Vector3.ZERO if _on_floor(magic) else Vector3(0.0, 0.0, lift)
		add_child(layer.root)
		layers[key] = layer

	var ok := false
	match magic[0]:
		"S":
			ok = _scalar(layer, rebuild, magic, dims, payload)
		"V":
			ok = _quiver(layer, rebuild, magic, info, payload)
		"P":
			ok = _particles(layer, rebuild, magic, dims, payload)
		"C":
			ok = _cellular(layer, rebuild, magic, info, payload)
	if not ok:
		push_warning("Keine Darstellung fuer Magic %s." % magic)
		layer.root.queue_free()
		layers.erase(key)


func _clear() -> void:
	for layer: Dictionary in layers.values():
		layer.root.queue_free()
	layers.clear()


# ---- Einpassen in die Box ---------------------------------------------------

## Faktoren s (Meter je Zelle und Achse) passen ext (Zellen je Achse) in box_size
## und zentrieren. Bei `stretch` fuellt jede Achse die Box, sonst gilt ein
## einheitlicher Faktor (ohne Verzerrung). Fehlende Achsen (2D) bleiben bei s.z = min(s).
func _fit(ext: Array) -> Dictionary:
	var s := Vector3.ONE * INF
	for i in ext.size():
		s[i] = box_size[i] / ext[i]
	var smin := minf(s.x, minf(s.y, s.z))
	if not stretch:
		s = Vector3.ONE * smin
	elif ext.size() < 3:
		s.z = smin
	var off := Vector3.ZERO
	for i in ext.size():
		off[i] = (box_size[i] - s[i] * ext[i]) / 2.0
	return {"s": s, "off": off}


# ---- Skalarfelder -----------------------------------------------------------

func _scalar(layer: Dictionary, rebuild: bool, magic: String, dims: Array, payload: PackedByteArray) -> bool:
	match magic.substr(1, 2):
		"2i":
			_field2d(layer, rebuild, dims[0], dims[1], payload, "plane", 1.0, false)
		"2s":
			_field2d(layer, rebuild, dims[0], dims[1], payload, "height", 1.0, false)
		"3i":
			return _slices(layer, rebuild, magic, dims, payload)
		"3v":
			_volume(layer, rebuild, dims, payload)
		_:
			return false
	return true


func _cellular(layer: Dictionary, rebuild: bool, magic: String, info: Dictionary, payload: PackedByteArray) -> bool:
	var dims: Array = info.dims
	var scale := 255.0 / maxf(1.0, info.nostates - 1.0)
	match magic.substr(1, 2):
		"2i":
			_field2d(layer, rebuild, dims[0], dims[1], payload, "plane", scale, true, info.bits)
		"2m":
			var kind := magic[3]
			if not ["0", "1", "2"].has(kind):
				return false
			var mode: String = ["plane", "sphere", "torus"][int(kind)]
			_field2d(layer, rebuild, dims[0], dims[1], payload, mode, scale, true, info.bits)
		_:
			return false
	return true


## Zweidimensionales Feld: erste Ebene [ny nx] als Textur auf Flaeche/Kugel/Torus/Hoehe.
## bits > 0: bytes sind bitgepackte Zustaende, die der Shader entpackt.
func _field2d(layer: Dictionary, rebuild: bool, ny: int, nx: int, bytes: PackedByteArray,
		mode: String, value_scale: float, nearest: bool, bits: int = 0) -> void:
	var img: Image
	if bits > 0:
		var needed := ceili(ny * nx * bits / 8.0)
		var rows := ceili(needed / float(PACKED_TEX_WIDTH))
		var padded := bytes.slice(0, needed)
		padded.resize(PACKED_TEX_WIDTH * rows)
		img = Image.create_from_data(PACKED_TEX_WIDTH, rows, false, Image.FORMAT_R8, padded)
	else:
		img = Image.create_from_data(ny, nx, false, Image.FORMAT_R8, bytes.slice(0, ny * nx))
	if not rebuild:
		(layer.tex as ImageTexture).update(img)
		return
	var tex := ImageTexture.create_from_image(img)
	layer.tex = tex

	var mat := ShaderMaterial.new()
	mat.shader = _shader("field_height" if mode == "height" else "field_image")
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("colormap", colormap)
	if bits > 0:
		mat.set_shader_parameter("packed_states", true)
		mat.set_shader_parameter("bits", bits)
		mat.set_shader_parameter("grid", Vector2i(ny, nx))
	var mesh: ArrayMesh
	var fit := _fit([nx, ny])
	var s: Vector3 = fit.s
	var off: Vector3 = fit.off
	var ext := Vector2(s.x * nx, s.y * ny)
	var round_size := minf(box_size.x, minf(box_size.y, box_size.z))
	match mode:
		"plane":
			mat.set_shader_parameter("value_scale", value_scale)
			mat.set_shader_parameter("nearest", nearest)
			mesh = _surface(1, 1, func(u: float, v: float) -> Vector3:
				return Vector3(off.x + ext.x * u, off.y + ext.y * v, 0.0))
		"height":
			mat.set_shader_parameter("extent", ext)
			mat.set_shader_parameter("height", 0.5 * box_size.z)
			mesh = _surface(clampi(nx, 1, MAX_SURFACE_SEGMENTS), clampi(ny, 1, MAX_SURFACE_SEGMENTS),
					func(u: float, v: float) -> Vector3:
				return Vector3(off.x + ext.x * u, off.y + ext.y * v, 0.0))
		"sphere":
			mat.set_shader_parameter("value_scale", value_scale)
			mat.set_shader_parameter("nearest", nearest)
			mesh = _surface(64, 32, func(u: float, v: float) -> Vector3:
				var phi := TAU * u
				var theta := PI * v
				return box_size / 2.0 + 0.5 * round_size * Vector3(
						sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)))
		_:  # torus
			mat.set_shader_parameter("value_scale", value_scale)
			mat.set_shader_parameter("nearest", nearest)
			mesh = _surface(64, 32, func(u: float, v: float) -> Vector3:
				var phi := TAU * u
				var theta := TAU * v
				var ring := 0.35 + 0.15 * cos(theta)
				return box_size / 2.0 + round_size * Vector3(
						ring * cos(phi), ring * sin(phi), 0.15 * sin(theta)))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.extra_cull_margin = 1.0
	layer.root.add_child(mi)
	layer.mats.append(mat)


## S3i<n>: n Schnitte entlang z, n=0 drei Mittelschnitte (xy, xz, yz).
func _slices(layer: Dictionary, rebuild: bool, magic: String, dims: Array, payload: PackedByteArray) -> bool:
	var ny: int = dims[0]
	var nx: int = dims[1]
	var nz: int = dims[2]
	var count := int(magic[3]) if magic[3].is_valid_int() else 0
	if nx < 2 or ny < 2 or (count == 0 and nz < 2):
		return false
	var images := _volume_images(ny, nx, nz, payload)
	if not rebuild:
		(layer.tex as ImageTexture3D).update(images)
		return true
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, ny, nx, nz, false, images)
	layer.tex = tex

	# [Achse, normierte Position]: 0 z konstant, 1 y konstant, 2 x konstant.
	var specs: Array = []
	if count == 0:
		specs = [[0, _mid(nz)], [2, _mid(nx)], [1, _mid(ny)]]
	else:
		var seen := {}
		for i in range(1, count + 1):
			var k := clampi(roundi((i - 0.5) * nz / count), 1, nz)
			if not seen.has(k):
				seen[k] = true
				specs.append([0, (k - 0.5) / nz])

	var fit := _fit([nx, ny, nz])
	var s: Vector3 = fit.s
	var off: Vector3 = fit.off
	var ext := Vector3(s.x * nx, s.y * ny, s.z * nz)
	for spec: Array in specs:
		var axis: int = spec[0]
		var pos: float = spec[1]
		var origin := off
		var du := Vector3.ZERO
		var dv := Vector3.ZERO
		match axis:
			0:
				origin.z += ext.z * pos
				du = Vector3(ext.x, 0, 0)
				dv = Vector3(0, ext.y, 0)
			1:
				origin.y += ext.y * pos
				du = Vector3(ext.x, 0, 0)
				dv = Vector3(0, 0, ext.z)
			_:
				origin.x += ext.x * pos
				du = Vector3(0, ext.y, 0)
				dv = Vector3(0, 0, ext.z)
		var mat := ShaderMaterial.new()
		mat.shader = _shader("field_slice")
		mat.set_shader_parameter("vol", tex)
		mat.set_shader_parameter("axis", axis)
		mat.set_shader_parameter("slice", pos)
		mat.set_shader_parameter("colormap", colormap)
		mat.set_shader_parameter("alpha", 0.5 if specs.size() > 1 else 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = _surface(1, 1, func(u: float, v: float) -> Vector3:
			return origin + du * u + dv * v)
		mi.material_override = mat
		layer.root.add_child(mi)
		layer.mats.append(mat)
	return true


func _mid(n: int) -> float:
	return (clampi(roundi(n / 2.0), 1, n) - 0.5) / n


func _volume(layer: Dictionary, rebuild: bool, dims: Array, payload: PackedByteArray) -> void:
	var ny: int = dims[0]
	var nx: int = dims[1]
	var nz: int = dims[2]
	var images := _volume_images(ny, nx, nz, payload)
	if not rebuild:
		(layer.tex as ImageTexture3D).update(images)
		return
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, ny, nx, nz, false, images)
	layer.tex = tex

	var fit := _fit([nx, ny, nz])
	var s: Vector3 = fit.s
	var off: Vector3 = fit.off
	var ext := Vector3(s.x * nx, s.y * ny, s.z * nz)
	var mat := ShaderMaterial.new()
	mat.shader = _shader("volume_raymarch")
	mat.set_shader_parameter("volume_tex", tex)
	mat.set_shader_parameter("colormap", colormap)
	var box := BoxMesh.new()
	box.size = ext
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = off + ext / 2.0
	mi.material_override = mat
	layer.root.add_child(mi)
	layer.mats.append(mat)


func _volume_images(ny: int, nx: int, nz: int, payload: PackedByteArray) -> Array[Image]:
	var images: Array[Image] = []
	var plane := ny * nx
	for z in nz:
		images.append(Image.create_from_data(ny, nx, false, Image.FORMAT_R8,
				payload.slice(z * plane, (z + 1) * plane)))
	return images


# ---- Vektorfelder -----------------------------------------------------------

## V2q/V3q<k>: k=0 automatisch skaliert, k>0 Pfeil fuer |v|=max(|vspan|) ist k Zellabstaende lang.
func _quiver(layer: Dictionary, rebuild: bool, magic: String, info: Dictionary, payload: PackedByteArray) -> bool:
	if magic[2] != "q":
		return false
	var dims: Array = info.dims
	var ny: int = dims[0]
	var nx: int = dims[1]
	var nz: int = dims[2]
	var is_2d := magic[1] == "2"
	var ncomp := 2 if is_2d else 3
	var sy := maxi(1, ceili(ny / (25.0 if is_2d else 12.0)))
	var sx := maxi(1, ceili(nx / (25.0 if is_2d else 12.0)))
	var sz := 1 if is_2d else maxi(1, ceili(nz / 8.0))
	var fit := _fit([nx, ny] if is_2d else [nx, ny, nz])
	var s: Vector3 = fit.s
	var off: Vector3 = fit.off
	var vspan: Array = info.vspan
	var vmax := maxf(absf(vspan[0]), absf(vspan[1]))
	if vmax == 0.0:
		vmax = 1.0
	var k := int(magic[3]) if magic[3].is_valid_int() else 0

	var positions := PackedVector3Array()
	var vectors := PackedVector3Array()
	var maxmag := 0.0
	for iz in range(0, 1 if is_2d else nz, sz):
		for ix in range(0, nx, sx):
			for iy in range(0, ny, sy):
				var v := Vector3.ZERO
				for c in ncomp:
					var q := payload[iy + ny * (ix + nx * (iz + nz * c))]
					v[c] = vspan[0] + q / 255.0 * (vspan[1] - vspan[0])
				var z := 0.0 if is_2d else off.z + s.z * (iz + 0.5)
				positions.append(Vector3(off.x + s.x * (ix + 0.5), off.y + s.y * (iy + 0.5), z))
				vectors.append(v)
				maxmag = maxf(maxmag, v.length())

	var spacing := minf(s.x * sx, s.y * sy)
	if not is_2d:
		spacing = minf(spacing, s.z * sz)
	var factor := 0.0
	if k > 0:
		factor = k * spacing / vmax
	elif maxmag > 0.0:
		factor = 0.9 * spacing / maxmag
	var ref := vmax if k > 0 else maxf(maxmag, 1e-12)
	var colors := PackedColorArray()
	var lengths := PackedFloat32Array()
	for v in vectors:
		colors.append(_rainbow(v.length() / ref))
		lengths.append(v.length() * factor)

	if rebuild:
		layer.mm = _arrow_instances(layer.root, positions.size())
	_set_arrows(layer.mm, positions, vectors, lengths, colors)
	return true


# ---- Partikel -----------------------------------------------------------------

## P2p<x>: Partikelart x; Spalten [x y (z)] in 0..1, dazu optional Geschwindigkeiten.
func _particles(layer: Dictionary, rebuild: bool, magic: String, dims: Array, payload: PackedByteArray) -> bool:
	if magic[2] != "p":
		return false
	var n: int = dims[0]
	var nc: int = dims[1]
	var nd := 3 if nc == 3 or nc == 6 else 2
	var species := int(magic[3]) if magic[3].is_valid_int() else 0
	var color: Color = SPECIES_COLORS[species % SPECIES_COLORS.size()]
	var data := payload.to_float32_array()
	var fit := _fit(_ones(nd))
	var s: Vector3 = fit.s
	var off: Vector3 = fit.off

	var positions := PackedVector3Array()
	var vectors := PackedVector3Array()
	var maxmag := 0.0
	for i in n:
		var p := Vector3.ZERO
		for c in nd:
			p[c] = off[c] + s[c] * data[i + n * c]
		positions.append(p)
		if nc > nd:
			var v := Vector3.ZERO
			for c in nd:
				v[c] = data[i + n * (nd + c)]
			vectors.append(v)
			maxmag = maxf(maxmag, v.length())

	if rebuild:
		var spheres := MultiMesh.new()
		spheres.transform_format = MultiMesh.TRANSFORM_3D
		var ball := SphereMesh.new()
		ball.radius = particle_radius
		ball.height = 2.0 * particle_radius
		ball.radial_segments = 8
		ball.rings = 4
		spheres.mesh = ball
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = spheres
		mi.material_override = _flat_material(color, false)
		layer.root.add_child(mi)
		layer.spheres = spheres
		layer.mm = null
	var spheres: MultiMesh = layer.spheres
	if spheres.instance_count != n:
		spheres.instance_count = n
	for i in n:
		spheres.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))

	if nc > nd:
		if rebuild or layer.mm == null or (layer.mm as MultiMesh).instance_count != n:
			if layer.mm == null:
				layer.mm = _arrow_instances(layer.root, n, color)
			else:
				(layer.mm as MultiMesh).instance_count = n
		# Laengster Pfeil: 8 % der kleinsten Boxkante.
		var longest := 0.08 * minf(box_size.x, minf(box_size.y, box_size.z))
		var lengths := PackedFloat32Array()
		var colors := PackedColorArray()
		for v in vectors:
			lengths.append(longest * v.length() / maxf(maxmag, 1e-12))
			colors.append(color)
		_set_arrows(layer.mm, positions, vectors, lengths, colors)
	return true


func _ones(n: int) -> Array:
	var a := []
	for i in n:
		a.append(1.0)
	return a


# ---- Pfeile -------------------------------------------------------------------

func _arrow_instances(root: Node3D, count: int, color := Color.WHITE) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _arrow_mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _flat_material(color, true)
	root.add_child(mi)
	return mm


func _set_arrows(mm: MultiMesh, positions: PackedVector3Array, vectors: PackedVector3Array,
		lengths: PackedFloat32Array, colors: PackedColorArray) -> void:
	for i in positions.size():
		var len := lengths[i]
		var basis := Basis.from_scale(Vector3.ZERO)
		if len > 1e-9:
			var x := vectors[i].normalized()
			var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			var z := x.cross(up).normalized()
			var y := z.cross(x)
			basis = Basis(x * len, y * len, z * len)
		mm.set_instance_transform(i, Transform3D(basis, positions[i]))
		mm.set_instance_color(i, colors[i])


func _flat_material(color: Color, vertex_colors: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = vertex_colors
	return mat


## Pfeil entlang +x mit Laenge 1: sechseckiger Schaft und Kegelspitze.
func _make_arrow_mesh() -> ArrayMesh:
	var sides := 6
	var shaft_r := 0.015
	var head_r := 0.05
	var neck := 0.7
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in sides:
		var a := TAU * i / sides
		verts.append(Vector3(0.0, cos(a) * shaft_r, sin(a) * shaft_r))
	for i in sides:
		var a := TAU * i / sides
		verts.append(Vector3(neck, cos(a) * shaft_r, sin(a) * shaft_r))
	for i in sides:
		var a := TAU * i / sides
		verts.append(Vector3(neck, cos(a) * head_r, sin(a) * head_r))
	var tip := verts.size()
	verts.append(Vector3(1.0, 0.0, 0.0))
	for i in sides:
		var j := (i + 1) % sides
		idx.append_array([i, j, sides + i, j, sides + j, sides + i])
		idx.append_array([2 * sides + i, 2 * sides + j, tip])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _rainbow(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var a := Color(0.05, 0.1, 0.9)
	var b := Color(0.0, 0.9, 0.9)
	var c := Color(1.0, 0.9, 0.1)
	var d := Color(1.0, 0.1, 0.05)
	if t < 0.33:
		return a.lerp(b, t / 0.33)
	if t < 0.66:
		return b.lerp(c, (t - 0.33) / 0.33)
	return c.lerp(d, (t - 0.66) / 0.34)


# ---- Hilfen ---------------------------------------------------------------------

func _shader(shader_name: String) -> Shader:
	if not _shaders.has(shader_name):
		_shaders[shader_name] = load("res://%s.gdshader" % shader_name)
	return _shaders[shader_name]


## Parametrische Flaeche mit UV = (u, v) auf dem Gitter nu x nv.
func _surface(nu: int, nv: int, fn: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			verts.append(fn.call(u, v))
			uvs.append(Vector2(u, v))
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
