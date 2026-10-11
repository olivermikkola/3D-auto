# auto

A minimal 3D sandbox kernel in Rust. One ~1 MB binary renders low-poly meshes, runs box
physics, and forwards input. **The game is entirely Lua**: the binary emits events
into a tiny pub/sub bus, and scripts build the world on top of it.

The bundled `game/` directory is an open-city demo in about 1,000 lines of Lua. It has a
procedural city, drivable cars, on-foot movement, ambient traffic, a minimap, cash, and
three missions. Edit any `.lua` file while it runs and it hot-reloads.

![Driving downtown](docs/driving.png)

```
cargo run --release              # runs ./game
cargo run --release -- my_game   # any directory with a main.lua
```

Controls: `WASD` move/drive · `Shift` run · `Space` jump/handbrake · `E` enter/exit car ·
mouse or arrow keys for the camera · `F5` reload · `F1` help · `Esc` free the mouse.

## Design

| Piece | Lines | Notes |
|---|---|---|
| `src/math.rs` | ~150 | `Vec3`, column-major `Mat4`. Y up, yaw-only rotation. |
| `src/mesh.rs` | ~250 | Flat-shaded unit primitives, OBJ+MTL loader, part baking. |
| `src/physics.rs` | ~310 | Yawed AABBs, min-axis push-out, impulses + Coulomb friction, step-up, raycasts. |
| `src/render.rs` | ~300 | miniquad/GL: lit + fogged opaque pass, sorted alpha pass, HUD quads. |
| `src/script.rs` | ~340 | The `engine` Lua table and the event bus. |
| `src/main.rs` | ~370 | Fixed 60 Hz tick, input, hot reload, headless + screenshot modes. |

Choices made to keep it small:

- **No ECS and no scene graph.** An entity is a position, yaw, scale, mesh, color, an optional
  body, and a tag. Lua holds plain integer ids.
- **Physics is boxes.** Rotation is visual only: a body collides as its yawed footprint
  re-boxed. That's enough for cars, crates and people. Ramps are not supported.
- **Prefabs are baked.** `engine.mesh(name, parts)` merges primitives into one mesh, so a car
  costs one draw call.
- **Missions are coroutines.** A mission reads top to bottom: `m:wait(...)`, `m:timer(...)`.
- **Deterministic headless mode.** `--headless N` runs N ticks with no window. CI uses it to
  play the game through scripted input (`game/test/autoplay.lua`).

## The event bus

The engine only ever calls `engine.emit(event, ...)`:

| Event | Args | When |
|---|---|---|
| `init` | | after `main.lua` runs |
| `tick` | `dt` | fixed 60 Hz, before physics |
| `contact` | `a, b` | each touching body pair after physics |
| `frame` | `dt` | once per rendered frame; build the HUD and camera here |
| `key` | `name, down` | keys: `a`-`z`, `0`-`9`, `space`, `shift`, `up`, `f1`, `mouse1`, ... |

Scripts subscribe with `engine.on(ev, fn)`, `engine.once`, `engine.off`, and can emit their
own events (the demo uses `vehicle_enter`, `mission_passed`, and so on). A handler that
throws is reported on screen with a traceback, and the other handlers still run.

## Lua API

```lua
-- entities
id = engine.spawn{mesh="cube", pos={x,y,z}, size={w,h,d}, scale=..., yaw=0,
                  color={r,g,b,a}, tag="crate", visible=true,
                  body="static"|"dynamic"|"kinematic", mass=1, friction=0.6,
                  restitution=0, gravity=1, sensor=false, step=0}
engine.despawn(id)          engine.exists(id)
engine.pos(id) -> x,y,z     engine.set_pos(id, x,y,z)
engine.yaw(id)              engine.set_yaw(id, radians)   -- forward = (sin, 0, cos)
engine.vel(id) -> x,y,z     engine.set_vel(id, x,y,z)     engine.push(id, ix,iy,iz)
engine.grounded(id)         engine.tag(id)                engine.find(tag) -> {ids}
engine.set_color(id, r,g,b[,a])   engine.set_visible(id, bool)   engine.set_scale(id, s)
engine.nearest(x,y,z, radius[, tag[, ignore]]) -> id, dist
engine.raycast(ox,oy,oz, dx,dy,dz[, max[, ignore]]) -> id, dist, hx,hy,hz, nx,ny,nz

-- meshes (builtin unit shapes: cube wedge cylinder sphere plane)
engine.mesh(name, {{mesh="cube", pos=..., size=..., yaw=..., color=..., axis="x"}, ...})
engine.load_obj(name, "assets/thing.obj")      -- usemtl/Kd become vertex colors

-- world
engine.camera(ex,ey,ez, tx,ty,tz[, fov_deg])
engine.sky(r,g,b)  engine.fog(start, end)  engine.sun(x,y,z)  engine.gravity(g)

-- input & HUD (pixels, origin top-left)
engine.key(name)  engine.mouse() -> dx,dy  engine.grab_mouse(bool)  engine.screen() -> w,h
engine.rect(x,y,w,h, r,g,b[,a])  engine.text(str, x,y[, size[, r,g,b,a]])  engine.text_width(str[, size])

-- misc
engine.time()  engine.ticks()  engine.stats()  engine.files(dir)  engine.quit()
```

## Adding a mission

![The demolition mission: physics crates and OBJ traffic cones](docs/mission.png)


Drop a file in `game/missions/`. It's picked up on the next reload:

```lua
local city = require "lib.city"
return {
  title = "Pizza Run", start = {city.node(2, 2)}, reward = 100,
  run = function(m)
    m:say("Get a car")
    m:wait(function() return m:in_car() end)
    local door = m:marker(city.node(6, 1))
    m:timer(45)
    m:wait(function() return m:near(door, 5) end)
  end,
}
```

## Command line

```
auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--frames N] [--size WxH]
```

`AUTO_TEST=1 auto game --headless 3000` plays the demo by itself and exits non-zero on any
failure. `SOAK=1` runs a traffic soak test.
