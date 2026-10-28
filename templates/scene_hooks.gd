## scene_hooks.gd
## ════════════════════════════════════════════════════════════════
##  Einstiegspunkt für eigenen Code in Team-Szenen.
##
##  Dieses Script hängt an der Root-Node der Team-Szene.
##  Beim Laden ruft es automatisch die nötigen Systemfunktionen auf:
##    • FPS-Player spawnen wenn die Szene per F6 solo getestet wird
##    • ServerCamera positionieren im Ausstellungsbetrieb
##
##  Eigener Code kommt in die markierten Bereiche:
##    _ready()     → z. B. Sound starten, Animation anstoßen
##    _exit_tree() → z. B. Sound stoppen, Zustand zurücksetzen
## ════════════════════════════════════════════════════════════════

extends Node3D


func _ready() -> void:
	SceneManager.on_team_scene_ready(self)

	# ── Eigener Code beim Laden der Szene ──────────────────────
	# $Sounds/Ambience.play()


func _exit_tree() -> void:
	# ── Eigener Code beim Entladen der Szene ───────────────────
	# $Sounds/Ambience.stop()
	pass
