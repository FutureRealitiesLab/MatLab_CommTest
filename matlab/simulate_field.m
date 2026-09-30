%% simulate_field.m  -  Beispiel: 3D-Volumen (wandernde Gauss-Kugel + Wellen)
% Vorlage fuer eigene Simulationsschleifen: Feld berechnen, send_via_udp aufrufen.
% Ziel-IP und Port stehen in udp_config.m. Abbruch mit Strg+C.

clear; clc;

gridSize  = [32 32 32];   % darf sich zur Laufzeit aendern und muss nicht kubisch sein
targetFPS = 30;

[X, Y, Z] = ndgrid(linspace(-1, 1, gridSize(1)), ...
                   linspace(-1, 1, gridSize(2)), ...
                   linspace(-1, 1, gridSize(3)));

t0 = tic;  statTimer = tic;  statFrames = 0;
while true
    frameTimer = tic;
    t = toc(t0);

    % --- eigene Simulation: fieldData(x,y,z), hier Werte ca. 0..1 ---
    cx = 0.6 * sin(0.9 * t);
    cy = 0.6 * sin(1.3 * t + 1.0);
    cz = 0.6 * cos(0.7 * t);
    blob  = exp(-((X-cx).^2 + (Y-cy).^2 + (Z-cz).^2) / (2 * 0.25^2));
    waves = 0.5 + 0.5 * sin(6 * X + 2 * t) .* sin(5 * Y - 1.5 * t) .* sin(4 * Z + t);
    fieldData = 0.75 * blob + 0.25 * waves .* exp(-(X.^2 + Y.^2 + Z.^2));

    % --- senden ---
    info = send_via_udp(fieldData, 'Range', [0 1], 'ColorMap', 'rainbow', ...
                        'Title', 'Wandernde Gauss-Kugel');

    statFrames = statFrames + 1;
    if toc(statTimer) >= 1
        fprintf("%.1f FPS | %s Gitter | %d Pakete/Frame | %.1f KB/Frame\n", ...
            statFrames / toc(statTimer), mat2str(gridSize), info.packets, info.bytes/1024);
        statFrames = 0;  statTimer = tic;
    end
    pause(max(0, 1/targetFPS - toc(frameTimer)));
end
