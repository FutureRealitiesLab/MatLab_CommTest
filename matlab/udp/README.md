# MATLAB -> Godot/VR: UDP simulation data

The sender has two public functions:

```matlab
u = udpOpen(magic="S2i0", address="127.0.0.1", port=4242, ...
            vspan=[-1 1], nostates=2, datagramSize=65000);
udpSend(u, data, frameid);
```

`u` is directly the MATLAB `udpport` object. It stores the magic,
destination, session ID, `vspan` and `nostates` in `u.UserData`. `frameid` is
sent as a `uint32` frame ID. `udpSend` builds all datagrams in a buffer and
calls `write()` **once per frame**. No internal frame counter is needed.

`datagramSize` means **total UDP payload bytes**, including the application
header (52 bytes for S/V, 28 for P, 33 for C). It defaults to 65000 and is
clamped to 1000..65000. Large datagrams reduce MATLAB call overhead but often
cause IPv4 fragmentation on real networks. Benchmark on the target LAN/WLAN.

## Magic

The four-character `magic` selects data format and visualization (details in
[PROTOCOL.md](PROTOCOL.md)). Byte 1 alone selects the wire format.

| `magic` | Data sent | MATLAB input |
|---|---|---|
| `S2i.` | scalar field as image | `[ny nx]` |
| `S2s.` | scalar field as height surface | `[ny nx]` |
| `S3i<n>` | scalar field, `n` slices along z (`0`: three mid slices) | `[ny nx nz]` |
| `S3v.` | scalar field as volume | `[ny nx nz]` |
| `V2q<k>` | 2D vectors as arrows | `[ny nx 1 2]` |
| `V3q<k>` | 3D vectors as arrows | `[ny nx nz 3]` |
| `P2p<x>`, `P3p<x>` | particles of species `x` | `[N 2]`, `[N 3]`, `[N 4]` or `[N 6]` (with velocities) |
| `C2i.` | cellular automaton as image | `[ny nx]` |
| `C2m<0\|1\|2>` | cellular automaton on plane / sphere / torus | `[ny nx]` |
| `T...` | reserved for traffic | not implemented yet |

`vspan=[vmin vmax]` applies to all S/V components; values are clipped and
quantized to 0..255. Particle data are sent as unquantized `float32`
(positions normalized to 0..1). CA input is packed to 1, 2, 4 or 8 bits per
state according to `nostates`.

**Frame IDs.** The frame ID identifies a frame. When one simulation sends
several datasets (for example density and vectors), each dataset needs its
own, increasing frame ID; a different magic alone is not enough.

## Viewers

MATLAB: in one session run `udpListen`, in another one a sender such as
`test2d`, `test3d` or `udpTest`. `udpTest` sends every magic for five seconds
so that the viewers can be checked.

```text
udpReceive(u)                 -> decoded data and metadata only
udpDrawnow(data, info, t, h)  -> MATLAB visualization only
```

`udpListen` connects these functions and keeps the display handle `h`
between frames. `udpReceive` returns one queued frame per call (newest per
magic). `udpDrawnow` draws each magic as its own layer in a shared plot box
and updates it in place.

Godot: open the project in [../../godot](../../godot) with Godot 4.7; it listens on
port 4242 (IPv4) and renders the same magics. Keys: `C` colormap, `F3`
statistics. `godot/selftest.gd` checks the receiver without a network.

`testProtocol` runs MATLAB loopback checks for all formats and the frame
queue.

## Operational notes

- For two computers, set `address` in the sender to the receiver's IPv4
  address and allow inbound UDP port 4242 in the receiver's firewall.
- Each `udpOpen` gets a new session ID, so a restarted simulation is accepted
  immediately by the viewers; no listener restart is needed.
- Only one program can use port 4242: stop `udpListen` before starting the
  Godot viewer (or change the port).
- UDP can lose or reorder datagrams. Only complete frames are displayed.
- Closing the listener figure ends its loop. Test senders stop with Ctrl+C.
- To release an interactive `udpport` object immediately, use `delete(u)`;
  `clear u` also drops the workspace reference.
