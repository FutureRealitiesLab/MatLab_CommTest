function cfg = udp_config()
%UDP_CONFIG Feste Einstellungen fuer die Verbindung zur Godot-Visualisierung.
%   Wird von send_via_udp benutzt. Studierende muessen hier nichts aendern.

cfg.godotIP       = "192.168.50.166";  % Rechner mit Godot
cfg.godotPort     = 4242;
cfg.maxPayload    = 60000;             % Nutzbytes pro Datagramm (max. ~65000). Groessere
                                       % Felder werden automatisch in Chunks geteilt.
cfg.defaultRange  = [0 1];             % Wertebereich, der auf 0..255 (uint8) abgebildet wird
cfg.format        = "uint8";           % "uint8" (schnell, 1 Byte/Wert) oder "single" (4 Byte/Wert)
cfg.configResend  = 2;                 % Sekunden, nach denen Konfigurationspakete erneut gesendet werden
end
