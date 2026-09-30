# MatLab_CommTest: MATLAB → Godot 4 per UDP (WLAN)

Echtzeit-Kopplung: MATLAB berechnet ein zeitveränderliches 2D- oder 3D-Feld und sendet es per UDP an Godot 4. Godot stellt 3D-Felder als Volumen (Raymarching) und 2D-Felder als Höhenkarte dar. Langfristiges Ziel: VR-Simulator.

Studierende schreiben nur ihre eigene Simulationsschleife und rufen `send_via_udp(field)` auf. Der Rest bleibt unverändert.

```
matlab/
  send_via_udp.m           Senden (Quantisierung, Chunking, Header, Konfiguration)
  udp_config.m             Feste Godot-IP (192.168.50.166), Port, Payload-Größe
  simulate_field.m         Beispiel 3D-Volumen
  simulate_surface.m       Beispiel 2D-Höhenkarte
godot/
  project.godot, main.tscn
  udp_receiver.gd          UDP-Empfang, Chunk-Zusammenbau, Texturen, Konfiguration
  volume_raymarch.gdshader Volumen-Shader (3D)
  heightmap.gdshader       Höhenkarten-Shader (2D)
  colormap.gdshaderinc     Farbskalen (rainbow, hot, gray, viridis)
  box_outline.gd           Kanten-Wireframe
  orbit_camera.gd          Orbit-Kamera (LMB drehen, Mausrad zoomen)
  debug_overlay.gd         Pakete/s, FPS, Frame-Größe, Gitter, Wertebereich
```

## Schnellstart

1. **Godot** (4.3+): `godot/project.godot` importieren und starten (F5). Das Overlay zeigt "lauscht" auf Port 4242.
2. **MATLAB** (anderer Rechner): `matlab/` zum Pfad hinzufügen, `simulate_field.m` (3D) oder `simulate_surface.m` (2D) ausführen. Abbruch mit Strg+C.

## `send_via_udp` verwenden

```matlab
send_via_udp(field)                                    % 2D [nx ny] oder 3D [nx ny nz]
send_via_udp(field, 'Range',[0 1], 'ColorMap','viridis', 'Title','Meine Simulation')
info = send_via_udp(field);                            % info.bytes, info.packets, info.seconds
```

Dimension 1 = x, 2 = y, 3 = z. Die Gittergröße darf sich zur Laufzeit ändern und muss nicht kubisch sein (max. 512 pro Dimension). 2D-Felder (`nz = 1`) werden als **Höhenkarte** gezeigt, 3D-Felder als **Volumen**.

| Option | Bedeutung |
|---|---|
| `'Range',[vmin vmax]` | Werte werden auf 0..255 abgebildet, außerhalb wird abgeschnitten (Standard `[0 1]`) |
| `'Autoscale',true` | Range pro Frame aus min/max (Farben können flackern) |
| `'ColorMap'` | `rainbow`, `hot`, `gray`, `viridis` |
| `'Extent',[x y z]` | Größe in Godot-Metern (bei 2D ist z die Höhe) |
| `'Density'`, `'Threshold'` | Deckkraft und Schwellwert des Volumens |
| `'Interpolate',true/false` | Zeitliche Überblendung in Godot |
| `'Title'` | Text im Overlay |
| `'Format'` | `"uint8"` (Standard) oder `"single"` |

## Auflösung vs. FPS

Begrenzend ist der MATLAB-Sender: ein `write` kostet ca. 10 ms bei bis zu ~60 KB pro Datagramm, das sind rund 6 MB/s (dazu kommt die Rechenzeit der Simulation).

| Gitter (uint8) | Bytes/Frame | Pakete | realistische FPS |
|---|---|---|---|
| 32³ | 32 KB | 1 | 30–60 |
| 64³ | 256 KB | 5 | ca. 15–20 |
| 128³ | 2 MB | 35 | ca. 2–3 |

- **Wenig Auflösung, viele FPS:** flüssig, robust (1 Paket), grobe Voxel. Empfohlen: 32³–48³ bei 20–30 FPS.
- **Viel Auflösung, wenige FPS:** feine Struktur, aber ruckelig und anfälliger für Paketverlust (große Fragmente). Ab ca. 96³ im WLAN unpraktisch.
- **Interpolation in Godot** (Standard an): Godot hält den vorigen und den aktuellen Frame und blendet dazwischen über das gemessene Frame-Intervall. Das glättet niedrige Sende-FPS bei glatten Feldern, kostet aber eine Frame-Periode Latenz. Bei schnell bewegten Strukturen entsteht Überblendung statt echter Bewegung.

## Paketformat (Version 2, little-endian)

**Datenpaket**, 32 Byte Header + Payload. Passt ein Feld nicht in ein Datagramm (`maxPayload = 60000`), wird es automatisch in gleich große Chunks geteilt; sonst ist es ein einziges Paket.

| Offset | Typ | Inhalt |
|---:|---|---|
| 0 | uint16 | Magic `0x4456` |
| 2 | uint8 | Version = 2 |
| 3 | uint8 | Format: 0 = float32, 1 = uint8 |
| 4 | uint32 | Frame-ID |
| 8 | uint16 | Chunk-Index (ab 0) |
| 10 | uint16 | Chunk-Anzahl |
| 12 / 14 / 16 | uint16 | nx / ny / nz |
| 18 | uint16 | reserviert |
| 20 / 24 | float32 | vmin / vmax (Wertebereich der uint8-Skalierung) |
| 28 | uint32 | reserviert |

Payload: `field(:)` (x schnellster Index, dann y, dann z). Unvollständige Frames werden verworfen ("Verworfen" im Overlay), das nächste Frame ersetzt sie.

**Konfigurationspaket:** Magic `0x4643` (uint16), danach ein JSON-Text (UTF-8), z. B. `{"colormap":"hot","extent":[3,3,2],"interpolate":true,"title":"..."}`. Erlaubte Schlüssel: `colormap`, `extent`, `density`, `threshold`, `interpolate`, `title`. `send_via_udp` sendet es bei Änderung sofort, sonst alle 2 s erneut (falls Godot später startet).

**Ein Absender gleichzeitig:** Godot nimmt Pakete nur vom zuerst aktiven Absender an (nach 2 s Stille darf ein anderer übernehmen). Das Overlay zählt ignorierte Pakete unter "Fremd".

## WLAN- und Netzwerk-Tipps

### 1. IP-Adresse ermitteln

Godot-Rechner (Empfänger), hier `192.168.50.166`:

```powershell
# Windows
ipconfig            # Eintrag "IPv4-Adresse" des WLAN-Adapters
```
```bash
# macOS
ifconfig | grep "inet "
# Linux
ip a
```

Diese IP muss in `matlab/udp_config.m` als `godotIP` stehen. Beide Rechner müssen im selben Subnetz sein (`192.168.50.x`). Bei manchen Routern isoliert "AP/Client-Isolation" WLAN-Geräte voneinander; dann kommt nichts an, bis sie ausgeschaltet wird. Test: `ping 192.168.50.166` vom MATLAB-Rechner.

### 2. Firewall

- **Godot-Rechner:** eingehenden UDP-Port 4242 freigeben. Windows (Admin-PowerShell):
  ```powershell
  New-NetFirewallRule -DisplayName "Godot UDP 4242" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow
  ```
  Alternativ die Windows-Abfrage beim ersten Start von Godot mit "Zugriff zulassen" (auch für *Private Netzwerke*) bestätigen.
- **MATLAB-Rechner:** ausgehender UDP-Verkehr ist normalerweise erlaubt.

### 3. Paketgröße, MTU und Paketverluste

- Ein UDP-Datagramm darf max. 65 507 Byte haben. Große Datagramme werden im WLAN in ~1500-Byte-Fragmente zerlegt; geht eines verloren, ist das ganze Datagramm weg.
- Bei vielen "Verworfen" im Overlay: `maxPayload` in `udp_config.m` senken (z. B. 1400, dann keine Fragmentierung, aber ~46× mehr Pakete und in MATLAB deutlich langsamer), das Gitter verkleinern oder die FPS senken. 5-GHz-WLAN oder LAN-Kabel helfen ebenfalls.
- MATLABs `udpport` schneidet `write`-Aufrufe standardmäßig bei 512 Byte (`OutputDatagramSize`) in mehrere Datagramme. `send_via_udp` setzt den Wert passend.
- Der Empfangspuffer in Godot ist 4 MB groß (`recv_buffer_size`).

## Anpassungen in Godot

- Shader-Parameter (Schrittzahl, Dichte, Schwelle, Emission) am Material der Node `Volume`; `interpolate` und `allow_remote_config` an der Node `Volume` im Inspector.
- Port: `port` an der Node `Volume` (Godot) und `godotPort` in `udp_config.m`.
- VR-Erweiterung geplant: Mit dem OpenXR-Vendors-Plugin (Quest) nutzt der Shader `CAMERA_POSITION_WORLD` pro Auge; der Raymarch-Aufbau funktioniert dafür unverändert.
