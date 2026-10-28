## scene_registry.gd  (Vorlage – ins Projekt kopieren, z. B. nach res://_scenes/scene_registry.gd)
## ════════════════════════════════════════════════════════════════
##  Hier steht die Reihenfolge der Szenen im Loop.
##
##  Format: res:// Pfad zum Ordner der Szene (mit abschließendem /)
##  Metadaten (Name, Dauer, Avatar, …) kommen aus scene_info.cfg
##  im jeweiligen Ordner (Vorlage: scene_info.cfg neben dieser Datei).
##
##  Szene hinzufügen:  Zeile einfügen, Reihenfolge = Ablauf
##  Szene deaktivieren: Zeile mit # auskommentieren
##
##  Anderer Pfad für diese Datei? Project Setting
##  "situs_core/scene_loop/registry_path" setzen.
## ════════════════════════════════════════════════════════════════

extends RefCounted


func get_scenes() -> Array:
	return [
		"res://_scenes/team_a/",
		# "res://_scenes/team_b/",
		# weitere Szenen hier eintragen …
	]
