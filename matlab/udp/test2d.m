function test2d()
%TEST2D Stream a moving 2D density field to udp_listen/Godot.

address = "127.0.0.1"; % Use the receiver's IP for two computers.
port = 4242;
fps = 20;
x = linspace(-2, 2, 192);
y = linspace(-1.5, 1.5, 128);
[Y, X] = ndgrid(y, x);

u = udpOpen(magic="S2i0", address=address, port=port, vspan=[-1 1]);
started = tic;
step = 0;
fprintf('Sending 2D field to %s:%d; stop with Ctrl+C.\n', address, port);
while true
    frameTimer = tic;
    t = toc(started);
    field = sin(7 * hypot(X, Y) - 3*t) .* exp(-0.5 * (X.^2 + Y.^2));
    info = udpSend(u, field, step);
    fprintf('step %u | %d datagrams | %.1f kB | %.2f ms\n', ...
        info.frame_id, info.packets, info.wire_bytes/1024, info.seconds*1000);
    step = step + 1;
    pause(max(0, 1/fps - toc(frameTimer)));
end
end
