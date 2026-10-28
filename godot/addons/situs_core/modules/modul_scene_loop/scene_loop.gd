extends Node

## scene_loop.gd – Autoload "SceneLoop" des Moduls modul_scene_loop.
##
## Spielt mehrere Szenen nacheinander ab (Ausstellungs-Loop):
##   • liest die Szenen-Reihenfolge aus einer Registry-Datei (nur Ordnerpfade)
##   • liest Name, Dauer, Avatar, … aus scene_info.cfg im jeweiligen Szenen-Ordner
##   • Server: Timer, Auto-Wechsel, N = nächste Szene, L = Auto-Wechsel an/aus
##   • Standalone-Modus (ohne Server): Controller-Tasten wechseln lokal
##
## Anbindung an den Core: setzt sich als SceneManager.scene_provider und löst
## Wechsel über SceneManager.request_scene(index) aus. Ohne dieses Modul läuft
## der Core mit genau einer Szene.
##
## Registry-Pfad: Project Setting "situs_core/scene_loop/registry_path"
##   (Default res://_scenes/scene_registry.gd, Vorlage: templates/scene_registry.example.gd)

const DEFAULT_REGISTRY_PATH := "res://_scenes/scene_registry.gd"

signal timer_tick(remaining: float, total: float)
signal auto_advance_toggled(enabled: bool)

## Automatischer Szenenwechsel auf dem Server (an/aus via L-Taste oder Button)
var auto_advance: bool = true

## Laufzeit-Timer der aktuellen Szene (Sekunden)
var _timer: float = 0.0


func _ready() -> void:
	# Autoload-Reihenfolge: SceneLoop steht nach SceneManager, damit dieser existiert.
	SceneManager.scene_provider = self
	SceneManager.scene_changed.connect(_on_scene_changed)
	SceneManager.scene_step_requested.connect(_on_step_requested)


# ══════════════════════════════════════════════════════════════════
#  Szenen-Liste  (wird vom SceneManager in initialize() abgefragt)
# ══════════════════════════════════════════════════════════════════

func get_scene_list() -> Array:
	var path: String = ProjectSettings.get_setting("situs_core/scene_loop/registry_path", DEFAULT_REGISTRY_PATH)
	var registry_script := load(path) as GDScript
	if registry_script == null:
		push_error("[SceneLoop] Registry nicht gefunden: %s" % path)
		return []
	var folder_list: Array = registry_script.new().get_scenes()
	var list: Array = []
	for folder_path in folder_list:
		var d := _load_scene_info(folder_path)
		if not d.is_empty():
			list.append(d)
		else:
			push_warning("[SceneLoop] Überspringe '%s' (scene_info.cfg fehlt oder ungültig)" % folder_path)
	print("[SceneLoop] %d Szene(n) registriert." % list.size())
	return list


## Lädt scene_info.cfg aus einem Szenen-Ordner und gibt das Scene-Dict zurück.
## Gibt leeres Dict zurück wenn die Datei fehlt oder scene_file nicht gesetzt ist.
func _load_scene_info(folder_path: String) -> Dictionary:
	var cfg_path := folder_path + "scene_info.cfg"
	var cf       := ConfigFile.new()
	if cf.load(cfg_path) != OK:
		push_error("[SceneLoop] scene_info.cfg nicht gefunden: " + cfg_path)
		return {}
	var scene_file: String = cf.get_value("scene", "scene_file", "")
	if scene_file.is_empty():
		push_error("[SceneLoop] 'scene_file' fehlt in: " + cfg_path)
		return {}
	var d := {
		"path":     folder_path + scene_file,
		"name":     cf.get_value("scene", "name",     "Unbenannt"),
		"duration": cf.get_value("scene", "duration", -1.0),
		"avatar":   cf.get_value("scene", "avatar",   SceneManager.DEFAULT_AVATAR_PATH),
		"team":     cf.get_value("scene", "team",     ""),
		"info":     cf.get_value("scene", "info",     ""),
	}
	if cf.has_section_key("scene", "player_color"):
		d["player_color"] = cf.get_value("scene", "player_color")
	return d


# ══════════════════════════════════════════════════════════════════
#  Timer  (läuft nur auf dem Server bzw. im Standalone-Modus)
# ══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _is_authority():
		return

	var scenes: Array = SceneManager.scenes_list
	var index: int = SceneManager.current_index
	if index < 0 or index >= scenes.size():
		return

	var duration: float = float(scenes[index].get("duration", -1.0))
	if duration <= 0.0:
		return  # Kein Auto-Advance für diese Szene

	if not auto_advance:
		return  # Auto-Advance pausiert (Loop deaktiviert via L-Taste)

	_timer += delta
	timer_tick.emit(duration - _timer, duration)

	if _timer >= duration:
		advance_scene()


## Server oder Standalone → darf Szenen wechseln.
func _is_authority() -> bool:
	if SceneManager.standalone_mode:
		return true
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


# ══════════════════════════════════════════════════════════════════
#  Szenenwechsel
# ══════════════════════════════════════════════════════════════════

## Lädt die nächste Szene – Server per N-Taste/Button/Timer, oder lokal im Standalone-Modus.
func advance_scene() -> void:
	_step(1)


## Lädt die vorherige Szene.
func retreat_scene() -> void:
	_step(-1)


func _step(direction: int) -> void:
	if not _is_authority():
		return
	var count: int = SceneManager.scenes_list.size()
	if count == 0:
		return
	_timer = 0.0
	var target: int = posmod(SceneManager.current_index + direction, count)
	print("[SceneLoop] Szenenwechsel %s Index %d" % ["→" if direction > 0 else "←", target])
	SceneManager.request_scene(target)


## Schaltet den automatischen Szenenwechsel um (Taste L oder Button).
func toggle_auto_advance() -> void:
	auto_advance = not auto_advance
	auto_advance_toggled.emit(auto_advance)
	print("[SceneLoop] Auto-Szenenwechsel: %s" % ("AN" if auto_advance else "AUS"))


## Text für das Server-HUD (TimerLabel).
func get_hud_timer_text() -> String:
	var scenes: Array = SceneManager.scenes_list
	var index: int = SceneManager.current_index
	if index < 0 or index >= scenes.size():
		return "Timer: –"
	var duration: float = float(scenes[index].get("duration", -1.0))
	if duration <= 0.0:
		return "Kein Auto-Advance (N = manuell)"
	if not auto_advance:
		return "Auto-Wechsel: AUS [L] (N = manuell)"
	return "Wechsel in: %ds" % int(max(0.0, duration - _timer))


# ── Callbacks ────────────────────────────────────────────────────

func _on_scene_changed(_index: int, _scene_name: String) -> void:
	_timer = 0.0


func _on_step_requested(direction: int) -> void:
	_step(direction)


func _unhandled_input(event: InputEvent) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if event.is_action_pressed("scene_next") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N):
		print("[SceneLoop] Manueller Szenenwechsel via Taste N.")
		advance_scene()
	elif event.is_action_pressed("scene_loop_toggle") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L):
		toggle_auto_advance()
