# modul_scene_loop

Spielt mehrere Szenen nacheinander ab (Ausstellungs-Loop). Ohne dieses Modul zeigt der Core nur eine Szene.

## Was es tut

- liest die Szenen-Reihenfolge aus einer Registry-Datei (Liste von Ordnerpfaden)
- liest Name, Dauer, Avatar, Team, Info, Spielerfarbe aus `scene_info.cfg` im Szenen-Ordner
- Server: Timer pro Szene, Auto-Wechsel, **N** = nächste Szene, **L** = Auto-Wechsel an/aus
- Server-HUD: Timer-Anzeige, „Nächste Szene“-Button, Auto-Wechsel-Schalter
- Standalone-Modus (ohne Server): VR-Taste B/Y bzw. FPS-Taste Q/E wechseln lokal

## Einrichten

1. Registry anlegen: `templates/scene_registry.example.gd` nach `res://_scenes/scene_registry.gd` kopieren und Szenen-Ordner eintragen.
   Anderer Pfad? Project Setting `situs_core/scene_loop/registry_path`.
2. Pro Szene einen Ordner mit `scene_info.cfg` (Vorlage: `templates/scene_info.cfg`) und der Szene anlegen.
   Als Basis dient `addons/situs_core/templates/team_scene.tscn`.
3. Plugin „Situs Core“ aktivieren. Es trägt den Autoload `SceneLoop` ein.

Deaktivieren: Project Setting `situs_core/modules/modul_scene_loop = false` oder den Ordner löschen
(Autoload `SceneLoop` danach aus den Project Settings entfernen).

## Anbindung an den Core

| Richtung | Mechanismus |
|----------|-------------|
| Modul → Core | setzt `SceneManager.scene_provider`, ruft `SceneManager.request_scene(index)` |
| Core → Modul | `SceneManager.scene_changed`, `SceneManager.scene_step_requested(±1)` |
| Server-HUD | `main.gd` findet `/root/SceneLoop` und zeigt Timer-Elemente nur, wenn es existiert |

Autoload-Reihenfolge: `SceneLoop` muss nach `SceneManager` stehen (das Plugin sorgt dafür).
