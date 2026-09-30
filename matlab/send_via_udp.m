function info = send_via_udp(field, varargin)
%SEND_VIA_UDP Sendet ein 2D- oder 3D-Feld an die Godot-Visualisierung (Protokoll v2).
%
%   send_via_udp(field)
%   send_via_udp(field, 'Range',[0 1], 'ColorMap','viridis', 'Title','Meine Simulation')
%   info = send_via_udp(...)   % info.bytes, info.packets, info.seconds
%
%   field   numerische Matrix, 2D [nx ny] oder 3D [nx ny nz].
%           Dim 1 = x, Dim 2 = y, Dim 3 = z. 2D-Felder werden als Hoehenkarte
%           dargestellt, 3D-Felder als Volumen. Die Groesse darf sich zur
%           Laufzeit aendern (max. 512 pro Dimension).
%
%   Optionen (alle optional):
%     'Range'       [vmin vmax]  Wertebereich fuer die Skalierung auf 0..255.
%                                Werte ausserhalb werden abgeschnitten.
%                                Standard: udp_config().defaultRange
%     'Autoscale'   true/false   Range pro Frame aus min/max des Feldes bestimmen
%                                (Farben koennen dabei flackern).
%     'ColorMap'    'rainbow' | 'hot' | 'gray' | 'viridis'
%     'Extent'      [x y z]      Physikalische Groesse in Godot-Metern (bei 2D: z = Hoehe)
%     'Density'     Zahl         Deckkraft-Faktor des Volumens
%     'Threshold'   0..1         Werte darunter werden nicht gezeichnet
%     'Interpolate' true/false   Zeitliche Ueberblendung zwischen Frames in Godot
%     'Title'       Text         Anzeige im Godot-Overlay
%     'Format'      "uint8" | "single"   Standard: udp_config().format
%
%   Die Optionen ColorMap, Extent, Density, Threshold, Interpolate und Title
%   werden als Konfigurationspaket (JSON) gesendet, bei Aenderung sofort, sonst
%   alle udp_config().configResend Sekunden erneut (falls Godot spaeter startet).
%
%   Paketformat siehe README.md.

persistent u frameId lastCfg cfgTimer
cfg = udp_config();
HEADER_SIZE = 32;

%% Optionen
p = inputParser;
p.addParameter('Range', [], @(x) isnumeric(x) && numel(x) == 2);
p.addParameter('Autoscale', false, @islogical);
p.addParameter('ColorMap', '', @(x) ischar(x) || isstring(x));
p.addParameter('Extent', [], @(x) isnumeric(x) && numel(x) == 3);
p.addParameter('Density', [], @isnumeric);
p.addParameter('Threshold', [], @isnumeric);
p.addParameter('Interpolate', [], @islogical);
p.addParameter('Title', '', @(x) ischar(x) || isstring(x));
p.addParameter('Format', cfg.format, @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
o = p.Results;

%% Feld pruefen
if ~isnumeric(field) && ~islogical(field)
    error("send_via_udp:field", "field muss numerisch sein.");
end
if ndims(field) > 3
    error("send_via_udp:field", "Nur 2D- und 3D-Felder werden unterstuetzt.");
end
dims = [size(field, 1), size(field, 2), size(field, 3)];   % 2D -> nz = 1
if any(dims > 512)
    error("send_via_udp:field", "Maximal 512 Werte pro Dimension (hier: %s).", mat2str(dims));
end

%% Socket (einmalig)
if isempty(u) || ~isvalid(u)
    u = udpport("datagram", "IPV4");
    % Standard ist 512 Byte: groessere write()-Aufrufe wuerden in mehrere
    % Datagramme zerschnitten. Deshalb auf die maximale Chunkgroesse setzen.
    u.OutputDatagramSize = min(65507, cfg.maxPayload + HEADER_SIZE);
    frameId = 0;
    lastCfg = "";
    cfgTimer = tic;
end
tStart = tic;
packets = 0;

%% Konfigurationspaket
c = struct();
if strlength(string(o.ColorMap)) > 0, c.colormap    = char(o.ColorMap); end
if ~isempty(o.Extent),                c.extent      = o.Extent(:).';    end
if ~isempty(o.Density),               c.density     = o.Density;        end
if ~isempty(o.Threshold),             c.threshold   = o.Threshold;      end
if ~isempty(o.Interpolate),           c.interpolate = o.Interpolate;    end
if strlength(string(o.Title)) > 0,    c.title       = char(o.Title);    end
if ~isempty(fieldnames(c))
    json = string(jsonencode(c));
    if json ~= lastCfg || toc(cfgTimer) >= cfg.configResend
        cfgBytes = [typecast(uint16(hex2dec('4643')), 'uint8'), uint8(char(json))];
        if numel(cfgBytes) <= u.OutputDatagramSize
            write(u, cfgBytes, "uint8", cfg.godotIP, cfg.godotPort);
            packets = packets + 1;
        else
            warning("send_via_udp:config", "Konfiguration zu gross, nicht gesendet.");
        end
        lastCfg = json;
        cfgTimer = tic;
    end
end

%% Wertebereich und Umwandlung in Bytes
if o.Autoscale
    vmin = double(min(field(:)));
    vmax = double(max(field(:)));
    if vmax <= vmin, vmax = vmin + 1; end
elseif ~isempty(o.Range)
    vmin = o.Range(1);  vmax = o.Range(2);
else
    vmin = cfg.defaultRange(1);  vmax = cfg.defaultRange(2);
end

if lower(string(o.Format)) == "single"
    fmt = 0;
    bytes = typecast(single(field(:)), 'uint8');
else
    fmt = 1;
    scaled = (single(field(:)) - single(vmin)) ./ single(vmax - vmin);
    bytes = uint8(round(255 * min(max(scaled, 0), 1)));   % NaN -> 0
end
bytes = bytes(:).';
totalBytes = numel(bytes);

%% In Chunks aufteilen und senden (ein Paket, wenn es passt)
nChunks   = ceil(totalBytes / cfg.maxPayload);
chunkSize = ceil(totalBytes / nChunks);                  % gleichmaessig; letzter Chunk ggf. kuerzer
for k = 0:nChunks-1
    a = k * chunkSize + 1;
    b = min((k + 1) * chunkSize, totalBytes);
    header = packHeader(fmt, frameId, k, nChunks, dims, vmin, vmax);
    write(u, [header, bytes(a:b)], "uint8", cfg.godotIP, cfg.godotPort);
end
packets = packets + nChunks;
frameId = mod(frameId + 1, 2^32);

if nargout > 0
    info = struct('bytes', totalBytes, 'packets', packets, 'seconds', toc(tStart));
end
end

function h = packHeader(fmt, frameId, idx, cnt, dims, vmin, vmax)
% 32 Byte, little-endian (x86/ARM)
h = [typecast(uint16(hex2dec('4456')), 'uint8'), uint8(2), uint8(fmt), ...
     typecast(uint32(frameId), 'uint8'), ...
     typecast(uint16(idx), 'uint8'), typecast(uint16(cnt), 'uint8'), ...
     typecast(uint16(dims(1)), 'uint8'), typecast(uint16(dims(2)), 'uint8'), ...
     typecast(uint16(dims(3)), 'uint8'), uint8([0 0]), ...
     typecast(single(vmin), 'uint8'), typecast(single(vmax), 'uint8'), ...
     uint8([0 0 0 0])];
end
