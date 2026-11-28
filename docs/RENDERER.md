# The wgpu renderer

A second renderer beside the OpenGL one (`src/render.rs`), on
[wgpu](https://wgpu.rs) (Vulkan, Metal, DX12). It draws the same entities,
meshes, terrain, lights and camera from the same Lua scripts, and adds
textured ground materials, HDR with a filmic tone map, haze, screen-space
ambient occlusion and reflections, two cascades of cached sun shadows, a
lamp grid for night streets, skinned people, car and prop atlases, and
meshes streamed in tiles. It was built for a city game on an integrated
GPU (Radeon 780M/890M class): a 1 km² city street at 1080p draws in about
9 ms there.

It is in the default build (Cargo feature `wgpu-postcard`).
`--no-default-features` builds the OpenGL-only engine, and the browser build
is always OpenGL.

## Running it

```sh
auto GAME_DIR --wgpu                        # play in a wgpu window (HDR on; --no-hdr)
auto GAME_DIR --render-size 1600x900 --frames 4 --screenshot out.ppm   # an offscreen picture
auto GAME_DIR --render-size 1600x900 --hdr --frames 4 --screenshot out.ppm
WGPU_BENCH=60 auto GAME_DIR --render-size 1920x1080 --hdr --frames 4 --screenshot out.ppm
```

- `--render-scale 0.25..1` draws the 3D scene smaller than the window and
  upscales it. `--upscale bilinear|easu|easu-rcas` picks the filter for
  offscreen pictures (EASU/RCAS after AMD FSR 1, MIT: `src/THIRD-PARTY-FSR.txt`).
- `--material-pack DIR` uses another material pack. By default the window
  takes `GAME_DIR/materials`.
- `WGPU_BENCH=N` draws N more frames of the same scene and prints the GPU
  time of each stage.
- A build with the `wgpu-window` feature plays in the wgpu window by
  default; `--gl` plays in the OpenGL one. `--record` always uses OpenGL.
- Headless runs (`--headless`) draw nothing in either renderer.

## What your meshes can ask for

OBJ material names choose how a surface is shaded (`src/mesh.rs`). The OpenGL
renderer ignores them and uses the material's colour.

| Material name | Surface |
|---|---|
| `wall_...`, `roof_...`, `other_...` | building walls, roofs and the rest: textured by the material pack, with procedural windows on walls |
| `glass_...` | glass: reflects the sky, lit rooms behind it at night (interior mapping) |
| `leaf_...` | foliage: cut out by a leaf mask, casts dappled shadow |
| `limbll_`, `limbrl_`, `limbla_`, `limbra_`, `limbls_`, `limbrs_` | a walker's left/right leg, arm and shin, swung in the vertex shader as it walks |
| `car_...` | car body, shaded from the car atlas |
| `carwheel_<along cm>_<hub cm>` | a wheel: rolls with `engine.set_driven`; front ones steer with `engine.set_car` |
| `carplate_<step px>_<count>` | a number plate: each car shows one of `count` plates, `step` pixels apart in the atlas |
| `prop_...` | a prop (a shop sign, a tram's livery): colour from the prop atlas at the OBJ texture coordinate; alpha under one half is cut out |

An OBJ line `vs j0 j1 j2 w0 w1 w2` after a vertex skins it to three bones of
the humans pack.

## Packs and atlases

All are optional. Without them the renderer falls back to the materials'
colours.

- **Material pack** (a directory): two KTX2 texture arrays of 8 layers,
  RGBA8 uncompressed, `albedo.ktx2` and `normal_roughness.ktx2`, one layer
  per surface kind (`src/postcard_materials.rs`). Each layer's repeat in
  metres is `REPEAT_M` in `src/render2.wgsl`.
- **Atlases** (`engine.load_car_atlas`, `engine.load_prop_atlas`): `HATL`,
  width, height (u32 little-endian), then RGBA8 rows, colour in sRGB. In
  the car atlas, alpha is the surface: 255 paint (the entity's colour,
  clear-coated), 224-247 glass, 192-223 a lamp lens (lit at night and when
  braking), 128-191 metal, below that unpainted with gloss alpha/127.
- **Humans pack** (`engine.load_humans(dir)`): `humans_poses.bin` (`HPOS`,
  people, frames, bones; each person's cycle length, then 3x4 skinning
  matrices per frame and bone, the last frame a standing pose),
  `humans_atlas.rgba` (an atlas as above), and `human_<k>.obj` /
  `human_<k>_far.obj`. Walkers with these meshes step with the distance
  they move. `engine.set_gait(id, 0..1)` blends to standing.

## The ground

`engine.terrain{heights = "terrain.bin", ...}` reads a file of `w * d` points:
heights (i16, cm), then optionally a byte per point picking its class (and
its colour from `palette`), a byte of signed distance to a kerb (kerbs are
drawn there), and two planes of i8 x/z offsets in 2 cm steps that move the
drawn points onto a true shoreline (drawing only; physics keeps the grid).
`engine.terrain_class(x, z)` returns the class under a point.

## Streaming and packed meshes

`engine.stream(name, "tiles/t_3_4.obj", x, z, radius)` registers a mesh that
loads on a worker thread when the camera comes within `radius` of (x, z) and
is dropped when it leaves. `auto --pack-meshes DIR` writes a binary `.mesh`
beside every OBJ in DIR (`src/meshbin.rs`), which loads as a copy, not a
parse. `engine.stream_stats()` reports what's loaded. Entities have `near`
and `far` drawing distances (`spawn{near=, far=}`) for LOD.

## Light, weather and night

`engine.lighting{...}` takes `wet`, `rain` and `cloud` (0..1) as well: wet
streets with puddles and rain rings, screen-space reflections in water and
wet ground, and duller skies. At night (`glow` > 0) up to 128
`engine.light`s near the camera light the streets through a grid of 8 m
cells ahead of it, and lamp lenses and windows glow.
