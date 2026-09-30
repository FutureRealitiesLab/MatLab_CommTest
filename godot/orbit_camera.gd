extends Camera3D
## Orbit-Kamera: Linke Maustaste = drehen, Mausrad = Zoom, Auto-Rotation optional.

@export var target := Vector3.ZERO
@export var distance: float = 4.0
@export var rotate_speed: float = 0.005
@export var zoom_step: float = 0.9
@export var auto_rotate_speed: float = 0.0  # rad/s

var yaw: float = 0.6
var pitch: float = -0.4


func _ready() -> void:
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		yaw -= event.relative.x * rotate_speed
		pitch = clampf(pitch - event.relative.y * rotate_speed, -1.5, 1.5)
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
