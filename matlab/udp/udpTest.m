function udpTest(address, port, seconds)
%UDPTEST Send every magic variant for a fixed time so udpListen can show it.
%   udpTest()                          % 127.0.0.1:4242, 5 s per case
%   udpTest(address, port, seconds)
%
%   Cases with several magics alternate between them; every frame gets a new
%   frame ID, as the receiver identifies frames by ID.

if nargin < 1 || isempty(address), address = "127.0.0.1"; end
if nargin < 2 || isempty(port), port = 4242; end
if nargin < 3 || isempty(seconds), seconds = 5; end
fps = 10;
nostates = 5;

cases = { ...
    "S2i0", "S2s0", "S3i0", "S3i3", ...
    "V2q0", "V2q3", "V3q0", "V3q2", ...
    "P2p0", "P3p0", ...
    "C2i0", "C2m0", "C2m1", "C2m2", ...
    ["S3i3" "V3q0"], ["S2i0" "V2q0"], ["P2p0" "P2p1"]};

frameId = 0;
for c = 1:numel(cases)
    magics = cases{c};
    session = randi(2^31 - 1);
    senders = cell(1, numel(magics));
    for k = 1:numel(magics)
        senders{k} = udpOpen(magic=magics(k), address=address, port=port, ...
            sessionid=session, vspan=[-1 1], nostates=nostates);
    end
    fprintf('Case %d/%d: %s for %g s\n', c, numel(cases), strjoin(magics, ' + '), seconds);

    started = tic;
    while toc(started) < seconds
        frameTimer = tic;
        t = toc(started);
        for k = 1:numel(magics)
            frameId = frameId + 1;
            udpSend(senders{k}, makeData(char(magics(k)), t, nostates), frameId);
        end
        pause(max(0, 1/fps - toc(frameTimer)));
    end
    cellfun(@delete, senders);
end
fprintf('udpTest finished.\n');
end

% ------------------------------------------------------------------------

function data = makeData(magic, t, nostates)
% Synthetic moving data for one magic; sizes stay small for one datagram burst.
switch magic(1)
    case 'S'
        if magic(2) == '2'
            [Y, X] = ndgrid(linspace(-1, 1, 96), linspace(-1, 1, 128));
            data = sin(6 * hypot(X, Y) - 3 * t) .* exp(-(X.^2 + Y.^2));
        else
            [Y, X, Z] = ndgrid(linspace(-1, 1, 32), linspace(-1, 1, 40), linspace(-1, 1, 24));
            c = [0.5*sin(t), 0.4*cos(1.3*t), 0.3*sin(0.7*t)];
            data = exp(-((X-c(1)).^2 + (Y-c(2)).^2 + (Z-c(3)).^2) / 0.12);
        end
    case 'V'
        if magic(2) == '2'
            [Y, X] = ndgrid(linspace(-1, 1, 32), linspace(-1, 1, 48));
            data = cat(4, -Y * cos(t), X * cos(t));
        else
            [Y, X, Z] = ndgrid(linspace(-1, 1, 12), linspace(-1, 1, 12), linspace(-1, 1, 8));
            data = cat(4, -Y, X, 0.5 * sin(3*Z + t));
        end
    case 'P'
        % Positions in 0..1, then velocities (time derivative); species = magic(4).
        % A circular orbit with a radial oscillation running along the ring.
        species = str2double(magic(4));
        s = linspace(0, 2*pi, 150).';
        radius = 0.15 + 0.1 * species;
        wave = 5 * s + 2 * t;
        r = radius * (1 + 0.3 * sin(wave));
        dr = radius * 0.6 * cos(wave);
        e = [cos(s + t), sin(s + t)];
        pos = 0.5 + r .* e;
        vel = 0.3 * (dr .* e + r .* [-e(:,2), e(:,1)]);
        if magic(2) == '3'
            pos(:, 3) = 0.5 + 0.2 * sin(2*s + species + t);
            vel(:, 3) = 0.3 * 0.2 * cos(2*s + species + t);
        end
        data = [pos, vel];
    case 'C'
        [Y, X] = ndgrid(1:60, 1:80);
        data = uint8(mod(floor((X + Y) / 8 + 3 * t), nostates));
end
end
