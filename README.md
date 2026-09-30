# MatLab_CommTest: MATLAB → Godot 4 per UDP (WLAN)

Echtzeit-Kopplung: MATLAB erzeugt ein zeitveränderliches 3D-Skalarfeld (32×32×32) und sendet es per UDP an Godot 4. Godot setzt es zu einer `ImageTexture3D` zusammen und zeigt es per Raymarching-Shader auf einem Würfel an. Langfristiges Ziel: VR-Simulator.

```
matlab/simulate_field.m      MATLAB-Sender (Rechner 192.168.50.243)
godot/                       Godot-4-Projekt (Rechner 192.168.50.166)
  project.godot, main.tscn
  udp_receiver.gd            UDP-Empfang, Chunk-Zusammenbau, ImageTexture3D
  volume_raymarch.gdshader   Raymarching-Shader
  orbit_camera.gd            Orbit-Kamera (LMB drehen, Mausrad zoomen)
  debug_overlay.gd           Pakete/s, FPS, Frame-Größe
```

## Schnellstart

1. **Godot** (4.3+): `godot/project.godot` im Projektmanager importieren und starten (F5). Das Overlay zeigt "lauscht" auf Port 4242.
2. **MATLAB** (anderer Rechner): `matlab/simulate_field.m` öffnen, `godotIP = "192.168.50.166"` prüfen, ausführen. Abbruch mit Strg+C.

## Paketformat

Ein UDP-Datagramm darf höchstens 65 507 Byte Nutzdaten enthalten. Ein 32³-Float32-Feld hat 32³ × 4 = **131 072 Byte (128 KB)** und passt daher **nicht** in ein Datagramm. Deshalb wird jedes Volumen in Chunks zerlegt (Standard `maxPayload = 60000` = 3 Pakete; 1400 bleibt unter der WLAN-MTU, braucht aber ~94 Pakete und ist in MATLAB ca. 30x langsamer, da jeder `write` ~10 ms kostet), jeweils mit 16 Byte Header (little-endian):

| Offset | Typ    | Inhalt                            |
|-------:|--------|-----------------------------------|
| 0      | uint16 | Magic `0x4456`                    |
| 2      | uint8  | Format: 0 = float32, 1 = uint8    |
| 3      | uint8  | reserviert                        |
| 4      | uint32 | Frame-ID                          |
| 8      | uint16 | Chunk-Index (ab 0)                |
| 10     | uint16 | Chunk-Anzahl                      |
| 12     | uint16 | Gitter-Kantenlänge N              |
| 14     | uint16 | reserviert                        |

Payload: `field(:)` aus MATLAB (x schnellster Index, dann y, dann z). Godot legt jede z-Ebene als `Image` (`FORMAT_RF` bzw. `FORMAT_R8`) an. Unvollständige Frames (Paketverlust) werden verworfen und im Overlay als "Verworfen" gezählt; das nächste Frame ersetzt sie einfach.

Ein Volumen sind bei float32 ca. 94 Pakete, bei 20 Volumen/s also ca. 1900 Pakete/s und 2,5 MB/s.

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

Diese IP muss in MATLAB als `godotIP` stehen. Beide Rechner müssen im selben Subnetz sein (`192.168.50.x`). Bei manchen Routern isoliert "AP/Client-Isolation" WLAN-Geräte voneinander; dann kommt nichts an, bis sie ausgeschaltet wird.

Verbindung testen (vom MATLAB-Rechner): `ping 192.168.50.166`.

### 2. Firewall

- **Godot-Rechner:** eingehenden UDP-Port 4242 freigeben. Windows (Admin-PowerShell):
  ```powershell
  New-NetFirewallRule -DisplayName "Godot UDP 4242" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow
  ```
  Alternativ die Windows-Abfrage beim ersten Start von Godot mit "Zugriff zulassen" (auch für *Private Netzwerke*) bestätigen. Das WLAN-Profil sollte als "Privat" eingestuft sein.
- **MATLAB-Rechner:** ausgehender UDP-Verkehr ist normalerweise erlaubt. Falls nicht, MATLAB in der Firewall für ausgehende UDP-Verbindungen zulassen.

### 3. Paketgröße, MTU und Paketverluste

- 32×32×32 float32 = 131 072 Byte (~128 KB), das Skript zerlegt es in ~94 Chunks à ≤ 1400 Byte.
- Bei Paketverlusten im WLAN (Overlay zeigt viele "Verworfen"):
  - In `simulate_field.m` `sendAsUint8 = true` setzen: Werte werden auf 0–255 skaliert, die Größe sinkt auf **32 KB** (~24 Pakete). Der Empfänger erkennt das Format automatisch am Header.
  - `targetFPS` senken.
  - Wenn möglich Router-Band 5 GHz verwenden oder den Rechner per LAN anbinden.
- Der Empfangspuffer in Godot ist auf 4 MB gesetzt (`recv_buffer_size`), damit Bursts nicht verloren gehen.

## Anpassungen

- Shader-Parameter (Dichte, Schwelle, Schrittzahl, Wertebereich) am Material der Node `Volume` im Inspector. Feldwerte werden im Bereich `value_min`..`value_max` (Standard 0..1) auf die Farbskala abgebildet.
- Gittergröße: `gridSize` in MATLAB ändern, Godot passt die Textur automatisch an.
- Port: `port` an der Node `Volume` (Godot) und `godotPort` (MATLAB).
- Vorgesehene VR-Erweiterung: Mit dem OpenXR-Vendors-Plugin (Quest) verwendet der Shader `CAMERA_POSITION_WORLD` pro Auge; der Raymarch-Aufbau funktioniert dafür unverändert.
