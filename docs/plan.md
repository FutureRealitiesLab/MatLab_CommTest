# Plan: Architektur MATLAB → Server-PC → Brillen (WLAN)

> **Status: Planung, noch nicht umgesetzt.** Dieses Dokument hält die Architekturempfehlung für das spätere Colocated-VR fest. Es wird bewusst noch nichts davon entwickelt.

## Kontext

Späteres Ziel: Colocated-VR auf Basis von Hyper-Irrealismus III (Godot 4.6, GL Compatibility Renderer, ENet UDP Port 7777, bis 8 Clients, HTC Vive Focus Vision / Meta Quest). Der MATLAB-Rechner und der Server-PC hängen per Kabel am Router, die Brillen per WLAN.

Frage: Wie kommen die Simulationsdaten zu den Brillen, und was schickt der Server: fertige Textur oder Rohdaten?

Gelesen wurden die Notion-Seite "Technische Basis: Hyper-Irrealismus III Template", README und ARCHITECTURE.md des Repos sowie `network_manager.gd` und `game_state.gd`. Der Server ist dort reines Avatar-Relay (~20 Hz, `unreliable_ordered`, ENet). Nicht gelesen werden konnte `SITUS_CORE_REFACTOR_PLAN_v2.md` (signierte Notion-Datei, HTTP 403).

## Empfehlung

**Kabel-Hop reich, WLAN-Hop budgetiert. Der Server ist die einzige Datenquelle, die Brillen rendern selbst.**

```
MATLAB (Kabel) --UDP, Protokoll v2, unverändert--> Server-PC (Kabel)
   Server: Empfang + Frame-Zusammenbau (bestehende Logik), optional Downsampling/Kompression
   Server --ENet, eigener Kanal, Ack-Flusskontrolle, uint8-Skalarfeld (+Config)--> Brillen (WLAN)
   Brille: Textur (ImageTexture3D R8) + Raymarch-Shader + Interpolation lokal
```

### Fertige Textur oder Rohdaten?

Die "Textur" ist das Rohdatenfeld: ein 3D-Skalarfeld mit 1 Byte pro Voxel. **Das Skalarfeld wird weitergeleitet, Farbe, Transferfunktion und Raymarching laufen auf der Brille.**

- Nicht senden: vorgefärbte RGBA-Texturen (4× größer, Colormap und Schwelle nicht mehr interaktiv) und keine Video-Streams (blickpunktabhängig pro Auge, Latenz).
- Das Volumen muss ohnehin pro Auge auf der Brille gerendert werden. Der Server kann das nicht vorab erledigen.

### Warum der Server als Relay und nicht MATLAB direkt an alle Brillen

- Ein MATLAB-`write` kostet ~10 ms je Datagramm, 8 Empfänger wären 8× teurer. MATLAB kennt keine Client-IPs, Reconnects oder späte Beitritte.
- Broadcast und Multicast im WLAN laufen mit niedrigster Rate, ohne ACK und werden oft geblockt. Sinnvoll nur mit AP-Multicast-zu-Unicast-Umsetzung.
- Der Server ist im Template schon zentral (Peer-IDs, Reconnect, Szenensignal) und kann die Daten server-autoritativ halten (im Notion als Phase-2-Punkt vorgesehen).

## Bandbreite

WLAN ist ein geteiltes Medium, und der Server sendet an jede Brille einzeln.

| Feld (uint8) | KB/Frame | Hz | je Brille | 8 Brillen gesamt |
|---|---:|---:|---:|---|
| 32³ | 32 | 20 | 0,6 MB/s | 5 MB/s (~41 Mbit/s) |
| 64³ | 256 | 10 | 2,6 MB/s | 21 MB/s (~168 Mbit/s), grenzwertig |
| 64³ | 256 | 20 | 5,1 MB/s | 41 MB/s (~330 Mbit/s), unrealistisch |

Hebel: Auflösung senken, Sende-Hz senken (die Brille interpoliert lokal), zstd-Kompression auf dem Server (`PackedByteArray.compress`, Felder komprimieren oft 2–5×), später Delta oder ROI. Der Kabel-Hop MATLAB → Server kann hochauflösend und schnell bleiben, der Server dezimiert für die WLAN-Strecke.

## Designpunkte für die spätere Umsetzung

1. **Eigener ENet-Transferkanal** für Volumendaten, damit Kopf- und Avatar-Posen (Kanal 0, `unreliable_ordered`) nicht hinter 256-KB-Frames hängen.
2. **Ack-basierte Flusskontrolle je Client:** Der nächste Frame wird erst gesendet, wenn der Client den vorigen bestätigt hat. Sonst wächst der Rückstau bei langsamen Brillen. Es gilt "neuester Frame gewinnt", ältere werden verworfen.
3. **Serverzeit im Frame** und ein Jitter-Puffer von einem Frame auf den Brillen, damit alle nahezu dasselbe Bild zeigen (Co-located: gemeinsame Realität).
4. **Late Join:** Bei `peer_connected` werden der letzte Frame und die letzte Config geschickt. Die Config (Colormap, Extent, Titel) ist klein, reliable und server-autoritativ.
5. **Renderer-Risiko (GL Compatibility, Focus Vision):** Das Raymarching ist der teuerste Teil (Pixel × Schritte × 2 Augen, plus zweites Sample für die Interpolation). Schritte auf ca. 24–32, frühes Abbrechen, Render-Scale wie im Template. Float32-Texturen mit linearem Filter sind auf Mobile nicht garantiert, daher **R8 (uint8) verwenden**. Shader und `ImageTexture3D.update()` früh auf der Zielhardware testen.
6. **WLAN:** eigenes 5/6-GHz-Netz, WiFi-6-AP, Energiesparmodus der Brillen aus, kein anderer Verkehr.
7. **Platzierung im gemeinsamen Raum:** Die Volumen-Transform steht in der Szene (`scene_hooks.gd` / `scene_info.cfg`), nicht im Datenstrom.

## Später umzusetzen (nicht jetzt)

- Empfangslogik aus `godot/udp_receiver.gd` in eine wiederverwendbare `VolumeSource` auslagern (Server: UDP-Quelle, Client: ENet-Quelle).
- Autoload `SimulationRelay` im Hyper-Irrealismus-Projekt.
- Szene `volume_display.tscn` (Volumen-Mesh + Shader), einbindbar über `scene_info.cfg`.
- Eingebauter Testdaten-Generator in Godot, damit sich der Datenpfad ohne MATLAB prüfen lässt.

## Messcheckliste (wenn Hardware da ist)

1. Server + 1 Brille, dann 4 und 8 Brillen.
2. Kennzahlen je Brille: Frame-Rate der Daten, verworfene Frames, RTT, GPU-Zeit des Raymarchings.
3. Zielwerte prüfen: Volumen mit 32³ bei 20 Hz und 64³ bei 10 Hz (mit Kompression) auf allen 8 Brillen stabil.
