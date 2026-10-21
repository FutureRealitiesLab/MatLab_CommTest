function info = udpSend(u, data, frameid)
%UDPSEND Send a simulation frame with one UDP write() call.
%   udpSend(u, data, timestep)
%   info = udpSend(u, data, timestep)
%
%   magic(1), set by udpOpen, determines the header and payload format.
%   Every format shares 20 bytes (magic, session ID, timestep, chunk ID/count).

cfg = u.UserData;
magic = char(cfg.magic);

% Model-specific header and payload.
switch magic(1)
    case {'S','V'}
        % Data dimensions: [ny nx nz nv]
        dims = size(data,1:4);
        assert(ndims(data) <= 4, ...
            'S/V data must have at most 4 dimensions [ny nx nz nv].');
        
        header = headerField(magic, cfg.sessionid, frameid, dims, cfg.vspan);
        payload = quantisize(data, cfg.vspan);
    case {'P'}
        % Particle data: one particle per row.
        % Columns: [x y], [x y z], [x y vx vy], or [x y z vx vy vz].
        dims = size(data, 1:2);
        assert(ismember(dims(2), [2 3 4 6]), ...
            'P data must have 2, 3, 4, or 6 columns (pos/vel).');

        header = headerParticle(magic, cfg.sessionid, frameid, dims);
        payload = littleEndianBytes(single(data(:)));

    case {'C'}
        % Cellular automaton: [ny nx nz], nz = 1 for 2D.
        assert(ndims(data) <= 3, 'CA data must have at most 3 dimensions.');
        dims = size(data, 1:3);

        header = headerCellular(magic, cfg.sessionid, frameid, dims, cfg.nostates);
        payload = compress(data, cfg.nostates);

    case {'T'}
        error('T is reserved; its street-data format is not defined yet.');

    otherwise
        error('Unknown frame type: %s', magic);
end

% Shared chunking: replace the chunk fields in the prepared header.
headerSize = numel(header);
datagramSize = u.OutputDatagramSize;
payloadSize = datagramSize - headerSize;
assert(payloadSize > 0, 'Datagram size must exceed the %d-byte header.', headerSize);
chunkCount = ceil(numel(payload) / payloadSize);
assert(chunkCount <= double(intmax('uint32')), 'Too many chunks.');
header(17:20) = littleEndianBytes(uint32(chunkCount));

% All blocks except the last have exactly OutputDatagramSize bytes.
% MATLAB splits the single write() buffer along these boundaries.
buffer = zeros(1, numel(payload) + chunkCount * headerSize, 'uint8');
for k = 0:chunkCount-1
    first = k * payloadSize + 1;
    last = min((k + 1) * payloadSize, numel(payload));
    start = k * datagramSize + 1;

    header(13:16) = littleEndianBytes(uint32(k));
    buffer(start:start+headerSize-1) = header;
    buffer(start+headerSize:start+headerSize+last-first) = payload(first:last);
end

timer = tic;
write(u, buffer, 'uint8', cfg.address, cfg.port);
if nargout > 0
    info = struct('magic', string(magic), 'session_id', uint32(cfg.sessionid), ...
        'frame_id', uint32(frameid), ...
        'packets', chunkCount, 'payload_bytes', numel(payload), ...
        'wire_bytes', numel(buffer), 'seconds', toc(timer));
end
end

% ------------------------------------------------------------------------

function payload = quantisize(data, vspan)
% Quantize S/V data to uint8 using one fixed range for all components.
% Convert integer arrays first to avoid saturating integer arithmetic.
values = data(:);
if ~isfloat(values), values = double(values); end
payload = reshape(uint8(255 * min(max( ...
    (values - vspan(1)) / (vspan(2) - vspan(1)), 0), 1)), 1, []);
end

% ------------------------------------------------------------------------

function payload = compress(data, nostates)
% Pack CA states (0 to nostates-1) into uint8 bytes.

bits = 2^ceil(log2(max(1, ceil(log2(double(nostates))))));
perByte = 8 / bits;

values = uint8(data(:));
n = numel(values);
payload = zeros(ceil(n / perByte), 1, 'uint8');

for k = 0:perByte-1
    v = values(k+1:perByte:end);
    payload(1:numel(v)) = bitor(payload(1:numel(v)), ...
        bitshift(v, k * bits));
end
end

% ------------------------------------------------------------------------

function header = headerField(magic, sessionid, timestep, dims, vspan)
% S/V: 52 bytes = magic(4), session(4), frame(4), chunks(8), dims(16), vspan(16).
header = [uint8(magic), ...
    littleEndianBytes(uint32(sessionid)), ... % simulation session
    littleEndianBytes(uint32(timestep)), ...  % frame ID
    zeros(1, 4, 'uint8'), ...               % chunk index
    zeros(1, 4, 'uint8'), ...               % chunk count
    littleEndianBytes(uint32(dims)), ...    % [ny nx nz components]
    littleEndianBytes(double(vspan))];      % [vmin vmax]
end

% ------------------------------------------------------------------------

function header = headerParticle(magic, sessionid, timestep, dims)
% P: 28 bytes = magic(4), session(4), frame(4), chunks(8), dims(8).
header = [uint8(magic), ...
    littleEndianBytes(uint32(sessionid)), ... % simulation session
    littleEndianBytes(uint32(timestep)), ...  % frame ID
    zeros(1, 4, 'uint8'), ...               % chunk index
    zeros(1, 4, 'uint8'), ...               % chunk count
    littleEndianBytes(uint32(dims))];       % [nParticles nCoords]
end

% ------------------------------------------------------------------------

function header = headerCellular(magic, sessionid, timestep, dims, nostates)
% C: 33 bytes = magic(4), session(4), frame(4), chunks(8), dims(12), nostates(1).
header = [uint8(magic), ...
    littleEndianBytes(uint32(sessionid)), ... % simulation session
    littleEndianBytes(uint32(timestep)), ...  % frame ID
    zeros(1, 4, 'uint8'), ...                % chunk index
    zeros(1, 4, 'uint8'), ...                % chunk count
    littleEndianBytes(uint32(dims)), ...     % [ny nx nz]
    uint8(nostates)];                        % number of states
end

% ------------------------------------------------------------------------

function bytes = littleEndianBytes(values)
% Serialize multibyte header/payload values to a little-endian byte row.
bytes = reshape(typecast(values(:), 'uint8'), 1, []);
[~, ~, endian] = computer;
if endian == 'B'
    width = numel(bytes) / numel(values);
    bytes = reshape(flipud(reshape(bytes, width, [])), 1, []);
end
end

% ------------------------------------------------------------------------