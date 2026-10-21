function udpListen(address, port)
%UDPLISTEN Receive simulation data and pass it to myDrawnow.
%   udpListen()                   listens on 0.0.0.0:4242
%   udpListen(address, port)      specifies local bind address/port.

if nargin < 1 || isempty(address), address = '0.0.0.0'; end
if nargin < 2 || isempty(port), port = 4242; end

u = udpport('datagram', 'IPV4', 'LocalHost', address, 'LocalPort', port);
fig = figure('Name', sprintf('UDP listener :%d', port), 'NumberTitle', 'off');
h = struct('figure', fig);

fprintf('Listening on %s:%d. Close the figure to stop.\n', address, port);
while isgraphics(fig)
    [data, info] = udpReceive(u);
    if info.status == "received"
        h = udpDrawnow(data, info, info.frame_id, h);
    else
        drawnow limitrate; % Keep figure responsive when no data arrive.
    end
end
end
