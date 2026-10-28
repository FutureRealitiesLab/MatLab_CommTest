extends "res://addons/situs_core/templates/scene_hooks.gd"

## Simulationsszene für Situs Core: zeigt die MATLAB-Daten im Raum.
## Raumgröße kommt aus den Project Settings (situs_core/room), die Drehung des
## Raums gegenüber den Brillen übernimmt der XR-Ursprung (nicht dieser Inhalt).

const SitusSettings := preload("res://addons/situs_core/core/situs_settings.gd")


func _enter_tree() -> void:
	# Läuft vor _ready() der Kinder, damit scene_view.gd die Größe schon kennt.
	var room: Vector2 = SitusSettings.get_room_size()
	var view := $Plot/View
	view.box_size = Vector3(room.x, room.y, view.box_size.z)
	view.room_rotation_deg = 0.0


func _ready() -> void:
	super()
	SimulationRelay.attach()
	SimulationRelay.replay()
