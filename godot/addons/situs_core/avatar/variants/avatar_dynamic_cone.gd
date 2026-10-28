# TEMPLATE CORE – nicht verändern
extends CharacterBody3D

## avatar_dynamic_cone.gd – Standard-Avatar für die Ausstellung.
##
## Stellt einen Spieler als gestapelte Ringe dar, die weich hinter der
## Kopfbewegung nachziehen — ähnlich einer Kette.
## Anzahl, Größe und Nachzieh-Verhalten sind im Inspektor einstellbar.
## Für eine eigene Variante: avatar_dynamic_cone.tscn duplizieren
## und die Inspektor-Werte überschreiben (kein Code nötig).

## Anzahl der Ringe zwischen Boden und Kopf
@export var num_rings: int = 8

## Durchmesser des untersten Rings (Meter)
@export var base_diameter: float = 1.2

## Durchmesser des obersten Rings – direkt unter dem Kopf (Meter)
@export var top_diameter: float = 0.18

## Durchmesser der Kopfkugel (Meter)
@export var head_diameter: float = 0.25

## Dicke des Donut-Schlauchs (Meter) – wie "fett" jeder Ring ist
@export var tube_diameter: float = 0.049

## Segmente um den Schlauch-Querschnitt (Detailgrad des Röhrchens)
@export var tube_segments: int = 12

## Y-Abstand des untersten Rings vom Boden (Meter)
@export var base_y_offset: float = 0.05

## Abstand zwischen oberstem Ring und Kopfkugel (Meter)
@export var top_ring_gap: float = 0.05

## Responsivität des untersten Rings (1/Sekunde). Halbwertszeit ≈ ln(2)/Wert.
## 3.0 → ~0.23 s bis halbe Lücke geschlossen; sinnvoller Bereich 1.0 – 8.0.
@export var damping_bottom: float = 3.0

## Responsivität des obersten Rings (1/Sekunde).
## 14.0 → ~0.05 s; sinnvoller Bereich 8.0 – 20.0.
@export var damping_top: float = 14.0

## Krümmung der Dämpfungs-Verteilung (1.0 = linear).
## > 1.0 macht untere Ringe träger, < 1.0 macht sie responsiver.
@export var damping_curve: float = 1.0

## Versatz des gesamten Avatars nach hinten (Rücken-Richtung), Meter.
## Folgt der Kopf-Yaw-Richtung. 0.0 = kein Versatz (zentriert auf Spieler).
## Wird für Remote-Avatare auf 0.0 gelassen; set_self_mode() aktiviert 0.1 für den eigenen Avatar.
@export var body_back_offset: float = 0.0


# ── Interface: wird von SceneManager gesetzt ─────────────────────
var peer_id: int = 0:
	set(value):
		peer_id = value
		_apply_color()  # wird ggf. vor _ready() aufgerufen → Guard in _apply_color
		# peer_id auch auf Head-Collider spiegeln (falls schon erstellt)
		if is_instance_valid(_head_collider):
			_head_collider.set_meta("peer_id", value)


# ── Interne Zustandsvariablen ────────────────────────────────────
var _rings:          Array = []   # MeshInstance3D pro Ring
var _ring_pos_cur:   Array = []   # aktuelle (gedämpfte) Weltposition
var _ring_pos_tgt:   Array = []   # Zielposition (vom Netzwerk)
var _head_sphere:    MeshInstance3D = null
var _head_collider:  StaticBody3D = null   # Kopf-Collider, Layer 4, Gruppe "avatar_heads"
var _head_cur:       Vector3 = Vector3.ZERO
var _head_tgt:       Vector3 = Vector3.ZERO
var _ready_done:     bool = false
var _first_update:   bool = true  # beim ersten Netzwerk-Update sofort einrasten


func _ready() -> void:
	add_to_group("remote_avatars")
	collision_layer = 4   # Layer 3: "avatars"
	collision_mask  = 0   # kein Physik-Kontakt

	_build_rings()
	_ready_done = true  # muss VOR _apply_color() stehen, sonst greift der Guard
	_apply_color()


# ── Aufbau ───────────────────────────────────────────────────────

func _build_rings() -> void:
	var tube_radius: float = tube_diameter / 2.0
	for i in range(num_rings):
		var t            = float(i) / float(max(num_rings - 1, 1))
		var ring_radius  = lerp(base_diameter, top_diameter, t) / 2.0

		var inst  := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius   = max(0.001, ring_radius - tube_radius)
		torus.outer_radius   = ring_radius + tube_radius
		torus.rings          = 24
		torus.ring_segments  = tube_segments
		inst.mesh = torus
		add_child(inst)

		_rings.append(inst)
		_ring_pos_cur.append(Vector3.ZERO)
		_ring_pos_tgt.append(Vector3.ZERO)

	# Kopfkugel
	_head_sphere = MeshInstance3D.new()
	var sph        := SphereMesh.new()
	sph.radius      = head_diameter / 2.0
	sph.height      = head_diameter
	sph.radial_segments = 24
	_head_sphere.mesh = sph
	add_child(_head_sphere)

	# Kopf-Collider: StaticBody3D auf Layer 4, Gruppe "avatar_heads"
	# Folgt _head_cur in _process() → Area3D-Trigger können gezielt auf den Kopf reagieren.
	# Zugriff auf Spieler-ID: body.get_meta("peer_id") oder body.get_parent().peer_id
	_head_collider = StaticBody3D.new()
	_head_collider.collision_layer = 4
	_head_collider.collision_mask  = 0
	_head_collider.add_to_group("avatar_heads")
	var _hcol_shape  := CollisionShape3D.new()
	var _hcol_sphere := SphereShape3D.new()
	_hcol_sphere.radius = head_diameter / 2.0
	_hcol_shape.shape   = _hcol_sphere
	_head_collider.add_child(_hcol_shape)
	add_child(_head_collider)


# ── Netzwerk-Update (vom NetworkManager aufgerufen, ~20 Hz) ──────

func update_transform(body_pos: Vector3, head_pos: Vector3, head_rot: Vector3) -> void:
	# Horizontal-Rückwärtsvektor aus Kopf-Yaw (kein Pitch/Roll)
	var back_dir    := Vector3(sin(head_rot.y), 0.0, cos(head_rot.y))
	var back_offset := back_dir * body_back_offset

	var base        = body_pos + Vector3(0.0, base_y_offset, 0.0) + back_offset
	# Ringe enden top_ring_gap unterhalb der Kopfkugel.
	var ring_top    = head_pos - Vector3(0.0, top_ring_gap, 0.0) + back_offset
	for i in range(_rings.size()):
		var t = float(i) / float(max(_rings.size() - 1, 1))
		_ring_pos_tgt[i] = base.lerp(ring_top, t)

	_head_tgt = head_pos + back_offset

	# Beim allerersten Update: Positionen sofort einrasten (kein Slide von 0,0,0)
	if _first_update:
		_first_update = false
		for i in range(_rings.size()):
			_ring_pos_cur[i] = _ring_pos_tgt[i]
		_head_cur = head_pos + back_offset


# ── Smooth-Update pro Frame (delta-basiert, framerate-unabhängig) ─

func _process(delta: float) -> void:
	# Warten bis zum ersten update_transform()-Aufruf, damit die Ringe nicht kurz
	# auf Vector3.ZERO (Szenenursprung) erscheinen, bevor die echte Position ankommt.
	if _rings.is_empty() or _first_update:
		return

	# Dämpfung: linearer Gradient (mit Kurve) von bottom zu top.
	for i in range(_rings.size()):
		var t              = float(i) / float(max(_rings.size() - 1, 1))
		var responsiveness = lerp(damping_bottom, damping_top, pow(t, damping_curve))
		var smooth         = 1.0 - exp(-responsiveness * delta)
		
		_ring_pos_cur[i] = _ring_pos_cur[i].lerp(_ring_pos_tgt[i], smooth)
		_rings[i].global_position = _ring_pos_cur[i]

	if is_instance_valid(_head_sphere):
		# Kopf ist etwas responsiver als der oberste Ring (Faktor 1.5),
		# um den "Lead" zu behalten, aber fließend zum Rest.
		var head_resp = damping_top * 1.5
		_head_cur = _head_cur.lerp(_head_tgt, 1.0 - exp(-head_resp * delta))
		_head_sphere.global_position = _head_cur
		if is_instance_valid(_head_collider):
			_head_collider.global_position = _head_cur


# ── Selbst-Ansicht (eigener Körper in First-Person) ─────────────

## Schaltet den Avatar in den Selbst-Modus:
##   • Kopfkugel wird ausgeblendet (würde FPS-Kamera verdecken)
##   • collision_layer = 0  (löst keine Area3D-Trigger aus)
## Wird von SceneManager nach add_child() aufgerufen.
func set_self_mode(enabled: bool) -> void:
	if not enabled:
		return
	body_back_offset = 0.1  # Ringe 10 cm hinter Brille → Hals-Position
	collision_layer = 0
	if is_instance_valid(_head_sphere):
		_head_sphere.visible = false
	if is_instance_valid(_head_collider):
		_head_collider.collision_layer = 0


# ── Farbe (Spielerfarbe aus GameState oder Szenen-Override) ─────

## Szenen-spezifischer Farb-Override. Gesetzt von SceneManager wenn
## "player_color" in scene_registry eingetragen ist.
## Color(0,0,0,0) = kein Override → individuelle GameState-Farbe.
var _force_color: Color = Color(0, 0, 0, 0)

func set_force_color(c: Color) -> void:
	_force_color = c
	_apply_color()


func _apply_color() -> void:
	if peer_id == 0 or not _ready_done:
		return

	var color: Color = _force_color if _force_color.a > 0.01 else GameState.get_color_for_id(peer_id)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.7
	for ring in _rings:
		if is_instance_valid(ring):
			ring.set_surface_override_material(0, mat)

	if is_instance_valid(_head_sphere):
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = color.lightened(0.3)
		hmat.roughness    = 0.3
		hmat.metallic     = 0.4
		_head_sphere.set_surface_override_material(0, hmat)
