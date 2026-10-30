# TEMPLATE CORE – nicht verändern
extends CharacterBody3D

## avatar_dynamic_cone.gd – Standard-Avatar für die Ausstellung.
##
## Stellt einen Spieler als gestapelte Ringe dar, die hinter der Kopfbewegung
## nachziehen. Oben sitzt ein Kopf (Kugel) mit Brille (Würfel), Controller sind
## kleine Quader. Optional gibt es einen Sprung-Effekt (Hocke, dann Hochspringen).
## Anzahl, Größe, Nachzieh-Verhalten und Darstellung sind im Inspektor einstellbar.
## Für eine eigene Variante: avatar_dynamic_cone.tscn duplizieren
## und die Inspektor-Werte überschreiben (kein Code nötig).
##
## Die Schleppe und der Sprung orientieren sich am Avatar aus dem Projekt
## Spatial Encounters (siehe docs/THIRD_PARTY.md).

const SitusSettings := preload("res://addons/situs_core/core/situs_settings.gd")

## Wie die Ringe nachziehen:
## LINEAR = ein träger Bodenpunkt folgt dem Kopf, die Ringe liegen gleichmäßig auf
##          der Linie vom Bodenpunkt zum Kopf (Schweif nach hinten, wie im Original).
## DAMPED = jeder Ring hat eine eigene Dämpfung (älteres Verhalten, bleibt vorerst
##          zum Vergleich erhalten).
enum TrailMode { LINEAR, DAMPED }

@export var trail_mode: TrailMode = TrailMode.LINEAR

## Responsivität des Bodenpunkts im Modus LINEAR (1/Sekunde, zeitbasiert).
## Je kleiner, desto länger die Schleppe: 1.0 = lang (Standard), 3.0 = kurz.
## Sinnvoller Bereich 0.5 – 6.0.
@export var lazy_follow_rate: float = 1.0

## Anzahl der Ringe zwischen Boden und Kopf
@export var num_rings: int = 8

## Durchmesser des untersten Rings (Meter)
@export var base_diameter: float = 1.2

## Durchmesser des obersten Rings – direkt unter dem Kopf (Meter)
@export var top_diameter: float = 0.18

## Durchmesser der Kopfkugel (Meter). Die Kugel steht abstrahiert für den Kopf.
@export var head_diameter: float = 0.25

## Kantenlänge des Würfels, der die Brille (HMD) abstrahiert (Meter).
@export var hmd_size: float = 0.14

## Wie weit der Brillen-Würfel vor der Kopfmitte sitzt (Meter, entlang der Blickrichtung).
## Er ragt damit vorn aus der Kugel und zeigt die Blickrichtung.
@export var hmd_offset: float = 0.08

## Controller als Quader: Länge (Z) und Breite/Höhe (Meter)
@export var hand_length: float = 0.15
@export var hand_width: float = 0.04

## Flacher Stil: dünne, unbeleuchtete Bänder statt beleuchteter Donuts (wie im
## Original). Aus = Donut-Ringe mit Beleuchtung.
@export var flat_rings: bool = true

## Höhe der Bänder im flachen Stil (Meter)
@export var band_height: float = 0.06

## Dicke des Donut-Schlauchs (Meter), nur wenn flat_rings aus ist
@export var tube_diameter: float = 0.049

## Segmente um den Schlauch-Querschnitt (Detailgrad des Röhrchens), nur Donut-Stil
@export var tube_segments: int = 12

## Farbverlauf: unten dunkler, oben die volle Spielerfarbe.
@export var color_gradient: bool = true

## Wie stark der unterste Ring abgedunkelt wird (0 = gar nicht, 1 = schwarz)
@export_range(0.0, 1.0, 0.05) var gradient_darken: float = 0.6

## Y-Abstand des untersten Rings vom Boden (Meter)
@export var base_y_offset: float = 0.05

## Abstand zwischen oberstem Ring und Kopfkugel (Meter)
@export var top_ring_gap: float = 0.05

## Nur Modus DAMPED: Responsivität des untersten Rings (1/Sekunde).
## 3.0 → ~0.23 s bis halbe Lücke geschlossen; sinnvoller Bereich 1.0 – 8.0.
@export var damping_bottom: float = 3.0

## Responsivität des obersten Rings (1/Sekunde), im Modus LINEAR für den Kopf.
## 14.0 → ~0.05 s; sinnvoller Bereich 8.0 – 20.0.
@export var damping_top: float = 14.0

## Nur Modus DAMPED: Krümmung der Dämpfungs-Verteilung (1.0 = linear).
## > 1.0 macht untere Ringe träger, < 1.0 macht sie responsiver.
@export var damping_curve: float = 1.0

## Versatz des gesamten Avatars nach hinten (Rücken-Richtung), Meter.
## Folgt der Kopf-Yaw-Richtung. 0.0 = kein Versatz (zentriert auf Spieler).
## Wird für Remote-Avatare auf 0.0 gelassen; set_self_mode() aktiviert 0.1 für den eigenen Avatar.
@export var body_back_offset: float = 0.0

@export_group("Sprung")

## Sprung-Effekt erlaubt (zusätzlich zur Project Setting Situs Core → Avatar → Jump Enabled).
## Während des Sprungs fliegt der Avatar nach oben und wächst, an der echten Position
## des Spielers bleibt ein durchsichtiger Geist stehen.
@export var jump_enabled: bool = true

## Höhe, auf die der Avatar fliegt (Meter)
@export var jump_lift: float = 2.5

## Zusätzliche Vergrößerung der Ringe auf dem Höhepunkt (1.0 = doppelt so groß)
@export var jump_scale_gain: float = 1.0

## Dauer des Aufstiegs und des Absinkens (Sekunden)
@export var jump_up_time: float = 2.0
@export var jump_down_time: float = 6.0

## Deckkraft des Geistes an der echten Position (0 = unsichtbar, 1 = voll)
@export_range(0.0, 1.0, 0.05) var ghost_alpha: float = 0.25

## Wird nur für den Geist gesetzt (siehe _spawn_ghost): durchsichtiger Zwilling an der
## echten Position, ohne Kollision und ohne eigenen Sprung.
var ghost_mode: bool = false


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
var _ring_pos_cur:   Array = []   # DAMPED: aktuelle (gedämpfte) Weltposition
var _ring_pos_tgt:   Array = []   # DAMPED: Zielposition (vom Netzwerk)
var _lazy_cur:       Vector3 = Vector3.ZERO   # LINEAR: träger Bodenpunkt
var _lazy_tgt:       Vector3 = Vector3.ZERO
var _head_mesh:      MeshInstance3D = null   # Kopfkugel, folgt Position und Rotation des Kopfes
var _hmd_mesh:       MeshInstance3D = null   # Brillen-Würfel, Kind der Kugel (Vorderseite = -Z)
var _head_collider:  StaticBody3D = null   # Kopf-Collider, Layer 4, Gruppe "avatar_heads"
var _head_cur:       Vector3 = Vector3.ZERO
var _head_tgt:       Vector3 = Vector3.ZERO
var _head_basis_cur: Basis = Basis.IDENTITY
var _head_basis_tgt: Basis = Basis.IDENTITY
var _hands:          Array = []   # 2 MeshInstance3D: links, rechts (nur sichtbar, wenn getrackt)
var _hand_pos_tgt:   Array = [Vector3.ZERO, Vector3.ZERO]
var _hand_basis_tgt: Array = [Basis.IDENTITY, Basis.IDENTITY]
var _hand_snap:      Array = [true, true]  # beim ersten Tracking sofort einrasten
var _self_mode:      bool = false
var _ready_done:     bool = false
var _first_update:   bool = true  # beim ersten Netzwerk-Update sofort einrasten

# Letzter Netzwerkzustand (für den Geist beim Sprungbeginn)
var _last_body: Vector3 = Vector3.ZERO
var _last_head: Vector3 = Vector3.ZERO
var _last_rot:  Vector3 = Vector3.ZERO

# Sprung: 0 = kein Sprung, 1 = Aufstieg, 2 = Absinken
var _jump_phase: int = 0
var _jump_time: float = 0.0
var _jump_amount: float = 0.0   # 0..1
var _ghost: Node = null


func _ready() -> void:
	if not ghost_mode:
		add_to_group("remote_avatars")
	collision_layer = 0 if ghost_mode else 4   # Layer 3: "avatars"
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

		var inst := MeshInstance3D.new()
		if flat_rings:
			# Offenes Band: Zylinder ohne Deckel
			var band := CylinderMesh.new()
			band.top_radius      = ring_radius
			band.bottom_radius   = ring_radius
			band.height          = band_height
			band.radial_segments = 48
			band.rings           = 1
			band.cap_top         = false
			band.cap_bottom      = false
			inst.mesh = band
		else:
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

	# Kopfkugel mit Brillen-Würfel davor (-Z, wie die Blickrichtung der Kamera)
	_head_mesh = MeshInstance3D.new()
	var sph        := SphereMesh.new()
	sph.radius      = head_diameter / 2.0
	sph.height      = head_diameter
	sph.radial_segments = 24
	_head_mesh.mesh = sph
	add_child(_head_mesh)

	_hmd_mesh = MeshInstance3D.new()
	var box        := BoxMesh.new()
	box.size        = Vector3.ONE * hmd_size
	_hmd_mesh.mesh  = box
	_hmd_mesh.position = Vector3(0.0, 0.0, -hmd_offset)
	_head_mesh.add_child(_hmd_mesh)

	# Controller: zwei schmale Quader, Länge entlang Z
	for i in 2:
		var hand := MeshInstance3D.new()
		var hbox := BoxMesh.new()
		hbox.size = Vector3(hand_width, hand_width, hand_length)
		hand.mesh = hbox
		hand.visible = false
		add_child(hand)
		_hands.append(hand)

	if ghost_mode:
		return  # der Geist braucht keinen Collider

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
	_last_body = body_pos
	_last_head = head_pos
	_last_rot = head_rot

	# Horizontal-Rückwärtsvektor aus Kopf-Yaw (kein Pitch/Roll)
	var back_dir    := Vector3(sin(head_rot.y), 0.0, cos(head_rot.y))
	var back_offset := back_dir * body_back_offset

	var base        = body_pos + Vector3(0.0, base_y_offset, 0.0) + back_offset
	# Ringe enden top_ring_gap unterhalb der Kopfkugel.
	var ring_top    = head_pos - Vector3(0.0, top_ring_gap, 0.0) + back_offset
	_lazy_tgt = base
	for i in range(_rings.size()):
		var t = float(i) / float(max(_rings.size() - 1, 1))
		_ring_pos_tgt[i] = base.lerp(ring_top, t)

	_head_tgt = head_pos + back_offset
	_head_basis_tgt = Basis.from_euler(head_rot)

	# Beim allerersten Update: Positionen sofort einrasten (kein Slide von 0,0,0)
	if _first_update:
		_first_update = false
		_lazy_cur = _lazy_tgt
		for i in range(_rings.size()):
			_ring_pos_cur[i] = _ring_pos_tgt[i]
		_head_cur = head_pos + back_offset
		_head_basis_cur = _head_basis_tgt

	if is_instance_valid(_ghost):
		_ghost.call("update_transform", body_pos, head_pos, head_rot)


## Controller-Posen (vom NetworkManager, ~20 Hz). hands = [links_pos, links_rot,
## rechts_pos, rechts_rot] in Weltkoordinaten, mask: Bit 0 links, Bit 1 rechts getrackt.
func update_hands(hands: PackedVector3Array, mask: int) -> void:
	if is_instance_valid(_ghost):
		_ghost.call("update_hands", hands, mask)
	if _self_mode or _hands.size() < 2 or hands.size() < 4:
		return
	for i in 2:
		var tracked: bool = (mask & (1 << i)) != 0
		_hands[i].visible = tracked
		if not tracked:
			_hand_snap[i] = true
			continue
		_hand_pos_tgt[i] = hands[i * 2]
		_hand_basis_tgt[i] = Basis.from_euler(hands[i * 2 + 1])
		if _hand_snap[i]:
			_hand_snap[i] = false
			_hands[i].global_position = _hand_pos_tgt[i]
			_hands[i].global_basis = _hand_basis_tgt[i]


# ── Smooth-Update pro Frame (delta-basiert, framerate-unabhängig) ─

func _process(delta: float) -> void:
	# Warten bis zum ersten update_transform()-Aufruf, damit die Ringe nicht kurz
	# auf Vector3.ZERO (Szenenursprung) erscheinen, bevor die echte Position ankommt.
	if _rings.is_empty() or _first_update:
		return

	_update_jump(delta)
	# Beim Sprung wird der ganze Avatar nach oben verschoben (alle Ziele), die Ringe wachsen.
	var lift := Vector3(0.0, _jump_amount * jump_lift, 0.0)
	var ring_scale := Vector3.ONE * (1.0 + jump_scale_gain * _jump_amount)

	# Kopf ist etwas responsiver als der oberste Ring (Faktor 1.5),
	# um den "Lead" zu behalten, aber fließend zum Rest.
	var head_smooth: float = 1.0 - exp(-damping_top * 1.5 * delta)
	_head_cur = _head_cur.lerp(_head_tgt + lift, head_smooth)
	_head_basis_cur = _head_basis_cur.slerp(_head_basis_tgt, head_smooth)
	_head_mesh.global_position = _head_cur
	_head_mesh.global_basis = _head_basis_cur
	if is_instance_valid(_head_collider):
		_head_collider.global_position = _head_cur

	if trail_mode == TrailMode.LINEAR:
		# Ein träger Bodenpunkt folgt dem Kopf. Die Ringe liegen gleichmäßig auf der
		# Linie vom Bodenpunkt (unten) zum Kopf (oben).
		_lazy_cur = _lazy_cur.lerp(_lazy_tgt + lift, 1.0 - exp(-lazy_follow_rate * delta))
		var ring_top := _head_cur - Vector3(0.0, top_ring_gap, 0.0)
		for i in range(_rings.size()):
			var t = float(i) / float(max(_rings.size() - 1, 1))
			_rings[i].global_position = _lazy_cur.lerp(ring_top, t)
			_rings[i].scale = ring_scale
	else:
		# Dämpfung: linearer Gradient (mit Kurve) von bottom zu top.
		for i in range(_rings.size()):
			var t              = float(i) / float(max(_rings.size() - 1, 1))
			var responsiveness = lerp(damping_bottom, damping_top, pow(t, damping_curve))
			var smooth         = 1.0 - exp(-responsiveness * delta)

			_ring_pos_cur[i] = _ring_pos_cur[i].lerp(_ring_pos_tgt[i] + lift, smooth)
			_rings[i].global_position = _ring_pos_cur[i]
			_rings[i].scale = ring_scale

	# Controller folgen mit derselben Glättung wie der Kopf
	for i in _hands.size():
		if _hands[i].visible:
			_hands[i].global_position = _hands[i].global_position.lerp(_hand_pos_tgt[i] + lift, head_smooth)
			_hands[i].global_basis = _hands[i].global_basis.slerp(_hand_basis_tgt[i], head_smooth)


# ── Sprung ───────────────────────────────────────────────────────

## Startet den Sprung-Effekt (vom NetworkManager gerufen, wenn der Spieler gesprungen ist).
## Der Avatar fliegt nach oben und wächst, ein durchsichtiger Geist bleibt an der echten
## Position. Ignoriert, wenn der Effekt abgeschaltet ist oder gerade läuft.
func trigger_jump() -> void:
	if ghost_mode or _self_mode or not jump_enabled or not SitusSettings.get_jump_enabled():
		return
	if _jump_phase != 0 or _first_update:
		return
	_jump_phase = 1
	_jump_time = 0.0
	_spawn_ghost()


func _update_jump(delta: float) -> void:
	if _jump_phase == 0:
		return
	_jump_time += delta
	if _jump_phase == 1:
		var x := clampf(_jump_time / maxf(jump_up_time, 0.01), 0.0, 1.0)
		_jump_amount = _ease_in_out_cubic(x)
		if x >= 1.0:
			_jump_phase = 2
			_jump_time = 0.0
	else:
		var x := clampf(_jump_time / maxf(jump_down_time, 0.01), 0.0, 1.0)
		_jump_amount = 1.0 - _ease_in_out_cubic(x)
		if x >= 1.0:
			_jump_phase = 0
			_jump_amount = 0.0
			_free_ghost()


static func _ease_in_out_cubic(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


## Durchsichtiger Zwilling an der echten Position des Spielers.
func _spawn_ghost() -> void:
	if scene_file_path.is_empty():
		return
	var packed := load(scene_file_path) as PackedScene
	if packed == null:
		return
	var g: Node = packed.instantiate()
	g.set("ghost_mode", true)
	g.set("jump_enabled", false)
	add_child(g)
	g.set("peer_id", peer_id)
	if _force_color.a > 0.01:
		g.call("set_force_color", _force_color)
	g.call("update_transform", _last_body, _last_head, _last_rot)
	_ghost = g


func _free_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


# ── Selbst-Ansicht (eigener Körper in First-Person) ─────────────

## Schaltet den Avatar in den Selbst-Modus:
##   • Kopfkugel samt Brillen-Würfel wird ausgeblendet (würde FPS-Kamera verdecken)
##   • collision_layer = 0  (löst keine Area3D-Trigger aus)
## Wird von SceneManager nach add_child() aufgerufen.
func set_self_mode(enabled: bool) -> void:
	if not enabled:
		return
	_self_mode = true
	for hand: MeshInstance3D in _hands:
		hand.visible = false  # eigene Controller sieht man ohnehin direkt
	body_back_offset = 0.1  # Ringe 10 cm hinter Brille → Hals-Position
	collision_layer = 0
	if is_instance_valid(_head_mesh):
		_head_mesh.visible = false
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

	# Ringe: eigenes Material je Ring wegen des Farbverlaufs (unten dunkler)
	for i in range(_rings.size()):
		if not is_instance_valid(_rings[i]):
			continue
		var t := float(i) / float(max(_rings.size() - 1, 1))
		var ring_color := color
		if color_gradient:
			ring_color = color.darkened(gradient_darken * (1.0 - t))
		_rings[i].set_surface_override_material(0, _make_material(ring_color, flat_rings, 0.7, 0.0))

	for hand: MeshInstance3D in _hands:
		hand.set_surface_override_material(0, _make_material(color, false, 0.5, 0.0))

	if is_instance_valid(_head_mesh):
		_head_mesh.set_surface_override_material(0, _make_material(color.lightened(0.3), false, 0.3, 0.4))
		_hmd_mesh.set_surface_override_material(0, _make_material(color.darkened(0.45), false, 0.4, 0.0))


## Material für alle Teile. unshaded = flache Darstellung ohne Beleuchtung (beidseitig sichtbar).
## Beim Geist wird alles durchsichtig.
func _make_material(color: Color, unshaded: bool, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = roughness
	mat.metallic     = metallic
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	if ghost_mode:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = ghost_alpha
	return mat
