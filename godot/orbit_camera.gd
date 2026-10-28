extends Camera3D
## Orbit-Kamera: Linke Maustaste = um den Mittelpunkt drehen, rechte Maustaste =
## verschieben (Panning), Mausrad = Zoom, Auto-Rotation optional.

@export var target := Vector3.ZERO
@export var distance: float = 4.0
@export var rotate_speed: float = 0.005
## Verschiebung je Pixel, skaliert mit dem Abstand (weiter weg = größere Schritte).
@export var pan_speed: float = 0.0015
@export var zoom_step: float = 0.9
@export var auto_rotate_speed: float = 0.0  # rad/s
## true: nur reagieren, solange diese Kamera die aktive ist (z. B. Server-Kamera
## in Situs, die auf Clients nicht aktiv ist).
@export var require_current: bool = false

var yaw: float = 0.6
var pitch: float = -0.4


func _ready() -> void:
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if require_current and not is_current():
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		yaw -= event.relative.x * rotate_speed
		pitch = clampf(pitch - event.relative.y * rotate_speed, -1.5, 1.5)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		var step := distance * pan_speed
		target -= global_transform.basis.x * event.relative.x * step
		target += global_transform.basis.y * event.relative.y * step
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.3, distance * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(50.0, distance / zoom_step)


func _process(delta: float) -> void:
	yaw += auto_rotate_speed * delta
	_update()


func _update() -> void:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	global_transform = Transform3D(b, target + b.z * distance)
