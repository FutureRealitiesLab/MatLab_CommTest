function testProtocol()
%TESTPROTOCOL Check magic-driven UDP formats over MATLAB's local loopback socket.
%   Requires a working UDP port on the local machine.

rx = udpport('datagram', 'IPV4', 'LocalHost', '127.0.0.1');
port = rx.LocalPort;
tol = 1/255 + 1e-12;

A = reshape(linspace(-1, 1, 6*7), 6, 7);
u = udpOpen(magic="S2i0", port=port, vspan=[-1 1], datagramSize=100);
udpSend(u, A, 1);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "S2i0");
assert(isequal(size(B), size(A)) && max(abs(B(:)-A(:))) <= tol);
delete(u);

u = udpOpen(magic="S2s0", port=port, vspan=[-1 1], datagramSize=100);
udpSend(u, A, 2);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "S2s0");
assert(isequal(info.dims, [6 7 1 1]));
assert(max(abs(B(:)-A(:))) <= tol);
delete(u);

V = cat(4, A, -A);
u = udpOpen(magic="V2q0", port=port, vspan=[-1 1], datagramSize=100);
udpSend(u, V, 2);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "V2q0");
assert(isequal(info.dims, [6 7 1 2]));
assert(max(abs(B(:)-V(:))) <= tol);
delete(u);

D = reshape(linspace(-1,1,5*6*4),5,6,4);
u = udpOpen(magic="S3i0", port=port, vspan=[-1 1], datagramSize=100);
udpSend(u, D, 3);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "S3i0");
assert(isequal(info.dims, [5 6 4 1]));
assert(max(abs(B(:)-D(:))) <= tol);
delete(u);

F = cat(4, D, -D, 0.5*D);
u = udpOpen(magic="V3q0", port=port, vspan=[-1 1], datagramSize=100);
udpSend(u, F, 4);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "V3q0");
assert(isequal(info.dims, [5 6 4 3]));
assert(max(abs(B(:)-F(:))) <= tol);
delete(u);

P = single([0.1 0.2 0.3; -1 2 3; 1e-3 -4 9]);
u = udpOpen(magic="P3p0", port=port, datagramSize=100);
udpSend(u, P, 5);
[B, info] = udpReceive(rx, 2);
assert(info.status == "received" && info.magic == "P3p0");
assert(isequal(B, P));
delete(u);

Cp = uint8(mod(reshape(0:41, 6, 7), 4));
for magic = ["C2m2", "C2m1", "C2m0", "C2i0"]
    u = udpOpen(magic=magic, port=port, nostates=4, datagramSize=100);
    udpSend(u, Cp, 6);
    [B, info] = udpReceive(rx, 2);
    assert(info.status == "received" && info.magic == magic);
    assert(info.nostates == 4 && isequal(B, Cp));
    delete(u);
end

for nostates = [1 2 3 5 17 200]
    C = uint8(mod(reshape(0:34, 5, 7), nostates));
    u = udpOpen(magic="C2i0", port=port, nostates=uint8(nostates));
    udpSend(u, C, 8);
    [B, info] = udpReceive(rx, 2);
    assert(info.status == "received" && info.nostates == nostates);
    assert(isequal(B, C));
    delete(u);
end

% Alternating data in one session: one frame per call, newest per magic.
uS = udpOpen(magic="S3i0", port=port, sessionid=777, vspan=[-1 1], datagramSize=100);
uV = udpOpen(magic="V3q0", port=port, sessionid=777, vspan=[-1 1], datagramSize=100);
udpSend(uS, D, 1);
udpSend(uV, F, 2);
udpSend(uS, D, 3);
[~, info] = udpReceive(rx, 2);
assert(info.magic == "V3q0" && info.frame_id == 2 && info.pending == 1);
[~, info] = udpReceive(rx, 2);
assert(info.magic == "S3i0" && info.frame_id == 3);
delete(uS); delete(uV);

% Two particle species with different frame IDs.
u0 = udpOpen(magic="P3p0", port=port, sessionid=778, datagramSize=100);
u1 = udpOpen(magic="P3p1", port=port, sessionid=778, datagramSize=100);
udpSend(u0, P, 1);
udpSend(u1, 2*P, 2);
[B, info] = udpReceive(rx, 2);
assert(info.magic == "P3p0" && isequal(B, P));
[B, info] = udpReceive(rx, 2);
assert(info.magic == "P3p1" && isequal(B, 2*P));
delete(u0); delete(u1);

fprintf('All UDP loopback checks passed.\n');
end
