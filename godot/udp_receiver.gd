extends MeshInstance3D
## Empfaengt Felder per UDP (Protokoll v2, siehe README / matlab/send_via_udp.m),
## setzt Chunks zu Frames zusammen und schreibt sie in eine Textur.
## 3D-Feld -> ImageTexture3D + Volumen-Shader (diese Node, BoxMesh).
## 2D-Feld (nz = 1) -> ImageTexture + Hoehenkarte (Node `heightmap`).

const MAGIC_DATA := 0x4456
const MAGIC_CONFIG := 0x4643
const VERSION := 2
const HEADER_SIZE := 32
const FORMAT_FLOAT32 := 0
const FORMAT_UINT8 := 1
const MAX_DIM := 512
const SENDER_TIMEOUT_MS := 2000
const DEFAULT_SIZE := 3.5
const COLORMAPS := {"rainbow": 0, "hot": 1, "gray": 2, "viridis": 3}

@export var port: int = 4242
@export var recv_buffer_size: int = 4 * 1024 * 1024
@export var heightmap: MeshInstance3D
@export var outline: Node3D
## Zeitliche Ueberblendung zwischen zwei Frames (glaettet niedrige Sende-FPS).
@export var interpolate: bool = true
## Konfigurationspakete (Colormap, Extent, ...) von MATLAB annehmen.
@export var allow_remote_config: bool = true

var udp := PacketPeerUDP.new()

# Materialien und Texturen (curr = aktuell, prev = vorheriger Frame)
var _vol_mat: ShaderMaterial
var _h_mat: ShaderMaterial
var _tex_curr: Resource
var _tex_prev: Resource

# Frame-Zusammenbau
var _frame_id: int = -1
var _chunks: Array = []
var _chunk_count: int = 0
var _chunks_got: int = 0
var _f_fmt: int = 0
var _f_dims := Vector3i.ZERO
var _f_vmin: float = 0.0
var _f_vmax: float = 1.0

# aktuelles Feld
var _dims := Vector3i.ZERO
var _fmt: int = -1
var _extent := Vector3.ZERO
var _extent_set: bool = false
var _t_arrival: float = 0.0
var _interval: float = 0.1

# Einzelner aktiver Absender
var _active_ip: String = ""
var _last_packet_ms: int = 0

# Anzeige / Statistik (vom Debug-Overlay gelesen)
var packets_per_s: float = 0.0
var frames_per_s: float = 0.0
var kb_per_frame: float = 0.0
var kb_per_s: float = 0.0
var dropped_frames: int = 0
var bad_packets: int = 0
var ignored_packets: int = 0
var last_sender: String = "-"
var listening: bool = false
var data_min: float = 0.0
var data_max: float = 1.0
var colormap_name: String = "rainbow"
var title: String = ""

var _stat_time: float = 0.0
var _stat_packets: int = 0
var _stat_frames: int = 0
var _stat_bytes: int = 0


func _ready() -> void:
	_vol_mat = material_override as ShaderMaterial
	if heightmap:
		_h_mat = heightmap.material_override as ShaderMaterial

	var err := udp.bind(port, "*", recv_buffer_size)
	listening = err == OK
	if listening:
		print("UDP-Empfaenger lauscht auf Port ", port)
	else:
		push_error("UDP bind auf Port %d fehlgeschlagen: %s" % [port, error_string(err)])

	# Platzhalter (leeres 32^3-Feld) bis das erste Paket kommt
	var images: Array[Image] = []
	for z in 32:
		images.append(Image.create(32, 32, false, Image.FORMAT_R8))
	_fmt = FORMAT_UINT8
	_rebuild(images, Image.FORMAT_R8, Vector3i(32, 32, 32))


func _exit_tree() -> void:
	udp.close()


func _process(delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		if udp.get_packet_error() != OK:
			continue
		var ip := udp.get_packet_ip()
		var now_ms := Time.get_ticks_msec()
		# Nur ein Absender gleichzeitig; nach 2 s Stille darf ein anderer uebernehmen
		if _active_ip != "" and ip != _active_ip and now_ms - _last_packet_ms < SENDER_TIMEOUT_MS:
			ignored_packets += 1
			continue
		_active_ip = ip
		_last_packet_ms = now_ms
		last_sender = "%s:%d" % [ip, udp.get_packet_port()]
		_stat_packets += 1
		_stat_bytes += pkt.size()
		_handle_packet(pkt)

	# Zeitliche Ueberblendung
	var blend := 1.0
	if interpolate and _interval > 0.0:
		blend = clampf((_now() - _t_arrival) / _interval, 0.0, 1.0)
	_set_common("blend", blend)

	_stat_time += delta
	if _stat_time >= 1.0:
		packets_per_s = _stat_packets / _stat_time
		frames_per_s = _stat_frames / _stat_time
		kb_per_s = _stat_bytes / 1024.0 / _stat_time
		_stat_time = 0.0
		_stat_packets = 0
		_stat_frames = 0
		_stat_bytes = 0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _handle_packet(pkt: PackedByteArray) -> void:
	if pkt.size() < 3:
		bad_packets += 1
		return
	var magic := pkt.decode_u16(0)
	if magic == MAGIC_CONFIG:
		_handle_config(pkt)
		return
	if magic != MAGIC_DATA or pkt.size() <= HEADER_SIZE or pkt.decode_u8(2) != VERSION:
		bad_packets += 1
		return

	var fmt := pkt.decode_u8(3)
	var frame_id := pkt.decode_u32(4)
	var idx := pkt.decode_u16(8)
	var count := pkt.decode_u16(10)
	var dims := Vector3i(pkt.decode_u16(12), pkt.decode_u16(14), pkt.decode_u16(16))
	if count == 0 or idx >= count or dims.x < 1 or dims.y < 1 or dims.z < 1 \
			or dims.x > MAX_DIM or dims.y > MAX_DIM or dims.z > MAX_DIM:
		bad_packets += 1
		return

	if frame_id != _frame_id:
		# Neuer Frame nur, wenn er "juenger" ist (uint32-Ueberlauf-sicher)
		if _frame_id >= 0 and ((frame_id - _frame_id) & 0xFFFFFFFF) >= 0x80000000:
			return  # verspaetetes Paket eines alten Frames
		if _frame_id >= 0 and _chunks_got < _chunk_count:
			dropped_frames += 1
		_frame_id = frame_id
		_chunk_count = count
		_chunks_got = 0
		_chunks.clear()
		_chunks.resize(count)
		_f_fmt = fmt
		_f_dims = dims
		_f_vmin = pkt.decode_float(20)
		_f_vmax = pkt.decode_float(24)

	if count != _chunk_count or dims != _f_dims or _chunks[idx] != null:
		return
	_chunks[idx] = pkt.slice(HEADER_SIZE)
	_chunks_got += 1

	if _chunks_got == _chunk_count:
		_finish_frame()


func _finish_frame() -> void:
	var bytes := PackedByteArray()
	for c: PackedByteArray in _chunks:
		bytes.append_array(c)

	var d := _f_dims
	var bpp := 4 if _f_fmt == FORMAT_FLOAT32 else 1
	if _f_fmt > FORMAT_UINT8 or bytes.size() != d.x * d.y * d.z * bpp:
		push_warning("Frame verworfen: Format %d, Grid %s, %d Byte" % [_f_fmt, d, bytes.size()])
		return

	var slice_bytes := d.x * d.y * bpp
	var image_format := Image.FORMAT_RF if _f_fmt == FORMAT_FLOAT32 else Image.FORMAT_R8
	var images: Array[Image] = []
	for z in d.z:
		images.append(Image.create_from_data(d.x, d.y, false, image_format,
				bytes.slice(z * slice_bytes, (z + 1) * slice_bytes)))

	if d != _dims or _f_fmt != _fmt:
		_fmt = _f_fmt
		_rebuild(images, image_format, d)
	else:
		_swap_and_update(images)

	# uint8-Texturen enthalten schon 0..1, float32-Texturen physikalische Werte
	if _f_fmt == FORMAT_UINT8:
		_set_common("value_min", 0.0)
		_set_common("value_max", 1.0)
	else:
		_set_common("value_min", _f_vmin)
		_set_common("value_max", _f_vmax if _f_vmax > _f_vmin else _f_vmin + 1.0)
	data_min = _f_vmin
	data_max = _f_vmax

	# Frame-Intervall glaetten
	var now := _now()
	if _t_arrival > 0.0:
		_interval = clampf(lerpf(_interval, now - _t_arrival, 0.2), 0.01, 2.0)
	_t_arrival = now

	kb_per_frame = bytes.size() / 1024.0
	_stat_frames += 1


## Neue Texturen (Groesse oder Format geaendert). prev und curr starten gleich.
func _rebuild(images: Array[Image], image_format: Image.Format, d: Vector3i) -> void:
	_dims = d
	if d.z == 1:
		_tex_curr = ImageTexture.create_from_image(images[0])
		_tex_prev = ImageTexture.create_from_image(images[0])
	else:
		_tex_curr = _make_tex3d(images, image_format, d)
		_tex_prev = _make_tex3d(images, image_format, d)
	_apply_layout()
	_assign_textures()


func _make_tex3d(images: Array[Image], image_format: Image.Format, d: Vector3i) -> ImageTexture3D:
	var t := ImageTexture3D.new()
	t.create(image_format, d.x, d.y, d.z, false, images)
	return t


## Ping-Pong: der bisherige aktuelle Frame wird zum vorigen, die aeltere Textur wird ueberschrieben.
func _swap_and_update(images: Array[Image]) -> void:
	var t := _tex_prev
	_tex_prev = _tex_curr
	_tex_curr = t
	if _dims.z == 1:
		(_tex_curr as ImageTexture).update(images[0])
	else:
		(_tex_curr as ImageTexture3D).update(images)
	_assign_textures()


func _assign_textures() -> void:
	if _dims.z == 1:
		if _h_mat:
			_h_mat.set_shader_parameter("height_tex", _tex_curr)
			_h_mat.set_shader_parameter("height_prev", _tex_prev)
	else:
		_vol_mat.set_shader_parameter("volume_tex", _tex_curr)
		_vol_mat.set_shader_parameter("volume_prev", _tex_prev)


func _default_extent() -> Vector3:
	var d := Vector3(_dims)
	if _dims.z == 1:
		var m := maxf(d.x, d.y)
		return Vector3(DEFAULT_SIZE * d.x / m, DEFAULT_SIZE * d.y / m, DEFAULT_SIZE * 0.5)
	return DEFAULT_SIZE * d / maxf(maxf(d.x, d.y), d.z)


## Sichtbarkeit, Skalierung und Mesh-Unterteilung je nach 2D/3D und Extent.
func _apply_layout() -> void:
	var is_2d := _dims.z == 1
	var ext := _extent if _extent_set else _default_extent()
	visible = not is_2d
	if is_2d:
		# Ebene liegt in XZ, Hoehe ist Y: Extent (x, y, z) -> Scale (x, z, y)
		var box_scale := Vector3(ext.x, ext.z, ext.y)
		if heightmap:
			heightmap.visible = true
			heightmap.scale = box_scale
			var pm := heightmap.mesh as PlaneMesh
			if pm:
				pm.subdivide_width = maxi(_dims.x - 2, 0)
				pm.subdivide_depth = maxi(_dims.y - 2, 0)
		if outline:
			outline.scale = box_scale
	else:
		scale = ext
		if heightmap:
			heightmap.visible = false
		if outline:
			outline.scale = ext


func _set_common(param: StringName, value: Variant) -> void:
	if _vol_mat:
		_vol_mat.set_shader_parameter(param, value)
	if _h_mat:
		_h_mat.set_shader_parameter(param, value)


func _handle_config(pkt: PackedByteArray) -> void:
	if not allow_remote_config:
		return
	var parsed: Variant = JSON.parse_string(pkt.slice(2).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		bad_packets += 1
		return
	var cfg: Dictionary = parsed
	if cfg.has("colormap"):
		colormap_name = str(cfg["colormap"])
		_set_common("colormap", COLORMAPS.get(colormap_name.to_lower(), 0))
	if cfg.has("density") and _vol_mat:
		_vol_mat.set_shader_parameter("density_scale", float(cfg["density"]))
	if cfg.has("threshold") and _vol_mat:
		_vol_mat.set_shader_parameter("threshold", float(cfg["threshold"]))
	if cfg.has("interpolate"):
		interpolate = bool(cfg["interpolate"])
	if cfg.has("title"):
		title = str(cfg["title"])
	if cfg.has("extent") and cfg["extent"] is Array and (cfg["extent"] as Array).size() == 3:
		var e: Array = cfg["extent"]
		var new_ext := Vector3(float(e[0]), float(e[1]), float(e[2]))
		if new_ext.x > 0.0 and new_ext.y > 0.0 and new_ext.z > 0.0 \
				and (not _extent_set or not new_ext.is_equal_approx(_extent)):
			_extent = new_ext
			_extent_set = true
			_apply_layout()
