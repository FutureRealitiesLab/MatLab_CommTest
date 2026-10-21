function h = udpDrawnow(d, p, t, h)
%UDPDRAWNOW MATLAB diagnostic visualization of reconstructed model data.
%   h = udpDrawnow(data, info, timestep, h)
%
%   info.magic selects the display; the handle h allows efficient updates.
%   magic(1) = data type, magic(2) = dimension, magic(3) = visualization,
%   magic(4) = extra (see udpOpen).
%
%   Different magics draw into one shared axes. Each layer (S2i, S3i, V3q,
%   P2p0, ...) is updated in place and left untouched by other layers.
%   All data are fitted uniformly (no distortion) into the plot box.
%
%   S2i imagesc | S2s surf | S3i<n> n slices along z, S3i0 three orthogonal
%   mid slices | S3v volshow (needs its own viewer in the figure)
%   V2q/V3q<k> quiver, k=0 auto scale, k>0 arrow length k cells
%   P2p<x> particles of species x (+ velocity arrows if 4/6 columns)
%   C2i imagesc | C2m<0|1|2> CA on plane/sphere/torus

box = [0 1 0 1 0 1];    % [xmin xmax ymin ymax zmin zmax]

if nargin < 2 || isempty(p), p = struct(); end
if nargin < 3 || isempty(t), t = 0; end
if nargin < 4, h = []; end
if isfield(p, 'magic'), magic = char(p.magic); else, magic = 'S2i0'; end
% Transmitted dims keep trailing singletons that size(d) would omit.
if isfield(p, 'dims') && ~isempty(p.dims)
    dims = p.dims;
    d = reshape(d, dims);
else
    dims = size(d);
end
vspan = [0 1];
if isfield(p, 'vspan') && numel(p.vspan) == 2 && p.vspan(2) > p.vspan(1)
    vspan = p.vspan;
end
sessionId = [];
if isfield(p, 'session_id'), sessionId = p.session_id; end

if isstruct(h) && isfield(h, 'figure') && isgraphics(h.figure)
    fig = h.figure;
else
    fig = figure('Name', 'UDP simulation viewer', 'NumberTitle', 'off');
end
if ~isstruct(h) || ~isfield(h, 'axes') || ~isgraphics(h.axes)
    ax = axes('Parent', fig);
    hold(ax, 'on'); box_on(ax); applyBox(ax, box);
    view(ax, 2);
    h = struct('figure', fig, 'axes', ax, 'layers', struct(), 'session', []);
end
ax = h.axes;

% A restarted simulation drops every layer.
if ~isequal(h.session, sessionId)
    h = clearLayers(h);
    h.session = sessionId;
end

key = layerKey(magic);
if magic(1) == 'P'
    sig = dims(2);         % particle count may change every frame
else
    sig = dims;
end
rebuild = ~isfield(h.layers, key) || ~strcmp(h.layers.(key).magic, magic) ...
    || ~isequal(h.layers.(key).sig, sig) || ~all(isvalid(h.layers.(key).plot));
if rebuild
    if isfield(h.layers, key)
        old = h.layers.(key).plot;
        delete(old(isvalid(old)));
    end
    h.layers.(key) = struct('magic', magic, 'sig', sig, 'plot', []);
end
plt = h.layers.(key).plot;

switch magic(1)
    case 'S'
        switch magic(2:3)
            case '2i', plt = drawImage(ax, plt, rebuild, d(:,:,1,1), dims, box);
            case '2s', plt = drawSurface(ax, plt, rebuild, d(:,:,1,1), dims, box, vspan);
            case '3i', plt = drawSlices(ax, plt, rebuild, d(:,:,:,1), dims, box, vspan, magic);
            case '3v', plt = drawVolume(h.figure, plt, rebuild, d(:,:,:,1));
            otherwise, error('No visualization defined for magic %s.', magic);
        end
        setClim(ax, vspan);
    case 'V'
        if magic(3) ~= 'q', error('No visualization defined for magic %s.', magic); end
        plt = drawQuiver(ax, plt, rebuild, d, dims, box, vspan, magic);
    case 'P'
        if magic(3) ~= 'p', error('No visualization defined for magic %s.', magic); end
        plt = drawParticles(ax, plt, rebuild, d, box, magic);
    case 'C'
        nostates = 2;
        if isfield(p, 'nostates') && ~isempty(p.nostates), nostates = p.nostates; end
        d = double(d(:,:,1));
        switch magic(2:3)
            case '2i', plt = drawImage(ax, plt, rebuild, d, dims, box);
            case '2m', plt = drawMapped(ax, plt, rebuild, d, box, magic);
            otherwise, error('No visualization defined for magic %s.', magic);
        end
        setClim(ax, [0 max(1, nostates - 1)]);
    otherwise
        error('No visualization defined for magic %s.', magic);
end

if rebuild
    applyBox(ax, box);
    if magic(1) ~= 'S' || magic(3) ~= 'v'
        colorbarIfScalar(ax, magic);
    end
end
h.layers.(key).plot = plt;

caption = sprintf('%s | timestep %u', magic, uint32(t));
if isfield(p, 'queued')
    caption = sprintf('%s | queue %d', caption, p.queued);
end
title(ax, caption);
drawnow limitrate;
end

% ------------------------------------------------------------------------

function key = layerKey(magic)
% One layer per magic(1:3); particle species (magic(4)) get their own layer.
if magic(1) == 'P'
    key = magic(1:4);
else
    key = magic(1:3);
end
key = matlab.lang.makeValidName(key);
end

function h = clearLayers(h)
names = fieldnames(h.layers);
for k = 1:numel(names)
    old = h.layers.(names{k}).plot;
    delete(old(isvalid(old)));
end
h.layers = struct();
end

function box_on(ax)
box(ax, 'on'); grid(ax, 'on');
end

function applyBox(ax, box)
xlim(ax, box(1:2)); ylim(ax, box(3:4)); zlim(ax, box(5:6));
daspect(ax, [1 1 1]);
end

function setClim(ax, lim)
if numel(lim) == 2 && lim(2) > lim(1), clim(ax, lim); end
end

function colorbarIfScalar(ax, magic)
if any(magic(1) == 'SC'), colorbar(ax); end
end

% ------------------------------------------------------------------------

function [s, off] = fitBox(box, ext, nd)
% One uniform scale s fits ext (first nd axes) into the box, centered.
span = box(2:2:6) - box(1:2:5);
ext = ext(1:nd);
s = min(span(1:nd) ./ ext);
off = box(1:2:5);
off(1:nd) = off(1:nd) + (span(1:nd) - s * ext) / 2;
end

function c = centers(off, s, n)
c = off + s * ((1:n) - 0.5);
end

% ------------------------------------------------------------------------

function plt = drawImage(ax, plt, rebuild, f, dims, box)
if rebuild
    ny = dims(1); nx = dims(2);
    [s, off] = fitBox(box, [nx ny], 2);
    plt = imagesc(ax, centers(off(1), s, nx), centers(off(2), s, ny), f);
    set(ax, 'YDir', 'normal');
else
    plt.CData = f;
end
end

function plt = drawSurface(ax, plt, rebuild, f, dims, box, vspan)
% Height is the field normalized by vspan, up to half the box height.
z = box(5) + 0.5 * (box(6) - box(5)) * ...
    min(max((f - vspan(1)) / (vspan(2) - vspan(1)), 0), 1);
if rebuild
    ny = dims(1); nx = dims(2);
    [s, off] = fitBox(box, [nx ny], 2);
    plt = surf(ax, centers(off(1), s, nx), centers(off(2), s, ny), z, f, ...
        'EdgeColor', 'none');
    view(ax, 3);
else
    plt.ZData = z; plt.CData = f;
end
end

% ------------------------------------------------------------------------

function plt = drawSlices(ax, plt, rebuild, f, dims, box, ~, magic)
n = str2double(magic(4));
if isnan(n), n = 0; end
if rebuild
    ny = dims(1); nx = dims(2); nz = dims(3);
    assert(nx >= 2 && ny >= 2 && (n > 0 || nz >= 2), ...
        'Slices need at least two cells per displayed axis.');
    [s, off] = fitBox(box, [nx ny nz], 3);
    x = centers(off(1), s, nx); y = centers(off(2), s, ny);
    z = centers(off(3), s, nz);
    if n == 0
        % [index dimension, index]: xy at mid z, yz at mid x, xz at mid y.
        specs = [3 round(nz/2); 2 round(nx/2); 1 round(ny/2)];
    else
        k = unique(min(max(round(((1:n) - 0.5) * nz / n), 1), nz));
        specs = [3 * ones(numel(k), 1), k(:)];
    end
    plt = gobjects(1, size(specs, 1));
    for j = 1:size(specs, 1)
        k = specs(j, 2);
        switch specs(j, 1)
            case 3
                [X, Y] = meshgrid(x, y); Z = z(k) * ones(ny, nx);
            case 2
                [Y, Z] = ndgrid(y, z); X = x(k) * ones(ny, nz);
            case 1
                [X, Z] = ndgrid(x, z); Y = y(k) * ones(nx, nz);
        end
        plt(j) = surf(ax, X, Y, Z, sliceData(f, specs(j, :)), ...
            'EdgeColor', 'none', 'FaceColor', 'interp');
        plt(j).UserData = specs(j, :);
    end
    if numel(plt) > 1, set(plt, 'FaceAlpha', 0.5); end
    view(ax, 3);
else
    for j = 1:numel(plt)
        plt(j).CData = sliceData(f, plt(j).UserData);
    end
end
end

function c = sliceData(f, spec)
switch spec(1)
    case 3, c = f(:, :, spec(2));
    case 2, c = squeeze(f(:, spec(2), :));
    case 1, c = squeeze(f(spec(2), :, :));
end
end

function plt = drawVolume(fig, plt, rebuild, f)
% volshow has its own viewer, so it cannot share the axes.
if rebuild
    plt = volshow(f, 'Parent', fig);
else
    plt.Data = f;
end
end

% ------------------------------------------------------------------------

function plt = drawQuiver(ax, plt, rebuild, d, dims, box, vspan, magic)
k = str2double(magic(4));
if isnan(k), k = 0; end
vmax = max(abs(vspan));
if vmax == 0, vmax = 1; end
ny = dims(1); nx = dims(2); nz = dims(3);
if magic(2) == '2'
    stride = [max(1, ceil(ny / 25)), max(1, ceil(nx / 25))];
    iy = 1:stride(1):ny; ix = 1:stride(2):nx;
    [s, off] = fitBox(box, [nx ny], 2);
    U = d(iy, ix, 1, 1); V = d(iy, ix, 1, 2);
else
    stride = [max(1, ceil(ny / 12)), max(1, ceil(nx / 12)), max(1, ceil(nz / 8))];
    iy = 1:stride(1):ny; ix = 1:stride(2):nx; iz = 1:stride(3):nz;
    [s, off] = fitBox(box, [nx ny nz], 3);
    U = d(iy, ix, iz, 1); V = d(iy, ix, iz, 2); W = d(iy, ix, iz, 3);
end
% k > 0: an arrow of magnitude vmax is k grid spacings long.
args = {'AutoScale', 'on'};
f = 1;
if k > 0
    args = {'AutoScale', 'off'};
    f = k * s * max(stride) / vmax;
end
if magic(2) == '2'
    if rebuild
        [X, Y] = meshgrid(centers(off(1), s, nx), centers(off(2), s, ny));
        plt = quiver(ax, X(iy, ix), Y(iy, ix), f * U, f * V, args{:});
    else
        plt.UData = f * U; plt.VData = f * V;
    end
else
    if rebuild
        [Y, X, Z] = ndgrid(centers(off(2), s, ny), centers(off(1), s, nx), ...
            centers(off(3), s, nz));
        plt = quiver3(ax, X(iy, ix, iz), Y(iy, ix, iz), Z(iy, ix, iz), ...
            f * U, f * V, f * W, args{:});
        view(ax, 3);
    else
        plt.UData = f * U; plt.VData = f * V; plt.WData = f * W;
    end
end
end

% ------------------------------------------------------------------------

function plt = drawParticles(ax, plt, rebuild, d, box, magic)
% Positions are normalized to 0..1. Columns: [x y (z)] then optional velocities.
nc = size(d, 2);
nd = 2 + (nc == 3 || nc == 6);
[s, off] = fitBox(box, ones(1, nd), nd);
pos = off(1:nd) + s * double(d(:, 1:nd));
vel = double(d(:, nd+1:end));

species = str2double(magic(4));
if isnan(species), species = 0; end
co = ax.ColorOrder;
col = co(mod(species, size(co, 1)) + 1, :);

if rebuild
    if nd == 3
        plt = scatter3(ax, pos(:,1), pos(:,2), pos(:,3), 12, col, 'filled');
        view(ax, 3);
    else
        plt = scatter(ax, pos(:,1), pos(:,2), 12, col, 'filled');
    end
    if ~isempty(vel)
        if nd == 3
            plt(2) = quiver3(ax, pos(:,1), pos(:,2), pos(:,3), ...
                vel(:,1), vel(:,2), vel(:,3), 'Color', col);
        else
            plt(2) = quiver(ax, pos(:,1), pos(:,2), vel(:,1), vel(:,2), ...
                'Color', col);
        end
    end
else
    plt(1).XData = pos(:,1); plt(1).YData = pos(:,2);
    if nd == 3, plt(1).ZData = pos(:,3); end
    if ~isempty(vel)
        plt(2).XData = pos(:,1); plt(2).YData = pos(:,2);
        plt(2).UData = vel(:,1); plt(2).VData = vel(:,2);
        if nd == 3
            plt(2).ZData = pos(:,3); plt(2).WData = vel(:,3);
        end
    end
end
end

% ------------------------------------------------------------------------

function plt = drawMapped(ax, plt, rebuild, c, box, magic)
% C2m<0|1|2>: CA grid on plane / sphere / torus inside the box.
if ~rebuild
    plt.CData = c;
    return;
end
[ny, nx] = size(c);
span = box(2:2:6) - box(1:2:5);
mid = (box(1:2:5) + box(2:2:6)) / 2;
rmax = min(span) / 2;
switch magic(4)
    case '0'
        [s, off] = fitBox(box, [nx ny], 2);
        X = centers(off(1), s, nx); Y = centers(off(2), s, ny);
        Z = box(5) * ones(ny, nx);
    case '1'
        [phi, theta] = meshgrid(linspace(0, 2*pi, nx), linspace(0, pi, ny));
        X = mid(1) + rmax * sin(theta) .* cos(phi);
        Y = mid(2) + rmax * sin(theta) .* sin(phi);
        Z = mid(3) + rmax * cos(theta);
    case '2'
        [phi, theta] = meshgrid(linspace(0, 2*pi, nx), linspace(0, 2*pi, ny));
        major = 0.7 * rmax; minor = 0.3 * rmax;
        X = mid(1) + (major + minor * cos(theta)) .* cos(phi);
        Y = mid(2) + (major + minor * cos(theta)) .* sin(phi);
        Z = mid(3) + minor * sin(theta);
    otherwise
        error('C2m needs magic(4) = 0, 1 or 2.');
end
plt = surf(ax, X, Y, Z, c, 'EdgeColor', 'none');
view(ax, 3);
end
