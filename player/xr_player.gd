# TEMPLATE CORE – nicht verändern
extends XROrigin3D

## xr_player.gd – Lokaler XR-Spieler (Focus Vision / Quest / OpenXR).
##
## Beide Controller gleichwertig:
##   Primary   (A / X)  → Standalone-Modus aktivieren
##   Secondary (B / Y)  → nächste Szene
##   Thumbstick Y       → Vor/Zurück-Bewegung (beide Controller, max-Betrag gewinnt)
##   Thumbstick X       → Links/Rechts-Rotation (beide Controller, max-Betrag gewinnt)


## Sendeintervall in Sekunden (20 Hz)
const SEND_RATE: float = 0.05

## Bewegungsgeschwindigkeit (m/s) – im Godot-Editor einstellbar
@export var move_speed: float = 1.2

## Rotation via Thumbstick X aktivieren
@export var rotation_enabled: bool = true

## Drehgeschwindigkeit (Grad/s)
@export var rotation_speed: float = 60.0

var _send_timer: float = 0.0
var _stick_l: Vector2 = Vector2.ZERO
var _stick_r: Vector2 = Vector2.ZERO


func _ready() -> void:
	$XRCamera3D.make_current()
	if has_node("LeftHand"):
		$LeftHand.button_pressed.connect(_on_button)
		$LeftHand.input_vector2_changed.connect(_on_left_stick)
	if has_node("RightHand"):
		$RightHand.button_pressed.connect(_on_button)
		$RightHand.input_vector2_changed.connect(_on_right_stick)


func _on_button(button_name: String) -> void:
	# Standalone nur aktivieren, wenn KEINE Server-Verbindung besteht
	if not NetworkManager.client_connected_flag and not SceneManager.standalone_mode:
		SceneManager.activate_standalone()
	# Secondary Button (B/Y) → nächste Szene (nur im Standalone-Modus; im Multiplayer steuert der Server)
	if button_name == "by_button" and SceneManager.standalone_mode:
		SceneManager.advance_scene()


func _on_left_stick(_action: String, value: Vector2) -> void:
	_stick_l = value


func _on_right_stick(_action: String, value: Vector2) -> void:
	_stick_r = value


func _physics_process(delta: float) -> void:
	_send_timer += delta
	if _send_timer >= SEND_RATE:
		_send_timer = 0.0
		_broadcast_position()
	_do_locomotion(delta)


func _do_locomotion(delta: float) -> void:
	# Im Multiplayer (mit Server verbunden): KEINE Thumbstick-Bewegung erlaubt!
	# Verhindert Virtual/Physical Offset in Co-located VR – Besucher bewegen sich rein physisch.
	# Nur im Offline- / Standalone-Modus für Einzelnutzer aktiv.
	if not SceneManager.standalone_mode or NetworkManager.client_connected_flag:
		return

	# Vor/Zurück: Controller mit größtem Y-Betrag gewinnt
	var fwd: float = _stick_l.y if abs(_stick_l.y) >= abs(_stick_r.y) else _stick_r.y
	# Rotation: Controller mit größtem X-Betrag gewinnt
	var turn: float = _stick_l.x if abs(_stick_l.x) >= abs(_stick_r.x) else _stick_r.x

	if abs(fwd) > 0.2:
		var cam := $XRCamera3D as XRCamera3D
		var forward := -cam.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		global_position += forward * fwd * move_speed * delta
		_clamp_to_walk_area()

	if rotation_enabled and abs(turn) > 0.2:
		rotate_y(deg_to_rad(-turn * rotation_speed * delta))


func _clamp_to_walk_area() -> void:
	var walk_area := get_tree().root.find_child("XRWalkArea", true, false) as MeshInstance3D
	if not walk_area or not walk_area.mesh is PlaneMesh:
		return
	var plane := walk_area.mesh as PlaneMesh
	var half_x := plane.size.x * 0.5 * walk_area.scale.x
	var half_z := plane.size.y * 0.5 * walk_area.scale.z
	var center := walk_area.global_position
	global_position.x = clamp(global_position.x, center.x - half_x, center.x + half_x)
	global_position.z = clamp(global_position.z, center.z - half_z, center.z + half_z)


func _broadcast_position() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var cam: XRCamera3D = $XRCamera3D
	if not is_instance_valid(cam):
		return
	var body_floor := Vector3(cam.global_position.x, global_position.y, cam.global_position.z)
	NetworkManager.send_player_state(body_floor, cam.global_position, cam.global_rotation)
