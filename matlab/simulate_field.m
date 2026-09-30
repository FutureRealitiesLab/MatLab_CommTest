%% simulate_field.m
% Erzeugt ein zeitveraenderliches 3D-Skalarfeld und sendet es per UDP an Godot.
%
% Paketformat (little-endian), pro Datagramm:
%   Header (16 Byte):
%     uint16 magic      = 0x4456
%     uint8  format     = 0 (float32) | 1 (uint8)
%     uint8  reserved
%     uint32 frameId
%     uint16 chunkIdx   (0-basiert)
%     uint16 chunkCount
%     uint16 gridSize   (Kantenlaenge N, Feld ist N x N x N)
%     uint16 reserved
%   Payload: Teilstueck des Volumens, x schnellster Index, dann y, dann z
%            (= MATLAB-Spaltenreihenfolge von field(:) mit field(x,y,z)).
%
% Ein UDP-Datagramm darf max. 65507 Byte haben, 32^3*4 = 131072 Byte passen
% also nicht in ein Paket -> das Volumen wird in Chunks zerlegt.
% Abbruch mit Strg+C.

clear; clc;

%% Konfiguration
godotIP      = "192.168.50.166";  % Rechner mit Godot
godotPort    = 4242;
gridSize     = 32;                % 32x32x32 Werte
targetFPS    = 20;                % Ziel-Sendefrequenz (Volumen/s)
sendAsUint8  = false;             % true: 0..255 statt float32 (4x kleiner)
maxPayload   = 60000;             % Nutzbytes pro Datagramm (max. ~65000). Jeder write() kostet in
                                  % MATLAB ~10 ms -> wenige grosse Pakete sind viel schneller.
                                  % Bei Paketverlust im WLAN auf 1400 (MTU) senken, dann keine
                                  % IP-Fragmentierung, aber ~94 Pakete/Frame und langsamer.

%% Setup
MAGIC = uint16(hex2dec('4456'));
[X, Y, Z] = ndgrid(linspace(-1, 1, gridSize));   % X variiert entlang Dim 1 (schnellster Index)

u = udpport("datagram", "IPV4");
cleanupObj = onCleanup(@() delete(u)); %#ok<NASGU>

bytesPerValue = 4 - 3 * sendAsUint8;
totalBytes    = gridSize^3 * bytesPerValue;
nChunks       = ceil(totalBytes / maxPayload);
chunkSize     = ceil(totalBytes / nChunks);      % gleichmaessig; letzter Chunk ggf. kuerzer
fmt           = uint8(sendAsUint8);

% WICHTIG: Standard ist 512 Byte, groessere write()-Aufrufe wuerden in
% mehrere Datagramme zerschnitten und der Header waere nur im ersten.
u.OutputDatagramSize = 16 + chunkSize;

fprintf("Sende %dx%dx%d Feld (%s) an %s:%d\n", gridSize, gridSize, gridSize, ...
    ternary(sendAsUint8, "uint8", "float32"), godotIP, godotPort);
fprintf("Volumen: %d Byte (%.1f KB) in %d Paketen a max. %d Byte + 16 Byte Header\n", ...
    totalBytes, totalBytes/1024, nChunks, chunkSize);

%% Simulationsschleife
frameId    = uint32(0);
period     = 1 / targetFPS;
t0         = tic;
statTimer  = tic;
statFrames = 0;

while true
    frameTimer = tic;
    t = toc(t0);

    % Wandernde Gauss-Verteilung (Lissajous-Bahn) + laufende Sinuswellen
    cx = 0.6 * sin(0.9 * t);
    cy = 0.6 * sin(1.3 * t + 1.0);
    cz = 0.6 * cos(0.7 * t);
    blob  = exp(-((X-cx).^2 + (Y-cy).^2 + (Z-cz).^2) / (2 * 0.25^2));
    waves = 0.5 + 0.5 * sin(6 * X + 2 * t) .* sin(5 * Y - 1.5 * t) .* sin(4 * Z + t);
    fieldData = single(0.75 * blob + 0.25 * waves .* exp(-(X.^2 + Y.^2 + Z.^2)));   % ~0..1

    % In Byte-Array umwandeln
    if sendAsUint8
        bytes = uint8(255 * min(max(fieldData(:), 0), 1));
    else
        bytes = typecast(single(fieldData(:)), 'uint8');
    end
    bytes = bytes(:).';

    % In Chunks senden
    for c = 0:nChunks-1
        a = c * chunkSize + 1;
        b = min((c + 1) * chunkSize, totalBytes);
        header = [typecast(MAGIC, 'uint8'), fmt, uint8(0), ...
                  typecast(frameId, 'uint8'), ...
                  typecast(uint16(c), 'uint8'), typecast(uint16(nChunks), 'uint8'), ...
                  typecast(uint16(gridSize), 'uint8'), uint8([0 0])];
        write(u, [header, bytes(a:b)], "uint8", godotIP, godotPort);
    end
    frameId = frameId + 1;
    statFrames = statFrames + 1;

    % Statistik jede Sekunde
    if toc(statTimer) >= 1
        fprintf("%.1f FPS | %d Pakete/Frame | %.1f KB/Frame | %.2f MB/s\n", ...
            statFrames / toc(statTimer), nChunks, totalBytes/1024, ...
            statFrames * totalBytes / toc(statTimer) / 1e6);
        statFrames = 0;
        statTimer = tic;
    end

    % Auf Ziel-Framerate takten
    pause(max(0, period - toc(frameTimer)));
end

function r = ternary(c, a, b)
    if c, r = a; else, r = b; end
end
