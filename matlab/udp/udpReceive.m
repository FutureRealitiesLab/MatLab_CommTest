function [data, info] = udpReceive(u, timeout)
%UDPRECEIVE Reconstruct the oldest queued complete UDP frame (no visualization).
%   [data, info] = udpReceive(u)         % default timeout: 0.2 s
%   [data, info] = udpReceive(u, timeout)
%
%   magic(1) selects header and payload format (S/V field, P particles,
%   C cellular automaton). Each call returns one frame; further complete
%   frames stay queued in u.UserData (newest per magic only).
%   Session IDs distinguish restarted simulations; older sessions are ignored.
%   S/V are [ny nx nz nv], P is N-by-2/3/4/6, C is [ny nx nz].

if nargin < 2 || isempty(timeout), timeout = 0.2; end
state = u.UserData;
if isempty(state)
    state = struct('sessionId', [], 'retiredSessions', uint32([]), ...
        'frameId', [], 'lastFrameId', [], 'magic', '', ...
        'dims', [], 'vspan', [], 'nostates', [], 'requiredBytes', [], ...
        'chunks', {{}}, 'received', 0, 'queue', {{}}, ...
        'senderAddress', "", 'senderPort', 0);
end

started = tic;
readCount = 0;

while toc(started) < timeout
    n = min(u.NumDatagramsAvailable, 1024);
    if n == 0
        if ~isempty(state.queue), break; end
        pause(0.001);
        continue;
    end
    packets = read(u, n, 'uint8');
    readCount = readCount + numel(packets);

    for k = 1:numel(packets)
        packet = uint8(packets(k).Data(:).');
        if numel(packet) < 21, continue; end
        magic = char(packet(1:4));
        headerSize = headerSizeOf(magic);
        if headerSize == 0 || numel(packet) <= headerSize, continue; end

        sessionId = readLE(packet(5:8), 'uint32');
        frameId = readLE(packet(9:12), 'uint32');
        index = double(readLE(packet(13:16), 'uint32'));
        count = double(readLE(packet(17:20), 'uint32'));
        if count < 1 || count > 100000 || index >= count, continue; end

        % A new udpOpen creates a new session. Discard old frame state,
        % including a previously displayed frame with a higher timestep.
        if isempty(state.sessionId) || sessionId ~= state.sessionId
            if any(state.retiredSessions == sessionId)
                continue;               % Late packet from an old session.
            end
            if ~isempty(state.sessionId)
                state.retiredSessions(end+1) = state.sessionId;
                nSessions = numel(state.retiredSessions);
                state.retiredSessions = state.retiredSessions( ...
                    max(1, nSessions-31):nSessions); % Keep up to 32 old IDs.
            end
            state.sessionId = sessionId;
            state.frameId = [];
            state.lastFrameId = [];
            state.chunks = {};
            state.received = 0;
            state.queue = {};
        end

        if ~isempty(state.lastFrameId) && frameId <= state.lastFrameId
            continue;                   % Old frame in the current session.
        end

        if isempty(state.frameId) || frameId > state.frameId
            hdr = readHeader(packet, magic);
            % Bound allocations from malformed network traffic.
            if isempty(hdr) || hdr.requiredBytes > 256 * 1024^2 || ...
                    count > hdr.requiredBytes
                continue;
            end
            state.frameId = frameId;
            state.magic = magic;
            state.dims = hdr.dims;
            state.vspan = hdr.vspan;
            state.nostates = hdr.nostates;
            state.requiredBytes = hdr.requiredBytes;
            state.chunks = cell(1, count);
            state.received = 0;
            state.senderAddress = string(packets(k).SenderAddress);
            state.senderPort = packets(k).SenderPort;
        elseif frameId < state.frameId || count ~= numel(state.chunks) || ...
                ~strcmp(magic, state.magic)
            continue;
        end

        if isempty(state.chunks{index+1})
            state.chunks{index+1} = packet(headerSize+1:end);
            state.received = state.received + 1;
        end
        if state.received == numel(state.chunks)
            bytes = [state.chunks{:}];
            if numel(bytes) == state.requiredBytes
                frame = struct('magic', string(state.magic), ...
                    'session_id', state.sessionId, ...
                    'frame_id', state.frameId, 'dims', state.dims, ...
                    'vspan', state.vspan, 'nostates', state.nostates, ...
                    'packets', numel(state.chunks), ...
                    'sender_address', state.senderAddress, ...
                    'sender_port', state.senderPort);
                % Keep only the newest queued frame per magic.
                keep = cellfun(@(q) q.info.magic ~= frame.magic, state.queue);
                state.queue = [state.queue(keep), {struct('bytes', bytes, 'info', frame)}];
                state.lastFrameId = state.frameId;
            end
            state.frameId = [];
            state.chunks = {};
        end
    end
end

if isempty(state.queue)
    data = [];
    info = struct('status', "timeout", 'magic', "", ...
        'session_id', state.sessionId, 'frame_id', [], ...
        'dims', [], 'vspan', [], 'nostates', [], 'packets', 0);
    state.frameId = [];    % Discard incomplete frame on timeout.
    state.chunks = {};
else
    entry = state.queue{1};
    state.queue(1) = [];
    info = entry.info;
    magic = char(info.magic);
    switch magic(1)
        case {'S', 'V'}
            data = dequantisize(entry.bytes, info.vspan);
        case 'P'
            data = readLE(entry.bytes, 'single');
        case 'C'
            data = decompress(entry.bytes, info.dims, info.nostates);
    end
    data = reshape(data, info.dims);
    info.status = "received";
end

u.UserData = state;
info.seconds = toc(started);
info.read_datagrams = readCount;
info.queued = u.NumDatagramsAvailable;
info.pending = numel(state.queue);
end

% ------------------------------------------------------------------------

function bytes = headerSizeOf(magic)
% Header bytes by magic(1); 0 marks an unknown or unsupported type.
switch magic(1)
    case {'S', 'V'}, bytes = 52;
    case 'P',        bytes = 28;
    case 'C',        bytes = 33;
    otherwise,       bytes = 0;
end
end

% ------------------------------------------------------------------------

function hdr = readHeader(packet, magic)
% Parse the type-specific header; empty if the declared shape is invalid.
switch magic(1)
    case {'S', 'V'}, hdr = headerField(packet, magic);
    case 'P',        hdr = headerParticle(packet);
    case 'C',        hdr = headerCellular(packet);
end
end

% ------------------------------------------------------------------------

function hdr = headerField(packet, magic)
% Field: dims [ny nx nz nv] at 21:36, vspan [vmin vmax] at 37:52.
dims = double(readLE(packet(21:36), 'uint32')).';
vspan = double(readLE(packet(37:52), 'double')).';
hdr = [];
if any(dims < 1) || ~all(isfinite(vspan)), return; end
if magic(1) == 'S'
    components = 1;
elseif magic(2) == '2'
    components = 2;
else
    components = 3;
end
if dims(4) ~= components || (magic(2) == '2' && dims(3) ~= 1), return; end
hdr = struct('dims', dims, 'vspan', vspan, 'nostates', [], ...
    'requiredBytes', prod(dims));
end

% ------------------------------------------------------------------------

function hdr = headerParticle(packet)
% Particles: dims [nParticles nCoords] at 21:28.
dims = double(readLE(packet(21:28), 'uint32')).';
hdr = [];
if any(dims < 1) || ~ismember(dims(2), [2 3 4 6]), return; end
hdr = struct('dims', dims, 'vspan', [], 'nostates', [], ...
    'requiredBytes', prod(dims) * 4);
end

% ------------------------------------------------------------------------

function hdr = headerCellular(packet)
% Cellular: dims [ny nx nz] at 21:32, nostates at 33.
dims = double(readLE(packet(21:32), 'uint32')).';
nostates = double(packet(33));
hdr = [];
if any(dims < 1) || nostates < 1, return; end
bits = 2^ceil(log2(max(1, ceil(log2(double(nostates))))));
hdr = struct('dims', dims, 'vspan', [], 'nostates', nostates, ...
    'requiredBytes', ceil(prod(dims) * bits / 8));
end

% ------------------------------------------------------------------------

function values = dequantisize(bytes, vspan)
% Reconstruct field values from uint8 codes (all components share vspan).
values = vspan(1) + (double(bytes) / 255) * (vspan(2) - vspan(1));
end

% ------------------------------------------------------------------------

function data = decompress(payload, dims, nostates)
% Unpack CA states (low-order bits first); caller restores the grid shape.
bits = 2^ceil(log2(max(1, ceil(log2(double(nostates))))));
perByte = 8 / bits;
payload = uint8(payload(:));
values = zeros(numel(payload)*perByte, 1, 'uint8');
mask = uint8(2^bits - 1);

for k = 0:perByte-1
    values(k+1:perByte:end) = ...
        bitand(bitshift(payload, -k*bits), mask);
end

data = values(1:prod(dims));
end

% ------------------------------------------------------------------------

function values = readLE(bytes, typeName)
% Convert little-endian bytes into MATLAB numeric values.
bytes = uint8(bytes(:));
[~, ~, endian] = computer;
if endian == 'B'
    if strcmp(typeName, 'double'), width = 8; else, width = 4; end
    bytes = reshape(flipud(reshape(bytes, width, [])), [], 1);
end
values = typecast(bytes, typeName);
end

% ------------------------------------------------------------------------
