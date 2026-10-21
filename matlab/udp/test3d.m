function test3d()
%TEST3D Stream a moving 3D density field to udp_listen/Godot.

address = "127.0.0.1"; % Use the receiver's IP for two computers.
port = 4242;
fps = 10;
x = linspace(-1, 1, 48);
y = linspace(-1, 1, 40);
z = linspace(-1, 1, 32);
[Y, X, Z] = ndgrid(y, x, z);

u = udpOpen(magic="S3i0", address=address, port=port, vspan=[0 1]);
started = tic;
step = 0;
fprintf('Sending 3D field to %s:%d; stop with Ctrl+C.\n', address, port);
while true
    frameTimer = tic;
    t = toc(started);
    center = [0.45*sin(0.8*t), 0.35*cos(1.1*t), 0.3*sin(0.6*t+0.7)];
    field = exp(-((X-center(1)).^2 + (Y-center(2)).^2 + ...
                  (Z-center(3)).^2)/0.12);
    info = udpSend(u, field, step);
    fprintf('step %u | %d datagrams | %.1f kB | %.2f ms\n', ...
        info.frame_id, info.packets, info.wire_bytes/1024, info.seconds*1000);
    step = step + 1;
    pause(max(0, 1/fps - toc(frameTimer)));
end
end
