@tool
extends RefCounted

## situs_settings.gd – Project Settings von Situs Core (Editor: Project Settings → Situs Core).
##
## Die Werte stehen in project.godot und sind damit auch in der exportierten APK.
## Gelesen wird immer mit Default, denn das Plugin läuft nur im Editor, nicht im Spiel.
## Unterschiedliche Werte für Editor und APK: im Editor bei der Einstellung
## "Override For…" → android wählen (Eintrag z. B. situs_core/network/server_ip.android).

const SERVER_IP      := "situs_core/network/server_ip"
const ROOM_WIDTH     := "situs_core/room/width_m"
const ROOM_LENGTH    := "situs_core/room/length_m"
const ROOM_ROTATION  := "situs_core/room/rotation_deg"

const DEFAULT_SERVER_IP     := "127.0.0.1"
const DEFAULT_ROOM_WIDTH    := 4.0
const DEFAULT_ROOM_LENGTH   := 8.0
const DEFAULT_ROOM_ROTATION := 0.0

## Wird vom Plugin beim Aktivieren registriert, damit die Felder im Editor erscheinen.
const DEFINITIONS := [
	{"name": SERVER_IP, "type": TYPE_STRING, "default": DEFAULT_SERVER_IP,
		"hint": PROPERTY_HINT_NONE, "hint_string": ""},
	{"name": ROOM_WIDTH, "type": TYPE_FLOAT, "default": DEFAULT_ROOM_WIDTH,
		"hint": PROPERTY_HINT_RANGE, "hint_string": "0.5,100,0.1,or_greater,suffix:m"},
	{"name": ROOM_LENGTH, "type": TYPE_FLOAT, "default": DEFAULT_ROOM_LENGTH,
		"hint": PROPERTY_HINT_RANGE, "hint_string": "0.5,100,0.1,or_greater,suffix:m"},
	{"name": ROOM_ROTATION, "type": TYPE_FLOAT, "default": DEFAULT_ROOM_ROTATION,
		"hint": PROPERTY_HINT_RANGE, "hint_string": "-180,180,0.5,suffix:°"},
]


## IP-Adresse des Servers (Clients verbinden sich hierhin).
static func get_server_ip() -> String:
	return str(ProjectSettings.get_setting(SERVER_IP, DEFAULT_SERVER_IP))


## Spielfläche in Metern: x = Breite (Weltachse x), y = Länge (Weltachse z).
static func get_room_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting(ROOM_WIDTH, DEFAULT_ROOM_WIDTH)),
		float(ProjectSettings.get_setting(ROOM_LENGTH, DEFAULT_ROOM_LENGTH)))


## Drehung des Tracking-Raums der Brillen gegenüber der Welt in Grad (um die Senkrechte).
## Wird auf den XR-Ursprung angewendet. Szenen bleiben unverändert.
static func get_room_rotation_deg() -> float:
	return float(ProjectSettings.get_setting(ROOM_ROTATION, DEFAULT_ROOM_ROTATION))


## Legt die Einstellungen mit Typ, Default und Wertebereich im Editor an.
static func register() -> void:
	for d: Dictionary in DEFINITIONS:
		var key: String = d["name"]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, d["default"])
		ProjectSettings.set_initial_value(key, d["default"])
		ProjectSettings.set_as_basic(key, true)
		ProjectSettings.add_property_info({
			"name": key,
			"type": d["type"],
			"hint": d["hint"],
			"hint_string": d["hint_string"],
		})
