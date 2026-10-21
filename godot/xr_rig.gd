extends XROrigin3D
## VR-Rig fuer OpenXR (SteamVR) mit Flug-Locomotion. Ohne Headset bleibt die
## Desktop-Orbitkamera aktiv.
##
## Linker Stick (Vive: Trackpad): fliegen in Zeigerichtung des linken Controllers
##   (vor/zurueck, seitwaerts). Rechter Stick: x dreht stufenlos um die Kopfposition,
##   y steigt/sinkt senkrecht. Keine Teleport- oder Drehschritte.
## Groesse und Lage der Plotbox legt scene_view.gd fest (Raum in Metern).

@export var camera_path: NodePath
@export var left_path: NodePath
@export var right_path: NodePath
@export var desktop_camera_path: NodePath
@export var fly_speed: float = 2.0
@export var turn_speed_deg: float = 90.0
@export var deadzone: float = 0.15

var xr_active: bool = false

@onready var _camera: XRCamera3D = get_node_or_null(camera_path)
@onready var _left: XRController3D = get_node_or_null(left_path)
@onready var _right: XRController3D = get_node_or_null(right_path)


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		print("XR: kein OpenXR-Headset, Desktop-Ansicht.")
		_set_xr(false)
		return
	get_viewport().use_xr = true
	# Die Headset-Bildrate bestimmt den Takt, nicht das Desktop-Fenster.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_set_xr(true)
	print("XR: OpenXR aktiv.")


func _set_xr(on: bool) -> void:
	xr_active = on
	if _camera:
		_camera.current = on
	var desktop := get_node_or_null(desktop_camera_path) as Camera3D
	if desktop:
		desktop.current = not on
	for hand: XRController3D in [_left, _right]:
		if hand:
			hand.visible = on
	set_process(on)
	if on:
		for hand: XRController3D in [_left, _right]:
			if hand and hand.get_child_count() == 0:
				hand.add_child(_make_pointer())


func _process(delta: float) -> void:
	if _camera == null or _left == null or _right == null:
		return
	var move := _stick(_left)
	var look := _stick(_right)

	# Drehen um die Kopfposition, damit das Bild nicht seitlich wegwandert.
	if absf(look.x) > 0.0:
		var pivot := Transform3D(Basis.IDENTITY, _camera.global_position)
		var turn := Transform3D(Basis(Vector3.UP, -look.x * deg_to_rad(turn_speed_deg) * delta), Vector3.ZERO)
		global_transform = pivot * turn * pivot.affine_inverse() * global_transform

	# Fliegen entlang der Zeigerichtung des linken Controllers.
	var basis := _left.global_basis
	var velocity := (-basis.z * move.y + basis.x * move.x + Vector3.UP * look.y) * fly_speed
	global_position += velocity * delta


## Stick mit Totzone und neu skaliertem Restbereich (0 in der Totzone).
func _stick(hand: XRController3D) -> Vector2:
	var v := hand.get_vector2("primary")
	var len := v.length()
	if len < deadzone:
		return Vector2.ZERO
	return v / len * ((len - deadzone) / (1.0 - deadzone))


## Kleiner Quader in Zeigerichtung (-z), damit man die Controller sieht.
func _make_pointer() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.9, 0.9)
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(0.0, 0.0, -0.06)
	return mi
