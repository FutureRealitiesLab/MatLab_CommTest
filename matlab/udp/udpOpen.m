function u = udpOpen(cfg)
%UDPOPEN Configure a UDP sender for simulation data.
%   u = udpOpen(magic="S2i0", address="127.0.0.1", port=4242, ...
%               vspan=[0 1], datagramSize=65000)
%
%   The returned u is a udpport object. Model options are in u.UserData.
%   datagramSize includes the application header and field payload.

% MAGIC: 4-character identifier defining data type and visualization.
%
% Byte 1: Data type
%   S = Scalar field (LG, LB, e.g. density)      = float (quantisize)
%   V = Vector field (LG, LB, e.g. velocity)     = float (quantisize)
%   C = Cellular automaton (CA, e.g. states)     = uint8 (compress)
%   P = Particle data (MD, positions/velocities) = float (single)
%   T = Traffic data
%
% Byte 2: Spatial dimension
%   2 = 2D
%   3 = 3D
%
% Byte 3: Visualization
%   i = Image (imagesc via slices, no slices via Byte 4)
%   s = Height surface (surf, only 2D)
%   v = Fog / volume rendering (volshow)
%   q = Vector arrows (quiver / quiver3)
%   p = Particles (scatter / scatter3)
%   m = 2D data mapped on 0/1/2 = plane/sphere/torus (Byte 4)
%
% Byte 4: Extra

arguments
    cfg.magic (1,1) string = "S2i1"
    cfg.address (1,1) string = "127.0.0.1"
    % cfg.address (1,1) string = "149.0.0.1"
    cfg.port (1,1) double {mustBeInteger, mustBePositive} = 4242
    cfg.datagramSize (1,1) double {mustBeInteger, mustBePositive} = 65000
    cfg.sessionid (1,1) double {mustBeInteger, mustBePositive} = ...
        randi(RandStream('mt19937ar','Seed','shuffle'), 2^32-1);
    cfg.vspan (1,2) double = [0 1]
    cfg.nostates (1,1) uint8 = 2
end

assert(strlength(cfg.magic) == 4, 'magic must contain exactly four characters.');
assert(cfg.port <= 65535, 'UDP port must be <= 65535.');

u = udpport('datagram', 'IPV4');
% IPv4 UDP payload limit: 65535 - 20 (IP) - 8 (UDP) = 65507 bytes.
u.OutputDatagramSize = min(65000, max(1000, cfg.datagramSize));

cfg = rmfield(cfg, 'datagramSize');
u.UserData = cfg;
end
