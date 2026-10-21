# Typed UDP simulation frames

Every datagram starts with a four-character ASCII **magic** that selects the
data format and the visualization. The **first 20 bytes** are identical for all
types:

| Offset | Bytes | Type | Meaning |
|---:|---:|---|---|
| 0 | 4 | ASCII | Magic, e.g. `S3i3`, `V2q0`, `P2p1`, `C2m2` |
| 4 | 4 | uint32 | Session ID (unique per `udpOpen`; must change when a simulation restarts) |
| 8 | 4 | uint32 | Frame ID (timestep) |
| 12 | 4 | uint32 | Chunk index (zero-based) |
| 16 | 4 | uint32 | Number of chunks in the frame |

Every multi-byte field is **little-endian**. Payloads are serialized in
MATLAB **column-major** order (`data(:)`). One UDP datagram contains one
complete header and one nonempty chunk.

## Magic

| Byte | Meaning |
|---:|---|
| 1 | Data type: `S` scalar field, `V` vector field, `P` particles, `C` cellular automaton, `T` traffic (reserved) |
| 2 | Spatial dimension: `2` or `3` |
| 3 | Visualization (see below) |
| 4 | Extra (see below) |

**Only byte 1 selects header and payload format.** Bytes 2 to 4 select the
visualization and its parameters; receivers may ignore unknown values.

| Magic | Visualization |
|---|---|
| `S2i.` | Image |
| `S2s.` | Height surface (height along z, up to half the box) |
| `S3i<n>` | `n` slices along z; `S3i0` shows the three orthogonal mid slices (xy, xz, yz) |
| `S3v.` | Volume rendering |
| `V2q<k>`, `V3q<k>` | Arrows; `k` = 0 autoscale, `k` > 0 arrow of magnitude `max(abs(vspan))` is `k` cells long |
| `P2p<x>`, `P3p<x>` | Particles of species `x` (own layer and color); velocity arrows if the data has 4 or 6 columns |
| `C2i.` | Image of the states |
| `C2m<0\|1\|2>` | States mapped on plane / sphere / torus |

Viewers draw each layer (`magic(1:3)`, for `P` `magic(1:4)`) into one shared
plot box `[0 1]^3` and update it in place. Data are fitted into the box with
one uniform scale factor (no distortion). Particle positions are normalized
to 0..1.

## S/V: scalar and vector grid fields

Header length: **52 bytes**.

| Offset | Bytes | Type | Meaning |
|---:|---:|---|---|
| 20 | 16 | uint32[4] | `[ny nx nz nv]` |
| 36 | 8 | float64 | `vmin` |
| 44 | 8 | float64 | `vmax` |
| 52 | variable | uint8[] | Quantized field values |

`S` requires `nv = 1`. `V` requires `nv = 2` (with `nz = 1`) for `V2` and
`nv = 3` for `V3`. Quantization (one range for all components):

```text
q = uint8(255 * clamp((value - vmin)/(vmax - vmin), 0, 1))
value_approx = vmin + (double(q)/255) * (vmax - vmin)
```

The input must be finite; `vmax > vmin`. Vector data use `[ny nx nz nv]`,
so a 2D vector field is `[ny nx 1 2]`.

## P: particles

Header length: **28 bytes**.

| Offset | Bytes | Type | Meaning |
|---:|---:|---|---|
| 20 | 8 | uint32[2] | `[nParticles nCoords]`, `nCoords` = 2, 3, 4 or 6 |
| 28 | variable | float32[] | Particle matrix, one particle per row |

Columns: `[x y]`, `[x y z]`, `[x y vx vy]` or `[x y z vx vy vz]`.
Two species are sent as two frames with different magic (`P2p0`, `P2p1`) and
different frame IDs.

## C: cellular automata

Header length: **33 bytes**.

| Offset | Bytes | Type | Meaning |
|---:|---:|---|---|
| 20 | 12 | uint32[3] | `[ny nx nz]`, `nz = 1` in 2D |
| 32 | 1 | uint8 | `nostates` |
| 33 | variable | uint8[] | Bit-packed states |

Bits per state:

```text
bits = 2^ceil(log2(max(1, ceil(log2(nostates)))))     % 1, 2, 4 or 8
```

Cells are packed in column-major order, low-order bits first; every value is
an integer in `[0, nostates-1]`.

`T` is reserved for traffic data; its payload schema is not defined yet.
A receiver must ignore unknown magics rather than guess a format.

## Chunking and reception

`udpSend` constructs `[header chunk][header chunk]...` in one `uint8` vector.
All blocks except the last are exactly `u.OutputDatagramSize` bytes long.
MATLAB's single `write()` call splits this vector into datagrams along those
boundaries. Each datagram repeats all metadata.

A receiver reconstructs frames whose session ID, frame ID, magic and chunk
count match:

- A new session ID means a restarted simulation; all state is discarded and
  late packets of retired sessions are ignored.
- The **frame ID identifies a frame**. Within a session only IDs greater than
  the last completed frame are accepted. A sender that alternates datasets
  must therefore also alternate the frame IDs (for example 1, 3, 5 density and
  2, 4, 6 vectors); a changed magic alone is not enough.
- Complete frames are queued; only the newest frame per magic is kept, and
  one frame is delivered per call.

`udpReceive` (MATLAB) and `godot/udp_receiver.gd` implement this; `udpDrawnow`
and `godot/scene_view.gd` render the frames. `udpTest` sends every magic for
five seconds each so that a viewer can be checked.
