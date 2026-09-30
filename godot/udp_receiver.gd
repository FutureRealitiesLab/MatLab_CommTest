extends MeshInstance3D
## Empfaengt Volumen-Chunks per UDP (siehe matlab/simulate_field.m), setzt sie zu
## einem Frame zusammen und schreibt ihn in eine ImageTexture3D.

const MAGIC := 0x4456
const HEADER_SIZE := 16
const FORMAT_FLOAT32 := 0
const FORMAT_UINT8 := 1

@export var port: int = 4242
@export var recv_buffer_size: int = 4 * 1024 * 1024
@export var texture_parameter: StringName = &"volume_tex"

var udp := PacketPeerUDP.new()
var texture: ImageTexture3D

# Frame-Zusammenbau
var _frame_id: int = -1
var _chunks: Array = []
var _chunk_count: int = 0
var _chunks_got: int = 0

# aktuelles Texturformat
var _grid: int = 0
var _fmt: int = -1

# Statistik (vom Debug-Overlay gelesen)
var packets_per_s: float = 0.0
var frames_per_s: float = 0.0
var kb_per_frame: float = 0.0
var kb_per_s: float = 0.0
var dropped_frames: int = 0
var last_sender: String = "-"
var listening: bool = false
var bad_packets: int = 0
var last_pkt_size: int = 0
var last_hdr: String = "-"

var _stat_time: float = 0.0
var _stat_packets: int = 0
var _stat_frames: int = 0
var _stat_bytes: int = 0


func _ready() -> void:
	var err := udp.bind(port, "*", recv_buffer_size)
	listening = err == OK
	if listening:
		print("UDP-Empfaenger lauscht auf Port ", port)
	else:
		push_error("UDP bind auf Port %d fehlgeschlagen: %s" % [port, error_string(err)])
	_create_texture(32, FORMAT_UINT8)  # Platzhalter bis das erste Paket kommt


func _exit_tree() -> void:
	udp.close()


func _process(delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		if udp.get_packet_error() != OK:
			continue
		last_sender = "%s:%d" % [udp.get_packet_ip(), udp.get_packet_port()]
		_stat_packets += 1
		_stat_bytes += pkt.size()
		last_pkt_size = pkt.size()
		last_hdr = pkt.slice(0, mini(16, pkt.size())).hex_encode()
		_handle_packet(pkt)

	_stat_time += delta
	if _stat_time >= 1.0:
		packets_per_s = _stat_packets / _stat_time
		frames_per_s = _stat_frames / _stat_time
		kb_per_s = _stat_bytes / 1024.0 / _stat_time
		_stat_time = 0.0
		_stat_packets = 0
		_stat_frames = 0
		_stat_bytes = 0


func _handle_packet(pkt: PackedByteArray) -> void:
	if pkt.size() <= HEADER_SIZE or pkt.decode_u16(0) != MAGIC:
		bad_packets += 1
		return
	var fmt := pkt.decode_u8(2)
	var frame_id := pkt.decode_u32(4)
	var idx := pkt.decode_u16(8)
	var count := pkt.decode_u16(10)
	var grid := pkt.decode_u16(12)
	if count == 0 or idx >= count or grid == 0:
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

	if count != _chunk_count or _chunks[idx] != null:
		return
	_chunks[idx] = pkt.slice(HEADER_SIZE)
	_chunks_got += 1

	if _chunks_got == _chunk_count:
		_finish_frame(fmt, grid)


func _finish_frame(fmt: int, grid: int) -> void:
	var bytes := PackedByteArray()
	for c: PackedByteArray in _chunks:
		bytes.append_array(c)

	var bpp := 4 if fmt == FORMAT_FLOAT32 else 1
	if fmt > FORMAT_UINT8 or bytes.size() != grid * grid * grid * bpp:
		push_warning("Frame verworfen: Format %d, Grid %d, %d Byte" % [fmt, grid, bytes.size()])
		return

	var slice_bytes := grid * grid * bpp
	var image_format := Image.FORMAT_RF if fmt == FORMAT_FLOAT32 else Image.FORMAT_R8
	var images: Array[Image] = []
	for z in grid:
		images.append(Image.create_from_data(grid, grid, false, image_format,
				bytes.slice(z * slice_bytes, (z + 1) * slice_bytes)))

	if grid != _grid or fmt != _fmt:
		_grid = grid
		_fmt = fmt
		texture = ImageTexture3D.new()
		texture.create(image_format, grid, grid, grid, false, images)
		_assign_texture()
	else:
		texture.update(images)

	kb_per_frame = bytes.size() / 1024.0
	_stat_frames += 1


func _create_texture(grid: int, fmt: int) -> void:
	var image_format := Image.FORMAT_RF if fmt == FORMAT_FLOAT32 else Image.FORMAT_R8
	var images: Array[Image] = []
	for z in grid:
		images.append(Image.create(grid, grid, false, image_format))
	texture = ImageTexture3D.new()
	texture.create(image_format, grid, grid, grid, false, images)
	_grid = grid
	_fmt = fmt
	_assign_texture()


func _assign_texture() -> void:
	(material_override as ShaderMaterial).set_shader_parameter(texture_parameter, texture)
