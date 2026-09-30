%% simulate_surface.m  -  Beispiel: 2D-Feld, in Godot als Hoehenkarte dargestellt
% Ein 2D-Feld (nz = 1) wird von Godot automatisch als Hoehenkarte gezeigt.
% Abbruch mit Strg+C.

clear; clc;

gridSize  = [64 64];
targetFPS = 30;

[X, Y] = ndgrid(linspace(-1, 1, gridSize(1)), linspace(-1, 1, gridSize(2)));
R = hypot(X, Y);

t0 = tic;  statTimer = tic;  statFrames = 0;
while true
    frameTimer = tic;
    t = toc(t0);

    % --- eigene Simulation: fieldData(x,y), hier Werte ca. -1..1 ---
    fieldData = sin(10 * R - 3 * t) .* exp(-2 * R.^2);

    % --- senden (Wertebereich -1..1 wird auf die Hoehe 0..1 abgebildet) ---
    info = send_via_udp(fieldData, 'Range', [-1 1], 'ColorMap', 'viridis', ...
                        'Title', 'Wellen (2D-Hoehenkarte)');

    statFrames = statFrames + 1;
    if toc(statTimer) >= 1
        fprintf("%.1f FPS | %s Gitter | %d Pakete/Frame | %.1f KB/Frame\n", ...
            statFrames / toc(statTimer), mat2str(gridSize), info.packets, info.bytes/1024);
        statFrames = 0;  statTimer = tic;
    end
    pause(max(0, 1/targetFPS - toc(frameTimer)));
end
