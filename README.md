# MatLab_CommTest: MATLAB → Godot 4 per UDP

Echtzeit-Kopplung: MATLAB berechnet zeitveränderliche Felder, Partikel oder Zellularautomaten und sendet sie per UDP an Godot 4. Godot stellt sie in einem Raum von 4 × 8 m dar (2D-Daten auf dem Boden, 3D-Daten in einer 2 m hohen Box) (Bild, Höhenfläche, Schnitte, Volumen, Pfeile, Partikel, Automat auf Ebene/Kugel/Torus). Langfristiges Ziel: VR-Simulator (siehe [docs/plan.md](docs/plan.md)).

Das Protokoll ist **typisiert**: Ein vierstelliger Magic-String (z. B. `S3v.`, `V2q0`, `P2p1`, `C2m2`) wählt Datenformat und Darstellung. Studierende schreiben nur ihre Simulationsschleife und rufen `udpSend(u, data, frameid)` auf.

```
matlab/udp/
  udpOpen.m        Sender anlegen (Magic, Ziel-IP, Port, Wertebereich)
  udpSend.m        Frame senden (Quantisierung, Chunking, Header, ein write() pro Frame)
  udpListen.m      MATLAB-Betrachter (udpReceive + udpDrawnow)
  udpReceive.m     Frames empfangen und dekodieren
  udpDrawnow.m     Darstellung in MATLAB
  test2d.m, test3d.m, udpTest.m, testProtocol.m   Beispiele und Tests
  README.md        Bedienung des Senders und der MATLAB-Betrachter (englisch)
  PROTOCOL.md      Paketformat (englisch, maßgeblich)
  HEADER_SESSION.md  Session-ID
godot/
  project.godot, main.tscn
  udp_receiver.gd  UDP-Empfang, Session-/Frame-Logik, Chunk-Zusammenbau, Warteschlange
  scene_view.gd    Darstellung je Magic (Ebenen), Raum 4 × 8 × 2 m, Einpassen
  field_image.gdshader, field_height.gdshader, field_slice.gdshader, volume_raymarch.gdshader
  colormap.gdshaderinc   Farbskalen (rainbow, hot, gray, viridis)
  box_outline.gd, orbit_camera.gd, debug_overlay.gd
  selftest.gd      Test ohne Netzwerk
docs/
  plan.md          Architektur MATLAB → Server-PC → Brillen (Planung)
```

> **Veraltet:** `matlab/send_via_udp.m`, `udp_config.m`, `simulate_field.m` und `simulate_surface.m` gehören zum alten Protokoll v2 (Magic `0x4456`, Konfigurationspakete). Der neue Godot-Empfänger versteht dieses Format **nicht** mehr. Für neue Simulationen `matlab/udp/` verwenden.

## Schnellstart

1. **Godot 4.7**: `godot/project.godot` importieren und starten (F5). Das Overlay zeigt "lauscht" auf Port 4242.
2. **MATLAB**: `matlab/udp/` zum Pfad hinzufügen und senden:

```matlab
u = udpOpen(magic="S3v.", address="127.0.0.1", port=4242, vspan=[0 1]);
for t = 1:1000
    field = ...;              % [ny nx nz], Werte im Bereich vspan
    udpSend(u, field, t);     % t = aufsteigende Frame-ID
    pause(1/20);
end
```

Zwei Rechner: `address` auf die IPv4-Adresse des Godot-Rechners setzen und dort eingehend UDP-Port 4242 in der Firewall freigeben. `udpTest` sendet nacheinander alle Magics (je 5 s), um den Betrachter zu prüfen.

## Magics und Eingabeformate

| `magic` | Darstellung | MATLAB-Eingabe |
|---|---|---|
| `S2i.` | Skalarfeld als Bild | `[ny nx]` |
| `S2s.` | Skalarfeld als Höhenfläche | `[ny nx]` |
| `S3i<n>` | `n` Schnitte entlang z (`0`: drei Mittelschnitte) | `[ny nx nz]` |
| `S3v.` | Volumen (Raymarching) | `[ny nx nz]` |
| `V2q<k>` / `V3q<k>` | Pfeile (`k` = 0 automatisch, sonst Pfeillänge in Zellen) | `[ny nx 1 2]` / `[ny nx nz 3]` |
| `P2p<x>` / `P3p<x>` | Partikelart `x` (eigene Farbe, Geschwindigkeitspfeile bei 4/6 Spalten) | `[N 2\|3\|4\|6]` |
| `C2i.` | Zellularautomat als Bild | `[ny nx]` |
| `C2m<0\|1\|2>` | Automat auf Ebene / Kugel / Torus | `[ny nx]` |
| `T...` | reserviert (Verkehr) | nicht umgesetzt |

Wichtig:
- **Achsen:** Dimension 1 = y (`ny`), Dimension 2 = x (`nx`), Dimension 3 = z, wie bei MATLAB-`imagesc`. Die Daten werden spaltenweise (`data(:)`) gesendet.
- **Wertebereich:** `vspan=[vmin vmax]` gilt für alle S/V-Komponenten. Die Werte werden abgeschnitten und auf 0..255 quantisiert. Partikel gehen unquantisiert als `float32`, Positionen normiert auf 0..1. Automaten werden mit 1, 2, 4 oder 8 Bit pro Zustand gepackt (`nostates`).
- **Ebenen:** Jeder Magic ergibt eine eigene Ebene in der Plotbox (bei `P` je Art). Zwei Datensätze derselben Simulation brauchen **eigene, aufsteigende Frame-IDs** (z. B. 1, 3, 5 Dichte und 2, 4, 6 Vektoren).
- **Raum und Einpassen:** Der Boden misst 4 m (MATLAB-x, `nx`) × 8 m (MATLAB-y, `ny`) und ist um den Ursprung zentriert. MATLAB-z zeigt nach oben. **2D-Daten** (`S2i`, `S2s`, `V2q`, `P2p`, `C2i`, `C2m0`) liegen auf dem Boden. **3D-Daten** (`S3*`, `V3q`, `P3p`) sowie Kugel und Torus (`C2m1`, `C2m2`) liegen in einer 2 m hohen Box, die 0,5 m über dem Boden beginnt. Die Daten füllen die jeweilige Fläche bzw. Box und werden dabei verzerrt, wenn das Gitter ein anderes Seitenverhältnis hat. Mit `stretch = false` an der Node `View` wird stattdessen ohne Verzerrung eingepasst. Maße: `box_size` und `lift` an der Node `View`. **Ausrichtung:** `room_rotation_deg` an `View` dreht den ganzen Raum um die Senkrechte (Standard 90°: die 8 m-Seite liegt entlang der Godot-x-Achse), um ihn zum echten Raum auszurichten. Später soll das serverseitig einstellbar sein. Höhenflächen (`S2s`) steigen bis zur halben Boxhöhe (1 m).

## Paketformat (Kurzfassung)

Jedes Datagramm beginnt mit 20 Byte (little-endian): Magic (4 Byte ASCII), Session-ID, Frame-ID, Chunk-Index und Chunk-Anzahl (je uint32). Danach folgt je nach `magic(1)` ein Zusatz-Header (S/V: 52 Byte gesamt, P: 28, C: 33) und die Nutzdaten. Das vollständige Format steht in [matlab/udp/PROTOCOL.md](matlab/udp/PROTOCOL.md).

- **Session-ID:** `udpOpen` erzeugt pro Lauf eine neue Session-ID. Godot verwirft bei einer neuen ID den alten Zustand und ignoriert späte Pakete der letzten 32 alten Sessions. Eine neu gestartete Simulation wird daher sofort angezeigt, auch wenn die Frame-ID wieder bei 0 beginnt.
- **Frame-ID:** Innerhalb einer Session werden nur Frames mit einer größeren ID als der letzten fertigen angenommen. Unvollständige Frames werden verworfen (Overlay: "Verworfen"), sobald ein neueres kommt.
- **Warteschlange:** Fertige Frames kommen in eine Warteschlange, pro Magic bleibt nur das neueste. Pro Godot-Frame wird ein Frame dargestellt.
- **Chunking:** `udpSend` baut alle Datagramme in einem Puffer und ruft `write()` **einmal pro Frame** auf. `datagramSize` (Standard 65000, Bereich 1000..65000) ist die gesamte UDP-Nutzlast inklusive Header.

## Bedienung in Godot

| Taste | Wirkung |
|---|---|
| Linke Maustaste ziehen | Kamera um den Mittelpunkt drehen (Orbit) |
| Rechte Maustaste ziehen | Ansicht verschieben (Panning) |
| Mausrad | Zoom |
| `C` | Colormap wechseln (rainbow, hot, gray, viridis) |
| `F3` | Overlay ein-/ausblenden (Pakete/s, Frames/s, Frame-Größe, Verworfen, Session, Magic, Ebenen) |

Port und Bind-Adresse stehen an der Node `Receiver` (`port`, `bind_address`, `recv_buffer_size`). Es ist IPv4 gebunden (`0.0.0.0`).

## Situs Core: Server und mehrere Brillen

Das Godot-Projekt startet jetzt mit [Situs Core](https://github.com/FutureRealitiesLab/Situs-Core) (Subtree in `godot/addons/situs_core`, Renderer GL Compatibility). Situs liefert Server, Clients, Avatare und die Spieler. Die Simulation läuft als Szene darin.

```
MATLAB --UDP 4242--> Server (godot, "Als Server starten")
                       SimulationRelay empfängt, zeigt an und veröffentlicht
                       --ENet 7777, Kanal 1 (modul_data_channel)--> Brillen und FPS-Clients
```

| Datei | Aufgabe |
|---|---|
| `simulation_scene.tscn/.gd` | Szene mit `scene_view.gd`, Raumrahmen und Overlay. Raumgröße aus den Situs-Settings |
| `simulation_relay.gd` | Autoload. Server: UDP empfangen und veröffentlichen. Client: Frames vom Datenkanal. Beide lösen das Signal `frame_received` für `scene_view.gd` aus |
| `modul_data_channel/` | Generischer Datenkanal vom Server zu den Clients ([README](godot/modul_data_channel/README.md)) |

**Einstellungen** (Project Settings, Abschnitt *Situs Core*): `network/server_ip`, `room/width_m` (4), `room/length_m` (8), `room/rotation_deg`. Die Raumdrehung wirkt auf den XR-Ursprung der Brillen, nicht auf den Inhalt. Der frühere Wert `room_rotation_deg = 90` an `View` entspricht jetzt `rotation_deg = -90` (Vorzeichen an der Brille prüfen). Weitere Details in der Situs-Core-README.

**Eigene Settings dieses Projekts** (optional): Sie gehören zu diesem Projekt, nicht zu Situs, und stehen nicht im Editor-Dialog. Man trägt sie in `godot/project.godot` unter `[sim]` ein. Fehlen sie, gelten die Standardwerte.

| Setting | Standard | Bedeutung |
|---|---|---|
| `sim/udp_port` | `4242` | UDP-Port, auf dem Godot die MATLAB-Daten empfängt. Er muss mit `udpOpen(port=...)` in MATLAB übereinstimmen. Nur ändern, wenn 4242 belegt ist. |
| `sim/udp_on_clients` | `false` | `false`: Nur der Server empfängt MATLAB und verteilt die Daten über den Datenkanal an die Clients. `true`: Jede Instanz (auch Brille oder FPS-Client) empfängt selbst per UDP, ohne Server und ohne Datenkanal. |

Wann `sim/udp_on_clients = true`? Für **eine einzelne Brille ohne Server**: MATLAB sendet direkt an die IP der Brille (`udpOpen(address="<IP der Brille>")`), und die Brille zeigt die Daten allein an. Bei mehreren Brillen bleibt es `false`: MATLAB sendet an den Server, der Datenkanal verteilt weiter. Mit `true` werden Frames auf den Clients nicht mehr vom Server geholt, und mehrere Absender auf demselben Port sind nicht vorgesehen.

Beispiel in `project.godot`:

```ini
[sim]

udp_port=4242
udp_on_clients=false
```

Auch beim F6-Test der `simulation_scene.tscn` allein empfängt die Instanz direkt per UDP, unabhängig von diesen Settings.

**Start:** Server-PC: F5, „Als Server starten“. Die Serveransicht lässt sich mit der Maus navigieren: links ziehen dreht, rechts ziehen verschiebt, Mausrad zoomt. Brillen: APK mit der Server-IP in den Settings. Desktop-Test: zweite Instanz mit „Als Spieler starten (Lokal / 127.0.0.1)“. Im Overlay (F3) zeigen „Rolle“ und „Relay“ den Stand.

**Nicht mehr aktuell:** `main.tscn` mit `orbit_camera.gd` und `xr_rig.gd` (Flug, LBE-Tag) ist nicht mehr die Startszene. Sie bleibt als eigenständiger Betrachter ohne Situs erhalten (auch der `selftest` nutzt sie). Die Abschnitte „VR mit SteamVR“ und „APK für die Vive Focus Vision“ unten beschreiben diesen alten Betrachter.

## VR mit SteamVR (HTC Vive am PC)

Das Projekt startet automatisch in VR, wenn SteamVR läuft und ein Headset erkannt wird (OpenXR). Ohne Headset bleibt die Desktop-Ansicht mit Orbit-Kamera. Die Konsole meldet `XR: OpenXR aktiv.` bzw. `XR: kein OpenXR-Headset, Desktop-Ansicht.`

**Voraussetzungen:** SteamVR starten und als OpenXR-Runtime setzen (SteamVR → Einstellungen → OpenXR → "SteamVR als OpenXR-Runtime festlegen"). Dann Godot 4.7 starten (F5 oder Play-Button).

**Steuerung (Flug, keine Schritte):**

| Eingabe | Wirkung |
|---|---|
| Linker Stick bzw. Trackpad | Fliegen in Zeigerichtung des linken Controllers (vor/zurück, seitlich) |
| Rechter Stick, x | Stufenlos drehen, um die Kopfposition |
| Rechter Stick, y | Senkrecht steigen / sinken |

Die Controller werden als kleine Quader dargestellt. Der Startpunkt liegt auf dem Boden, 1,5 m vor der Längskante der 4 × 8 m-Fläche, Blickrichtung in den Raum. Der Raum ist in Metern fest (siehe oben), er wird nicht mehr zum Headset hin skaliert. Geschwindigkeit und Drehrate stehen an der Node `XRRig` (`fly_speed`, `turn_speed_deg`, `deadzone`). Das Overlay (`F3`) ist nur im Desktopfenster sichtbar, nicht im Headset.

Aufbau: `godot/xr_rig.gd` liegt auf `XRRig` (XROrigin3D mit Kamera und zwei Controllern). Die Projekteinstellungen `xr/openxr/enabled` und `xr/shaders/enabled` sind gesetzt. Die Eingaben kommen aus der Standard-Action-Map von Godot (`primary` = Stick oder Trackpad).

## APK für die Vive Focus Vision (Standalone)

Das Projekt exportiert zwei APKs aus **demselben Code**. Sie unterscheiden sich nur im Feature-Tag und damit in der Steuerung:

| Preset | Datei | Tag | Steuerung | Start |
|---|---|---|---|---|
| `Vive_Stationaer` | `godot/build/vive_stationaer.apk` | – | Fliegen per Controller (wie am PC) | 1,5 m vor der Längskante der 4 × 8 m-Fläche |
| `Vive_LBE` | `godot/build/vive_lbe.apk` | `lbe` | **keine** Stick-Bewegung, nur Gehen im Raum | Raummitte (`roomscale_origin` an `XRRig`) |

Das Skript `xr_rig.gd` fragt beim Start `OS.has_feature("lbe")` ab. Der Tag wird beim Export in die APK eingebrannt (Preset → Features → eigene Feature-Tags), die Brille muss nichts melden. Am PC und im Editor bleibt es beim Fliegen; die Konsole zeigt `XR: Locomotion FLY` bzw. `ROOMSCALE`.

**Renderer:** Auf dem PC läuft `mobile` (Vulkan), auf Android automatisch `gl_compatibility` (Projekteinstellung `renderer/rendering_method.mobile`). Die Shader laufen unter beiden. Mit `--rendering-method gl_compatibility` kannst du den Android-Pfad am PC prüfen. Die Vive Focus Vision wird laut Godot-Doku über das Khronos-Plugin des OpenXR-Vendors-Plugins angesprochen (`xr_features/enable_khronos_plugin`).

**Daten:** Die Brille hört selbst auf UDP-Port 4242 (WLAN). In MATLAB `udpOpen(address="<IP der Brille>")` setzen. Die Brille bekommt per DHCP evtl. wechselnde Adressen: im Router eine feste IP reservieren. Eine Brille entspricht einem Absender; mehrere Brillen brauchen das Relay aus [docs/plan.md](docs/plan.md).

**Export per Kommandozeile** (aus dem Repo-Ordner, Godot 4.7.2):

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
Godot --headless --path godot --export-debug "Vive_LBE" build/vive_lbe.apk
adb install -r godot/build/vive_lbe.apk
```

Im Editor: *Projekt → Exportieren*. Die APKs sind Debug-Builds mit dem Godot-Debug-Keystore und landen nicht im Repo.

### Einrichtung auf einem anderen Rechner

`godot/export_presets.cfg` liegt im Repo (Godot 4 speichert Zugangsdaten getrennt in `.godot/export_credentials.cfg`). Was nicht im Repo liegt, installiert das Skript:

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_android.ps1
```

Voraussetzung: Windows mit `winget`, Godot 4.7.2 einmal gestartet (damit die Editoreinstellungen existieren), danach Godot schließen und das Skript starten. Es installiert JDK 17, das Android SDK (Platform 36, Build-Tools 36.1.0, NDK 29.0.14206865, CMake) und die Export-Templates, legt das Android-Build-Template (`godot/android`) und das OpenXR-Vendors-Plugin (`godot/addons/godotopenxrvendors`) an, erzeugt den Debug-Keystore und trägt die Pfade in die Editoreinstellungen ein. Etwa 4 GB Download. Das Skript akzeptiert dabei die Android-SDK-Lizenzen. Was es nicht tut: Entwicklermodus an der Brille aktivieren und per USB oder WLAN-`adb` verbinden.

## Tests

- **Godot ohne Netzwerk:** prüft Empfänger (Chunks, Warteschlange, Session, ungültige Header, Bit-Packen) und zeichnet jeden Magic zweimal (Neuaufbau und Update).
  ```
  Godot --headless --path godot --script res://selftest.gd
  ```
- **MATLAB Loopback:** `testProtocol` prüft alle Formate und die Frame-Warteschlange.
- **Zusammenspiel:** Godot starten, in MATLAB `udpTest` ausführen und im Overlay "Magic" und "Ebenen" beobachten.

## Auflösung und Datenrate

Begrenzend ist meist der MATLAB-Sender: Ein `write()` kostet etwa 10 ms je Datagramm von bis zu 65 kB. Große Datagramme werden im WLAN in ~1500-Byte-Fragmente zerlegt, geht eines verloren, ist das ganze Datagramm weg. Bei vielen "Verworfen" im Overlay `datagramSize` senken, das Gitter verkleinern, die Sendefrequenz senken oder 5-GHz-WLAN bzw. Kabel nutzen. Richtwerte (uint8, 1 Byte/Voxel): 32³ = 32 KB/Frame, 64³ = 256 KB/Frame, 128³ = 2 MB/Frame.

## Netzwerk-Tipps

- **IP des Godot-Rechners:** `ipconfig` (Windows), `ifconfig` (macOS), `ip a` (Linux). Beide Rechner im selben Subnetz. "AP/Client-Isolation" im Router ausschalten. Test: `ping <Godot-IP>`.
- **Firewall (Godot-Rechner):** eingehend UDP 4242 freigeben, in einer Admin-PowerShell:
  ```powershell
  New-NetFirewallRule -DisplayName "Godot UDP 4242" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow
  ```
- **Nur ein Programm pro Port:** `udpListen` (MATLAB) und der Godot-Betrachter können nicht gleichzeitig auf Port 4242 hören.
- **Empfangspuffer:** In Godot 4 MB (`recv_buffer_size`).

## Projektstand und Ausblick

Das Godot-Projekt nutzt am PC den `mobile`-Renderer (Vulkan), auf Android `gl_compatibility`, und ist als Godot 4.7 gespeichert. Das Zielsystem (Hyper-Irrealismus III) verwendet laut [docs/plan.md](docs/plan.md) Godot 4.6 mit GL Compatibility. Beim Übernehmen in das VR-Template muss der Shader dort früh getestet werden. Dort gilt auch: Texturen als `R8` (uint8) verwenden. Die Architektur für Server und Brillen steht in [docs/plan.md](docs/plan.md).
