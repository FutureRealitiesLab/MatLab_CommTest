# Entwicklungsprotokoll (KI-Chats)

Zusammenfassungen der Arbeitssitzungen mit Claude: was besprochen, entschieden und erreicht wurde. Keine Mitschrift. Neueste Einträge unten. Technische Änderungen stehen zusätzlich im [Changelog](../CHANGELOG.md). Die Situs-Seite hat ein eigenes Protokoll im Repo Situs-Core.

## 2026-10-29: Situs Core in MatLab_CommTest integrieren

**Ausgangslage:** Die Godot-Anwendung lief im Singleplayer, Shader waren auf der Vive Focus Vision im Standalone-Modus getestet. Gewünscht: Server empfängt MATLAB-UDP und verteilt die Daten an mehrere Brillen.

**Entschieden**
- Arbeitsordner ist `godot/`, `godot-stephan` wird ignoriert und später entfernt.
- Datenkanal wird im Projekt gebaut, aber als gekapseltes Modul, damit er später nach Situs wandern kann.
- Server-IP, Raumgröße (4 × 8 m) und Rotation gehören zu Situs und liegen in den Project Settings, nicht in einer Datei. Settings stecken beim Export in der APK.
- Rotation wirkt auf den XR-Ursprung, damit alle Szenen folgen und die Brillen nicht neu ausgerichtet werden müssen.

**Erreicht:** Plugin per subtree, Datenkanal mit Flusskontrolle und Late Join, Relay mit Rollen, Maussteuerung in der Serveransicht. Ende-zu-Ende headless mit synthetischen MATLAB-Paketen geprüft.

**Erklärt:** `sim/udp_port` legt den Port fest, auf dem der Server MATLAB-Pakete annimmt. `sim/udp_on_clients` lässt Clients selbst UDP empfangen (Direkt-Modus ohne Server).

## 2026-10-29/30: Export und Dokumentation

**Erreicht:** `docs/INSTALL.md` und `tools/setup_android.ps1` mit Schritten für einen neuen Rechner, Inhalt des Skripts und manuellen Punkten. Presets `Vive_Stationaer` und `Vive_LBE` (im Situs-Betrieb gleich, `Vive_LBE` verwenden). README und Firewall-Hinweise angepasst. Fehlermeldung zu `build-tools` verschwand nach dem Skript.

## 2026-10-30: Meilenstein

**Ereignis:** Die Brille zeigte „keine Verbindung“ bei `127.0.0.1:7777`. Server-IP war nicht gesetzt. Nach LAN-IP in den Project Settings und neuem Export läuft MATLAB im Netzwerk, und die andere Brille ist sichtbar.

**Erreicht:** `export_presets.cfg` committet, Branch gepusht, Plan, README und INSTALL auf den Stand gebracht.

**Offen:** siehe [plan.md](plan.md): Tests mit 4 und 8 Brillen, Rotationsvorzeichen, Messwerte, Greifen und Skalieren der Simulationskörper, kollaboratives Sketching.
