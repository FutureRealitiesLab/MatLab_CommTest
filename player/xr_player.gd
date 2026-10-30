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

## Sprung-Erkennung über die Kopfhöhe: Der Kopf steigt schnell und fällt gleich wieder.
## (Aufrichten aus der Hocke oder Verbeugen steigt nur und löst nichts aus.)
## Wird an die anderen gemeldet (Avatar fliegt, Geist bleibt).
## Ein/Aus und die zusätzliche Controller-Taste: Project Settings → Situs Core → Avatar.
## Mindest-Steiggeschwindigkeit des Kopfes in m/s (gemittelt über ca. 0.2 s)
@export var jump_speed: float = 1.0
## Mindest-Anstieg des Kopfes in Metern
@export var jump_min_rise: float = 0.1
## Pause nach einem Sprung in Sekunden
@export var jump_cooldown: float = 2.0
## Meldet Anstieg, Sprung und Taste im Log (adb logcat -s godot), zum Einstellen der Schwellen
@export var jump_debug: bool = true

var _send_timer: float = 0.0
var _jump_clock: float = 0.0
var _jump_hist: Array = []   # Vector2(Zeit, Höhe) der letzten 1 s
var _jump_rising: bool = false
var _jump_rise_t: float = 0.0
var _jump_peak: float = 0.0
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
	# Zusätzlicher Sprung-Auslöser: Controller-Taste (Standard B/Y), einstellbar in den Project Settings
	if SitusSettings.get_jump_enabled() and button_name == SitusSettings.get_jump_button() \
			and _jump_cool <= 0.0 and NetworkManager.client_connected_flag:
		_jump_cool = jump_cooldown
		_jump_log("Taste " + button_name, 0.0, 0.0)
		NetworkManager.send_jump()
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


## Sprung am Kopf erkennen: schneller Anstieg, dann innerhalb von 0.7 s wieder Abstieg.
## Ausgewertet wird nur die Höhenänderung der Kopfpose (egal, ob der Tracking-Raum am
## Boden oder am Kopf beginnt), pro gerendertem Bild.
func _detect_jump(delta: float) -> void:
	if delta <= 0.0 or not SitusSettings.get_jump_enabled():
		return
	var cam := $XRCamera3D as XRCamera3D
	if cam.position.length() < 0.01:
		return  # noch kein Tracking
	_jump_clock += delta
	_jump_cool = maxf(0.0, _jump_cool - delta)
	var h: float = cam.position.y
	_jump_hist.append(Vector2(_jump_clock, h))
	while _jump_hist.size() > 1 and _jump_clock - _jump_hist[0].x > 1.0:
		_jump_hist.pop_front()
	var vy := 0.0
	var rise := 0.0
	for e: Vector2 in _jump_hist:
		if _jump_clock - e.x <= 0.22:
			vy = (h - e.y) / maxf(_jump_clock - e.x, 0.05)
			rise = h - e.y
			break

	if not _jump_rising:
		if vy > jump_speed and rise > jump_min_rise and _jump_cool <= 0.0:
			_jump_rising = true
			_jump_rise_t = 0.0
			_jump_peak = h
			_jump_log("Anstieg", h, vy)
		return

	_jump_rise_t += delta
	_jump_peak = maxf(_jump_peak, h)
	if vy < -0.4 and _jump_peak - h > 0.04:
		_jump_rising = false
		_jump_cool = jump_cooldown
		_jump_log("SPRUNG", h, vy)
		NetworkManager.send_jump()
	elif _jump_rise_t > 0.7:
		_jump_rising = false  # nur aufgerichtet, kein Sprung
		_jump_log("kein Abstieg, verworfen", h, vy)


func _jump_log(what: String, h: float, vy: float) -> void:
	if jump_debug:
		print("[Sprung] %s: Höhe %.2f, v %.2f m/s" % [what, h, vy])


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
