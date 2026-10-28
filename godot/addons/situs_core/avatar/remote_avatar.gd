# TEMPLATE CORE – nicht verändern
extends CharacterBody3D

## remote_avatar.gd – Darstellung einer anderen Person im VR-Raum.
##
## Jede verbundene VR-Brille oder Desktop-Instanz erscheint bei anderen
## Spielern als farbiger Körper (Capsule) mit Kopf (Kugel), die der
## echten Kopfbewegung folgen.
## Wird von SceneManager automatisch gespawnt — nicht manuell einbauen.
##
## Basis-Implementierung; für eigene Avatar-Varianten avatar_dynamic_cone
## als Vorlage verwenden.


## Peer-ID dieses Avatars (wird von SceneManager gesetzt)
var peer_id: int = 0:
	set(value):
		peer_id = value
		_apply_player_color()

## get_node_or_null macht das Script tolerant gegenüber Varianten
## die keine Body- oder Head-Node haben (z. B. Single-Mesh-Avatare)
@onready var body_mesh: MeshInstance3D = get_node_or_null("Body")
@onready var head_mesh: MeshInstance3D = get_node_or_null("Head")


func _ready() -> void:
	add_to_group("remote_avatars")
	# Layer 3 (Bit 2 = Wert 4): "avatars" – damit Area3D-Trigger greifen
	# Mask 0: kein Physik-Kontakt mit Spielern oder Welt (Position kommt vom Netzwerk)
	collision_layer = 4
	collision_mask  = 0
	_apply_player_color()


## Aktualisiert Körper- und Kopfposition (wird vom NetworkManager aufgerufen).
## body_pos  → XROrigin3D / CharacterBody3D world position des Senders
## head_pos  → XRCamera3D / Head world position des Senders
## head_rot  → XRCamera3D / Head world rotation (Euler) des Senders
func update_transform(body_pos: Vector3, head_pos: Vector3, head_rot: Vector3) -> void:
	# Körper-Root interpoliert zur body_pos
	global_position = global_position.lerp(body_pos, 0.25)
	# Kopf separat positionieren und rotieren
	if is_instance_valid(head_mesh):
		head_mesh.global_position = head_mesh.global_position.lerp(head_pos, 0.25)
		head_mesh.global_rotation = head_rot


# ── Interne Hilfsfunktionen ──────────────────────────────────────

## Szenen-spezifischer Farb-Override (gesetzt von SceneManager).
## Color(0,0,0,0) = kein Override → individuelle GameState-Farbe.
var _force_color: Color = Color(0, 0, 0, 0)

func set_force_color(c: Color) -> void:
	_force_color = c
	_apply_player_color()


func _apply_player_color() -> void:
	if peer_id == 0:
		return
	var color: Color = _force_color if _force_color.a > 0.01 else GameState.get_color_for_id(peer_id)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if is_instance_valid(body_mesh):
		body_mesh.set_surface_override_material(0, mat)
	if is_instance_valid(head_mesh):
		# Kopf leicht dunkler für bessere Lesbarkeit
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = color.darkened(0.25)
		head_mat.roughness = 0.6
		head_mesh.set_surface_override_material(0, head_mat)
