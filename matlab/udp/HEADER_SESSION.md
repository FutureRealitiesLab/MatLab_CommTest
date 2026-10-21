# UDP session ID

The session ID is part of the common 20-byte header and is described in
[PROTOCOL.md](PROTOCOL.md). `udpOpen` creates a new session ID per simulation
run; receivers reset their state when they see an unknown session ID and
remember 32 retired IDs to ignore late packets of previous runs.
