# TEMPLATE CORE – nicht verändern
extends Node3D

## cam_dolly.gd – Dreht einen Node gleichmäßig um seine Achsen.
##
## Hängt in main.tscn am CamDolly-Node, der die ServerCamera trägt.
## Dadurch rotiert die Kameraansicht des Servers langsam im Kreis —
## für eine lebendige Übersichtsdarstellung während der Ausstellung.
## Drehgeschwindigkeit (Grad/s) im Inspektor unter „Rotation Speed" einstellbar.

@export var rotation_speed: Vector3 = Vector3(0, 1, 0)

func _process(delta):
	rotate_x(deg_to_rad(rotation_speed.x) * delta)
	rotate_y(deg_to_rad(rotation_speed.y) * delta)
	rotate_z(deg_to_rad(rotation_speed.z) * delta)
