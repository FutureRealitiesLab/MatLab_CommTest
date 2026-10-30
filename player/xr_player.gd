# TEMPLATE CORE – nicht verändern
extends XROrigin3D

## xr_player.gd – Lokaler XR-Spieler (Focus Vision / Quest / OpenXR).
##
## Beide Controller gleichwertig:
##   Primary   (A / X)  → Standalone-Modus aktivieren
##   Secondary (B / Y)  → nächste Szene
##   Thumbstick Y       → Vor/Zurück-Bewegung (beide Controller, max-Betrag gewinnt)
##   Thumbstick X       → Links/Rechts-Rotation (beide Controller, max-Betrag gewinnt)


const SitusSettings := preload("res://addons/situs_core/core/situs_settings.gd")

## Sendeintervall in Sekunden (20 Hz)
const SEND_RATE: float = 0.05

## Bewegungsgeschwindigkeit (m/s) – im Godot-Editor einstellbar
@export var move_speed: float = 1.2

## Rotation via Thumbstick X aktivieren
@export var rotation_enabled: bool = true

## Drehgeschwindigkeit (Grad/s)
@export var rotation_speed: float = 60.0

## Sprung-Erkennung: Hocke (Kopf mindestens so viel unter der normalen Höhe), dann
## schnelles Aufrichten. Wird an die anderen gemeldet (Avatar fliegt, Geist bleibt).
## Ein/Aus über Project Settings → Situs Core → Avatar → Jump Enabled.
@export var jump_crouch_drop: float = 0.4
## Mindest-Steiggeschwindigkeit des Kopfes in m/s
@export var jump_speed: float = 1.3
## Pause nach einem Sprung in Sekunden
@export var jump_cooldown: float = 3.0
## Meldet Hocke, Sprung und Standhöhe im Log (adb logcat), zum Einstellen der Schwellen
@export var jump_debug: bool = true

var _send_timer: float = 0.0
var _jump_baseline: float = -1.0   # normale Kopfhöhe (langsam nachgeführt)
var _jump_clock: float = 0.0
var _jump_hist: Array = []   # Vector2(Zeit, Höhe) der letzten 0.3 s
var _jump_crouched: bool = false
var _jump_crouch_t: float = 0.0
var _jump_crouch_min: float = 0.0
var _jump_cool: float = 0.0
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


func _process(delta: float) -> void:
	_detect_jump(delta)  # pro gerendertem Bild: so oft wie die Kopfpose neu kommt


func _physics_process(delta: float) -> void:
	_send_timer += delta
	if _send_timer >= SEND_RATE:
		_send_timer = 0.0
		_broadcast_position()
	_do_locomotion(delta)


## Hocke, dann Hochspringen erkennen. Ausgewertet wird nur die Kopfhöhe relativ zur
## normalen Standhöhe, unabhängig davon, ob der Tracking-Raum am Boden oder am Kopf
## beginnt. Die Geschwindigkeit wird über ca. 0.2 s gemittelt (ein Tracking-Ausreißer
## löst nichts aus).
func _detect_jump(delta: float) -> void:
	if delta <= 0.0 or not SitusSettings.get_jump_enabled():
		return
	var cam := $XRCamera3D as XRCamera3D
	if cam.position.length() < 0.01:
		return  # noch kein Tracking
	_jump_clock += delta
	var h: float = cam.position.y
	_jump_hist.append(Vector2(_jump_clock, h))
	while _jump_hist.size() > 1 and _jump_clock - _jump_hist[0].x > 0.3:
		_jump_hist.pop_front()
	var vy := 0.0
	for e: Vector2 in _jump_hist:
		if _jump_clock - e.x <= 0.22:
			vy = (h - e.y) / maxf(_jump_clock - e.x, 0.05)
			break
	_jump_cool = maxf(0.0, _jump_cool - delta)

	if _jump_baseline < 0.0:
		if _jump_clock > 1.5:
			_jump_baseline = h
			_jump_log("Standhöhe gesetzt", h, vy)
		return

	if not _jump_crouched:
		if h < _jump_baseline - jump_crouch_drop:
			_jump_crouched = true
			_jump_crouch_t = 0.0
			_jump_crouch_min = h
			_jump_log("Hocke erkannt", h, vy)
		elif absf(vy) < 0.3:
			_jump_baseline = lerpf(_jump_baseline, h, 1.0 - exp(-delta / 3.0))
		return

	_jump_crouch_t += delta
	_jump_crouch_min = minf(_jump_crouch_min, h)
	if vy > jump_speed and h > _jump_crouch_min + 0.2 and _jump_cool <= 0.0:
		_jump_crouched = false
		_jump_cool = jump_cooldown
		_jump_log("SPRUNG", h, vy)
		NetworkManager.send_jump()
	elif h > _jump_baseline - 0.15 or _jump_crouch_t > 2.5:
		_jump_crouched = false  # wieder aufgestanden oder zu lange unten
		_jump_log("Hocke beendet", h, vy)


func _jump_log(what: String, h: float, vy: float) -> void:
	if jump_debug:
		print("[Sprung] %s: Höhe %.2f, Standhöhe %.2f, v %.2f m/s" % [what, h, _jump_baseline, vy])


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
	var hands := PackedVector3Array()
	var mask := 0
	for i in 2:
		var ctrl := get_node_or_null("LeftHand" if i == 0 else "RightHand") as XRController3D
		var tracked: bool = ctrl != null and ctrl.get_is_active() and ctrl.get_has_tracking_data()
		if tracked:
			mask |= 1 << i
			hands.append(ctrl.global_position)
			hands.append(ctrl.global_rotation)
		else:
			hands.append(Vector3.ZERO)
			hands.append(Vector3.ZERO)
	NetworkManager.send_player_state(body_floor, cam.global_position, cam.global_rotation, hands, mask)
