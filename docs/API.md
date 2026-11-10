# Engine API


```lua
-- entities
id = engine.spawn{mesh="cube", pos={x,y,z}, size={w,h,d}, scale=..., yaw=0, pitch=0, roll=0,
                  color={r,g,b,a}, tag="crate", visible=true,
                  body="static"|"dynamic"|"kinematic", mass=1, friction=0.6,
                  restitution=0, gravity=1, sensor=false, step=0, lock_rotation=false}
engine.despawn(id)          engine.exists(id)
engine.pos(id) -> x,y,z     engine.set_pos(id, x,y,z)
engine.yaw(id)              engine.set_yaw(id, radians)   -- heading; keeps pitch and roll
engine.orient(id, yaw[, pitch[, roll]])                   engine.rot(id) / set_rot(id, x,y,z,w)
engine.forward(id) / up(id) / right(id) -> x,y,z          -- local +Z, +Y, -X in world space
engine.vel(id) -> x,y,z     engine.set_vel(id, x,y,z)
engine.angvel(id) -> x,y,z  engine.set_angvel(id, x,y,z)  -- rad/s, world space
engine.push(id, ix,iy,iz[, px,py,pz])                     -- impulse, optionally at a point
engine.grounded(id)         engine.tag(id)                engine.find(tag) -> {ids}
engine.set_mesh(id, name)  engine.mesh_of(id) -> name
engine.set_color(id, r,g,b[,a])   engine.set_visible(id, bool)   engine.set_scale(id, s)
engine.set_glow(id, g)          -- self-illumination regardless of time of day (spawn{glow=} too)
engine.nearest(x,y,z, radius[, tag[, ignore]]) -> id, dist
engine.raycast(ox,oy,oz, dx,dy,dz[, max[, ignore]]) -> id, dist, hx,hy,hz, nx,ny,nz

-- meshes (builtin unit shapes: cube wedge cylinder sphere plane)
engine.mesh(name, {{mesh="cube", pos=..., size=..., yaw=..., color=..., axis="x", emissive=0}, ...})
-- a part can be a footprint pushed up instead: walls round it from pos up `height`, a flat roof
engine.mesh(name, {{outline={x,z, x,z, ...}, height=12, pos=..., yaw=..., color=...}, ...})
engine.load_obj(name, "assets/thing.obj")      -- usemtl Kd = color, Ke = glows at night

-- lighting (lights and emissive parts are scaled by glow: 0 by day, 1 at night)
engine.lighting{sky={r,g,b}, sky_top=, sun={x,y,z}, sun_color=, ambient=, ground=, glow=0..1, shadows=true}
id = engine.light{pos={x,y,z}, dir={x,y,z}, color=, intensity=1, radius=12, cone=180, follow=entity}
engine.set_light(id, {...})  engine.remove_light(id)  -- cone = half-angle in degrees (180 = point)

-- sound (mono, 44.1 kHz; voices with pos/follow are panned and attenuated from the camera)
engine.synth(name, {wave="square"|"saw"|"sine"|"triangle"|"noise", freq=440, freq_end=,
                    dur=0.3, attack=, release=, volume=0.5, lowpass=1, notes={...}, note_len=, loop=false})
engine.load_wav(name, "assets/boom.wav")                  -- 8/16-bit PCM, any rate
voice = engine.play(name[, {volume=1, pitch=1, loop=false, pos={x,y,z}, follow=id, ui=false}])  -- ui: plays while paused
engine.set_voice(voice, {volume=, pitch=, pos=})  engine.stop(voice)  engine.playing(voice)
engine.volume([master]) -> master

-- world
engine.terrain{x0=, z0=, step=, w=, d=, heights={w*d, row by row toward +z}, colors={r,g,b per height},
               roads={ax,az,ay, bx,bz,by, half width, road number, asphalt half width,
                      side 1 raised (0/1), side 2 raised, ...}, kerb=meters}  -- roads: see "Terrain"
engine.terrain(nil)                            -- the ground as a heightfield; nil removes it
engine.terrain_height(x, z) -> h, nx,ny,nz     -- nothing off the grid
engine.camera(ex,ey,ez, tx,ty,tz[, fov_deg])  engine.camera_pos() -> x,y,z
engine.sky(r,g,b)  engine.fog(start, end)  engine.sun(x,y,z)  engine.gravity(g)  -- shorthands

-- input & HUD (pixels, origin top-left)
engine.key(name)  engine.mouse() -> dx,dy  engine.grab_mouse(bool)  engine.screen() -> w,h
engine.cursor() -> x,y      -- mouse position in pixels, for clicking on menus
engine.pad() -> {name, lx, ly, rx, ry, lt, rt} | nil   -- sticks -1..1 (up/right +), triggers 0..1
engine.pause(bool)  engine.paused()   engine.fullscreen([bool]) -> bool   engine.headless()
engine.rect(x,y,w,h, r,g,b[,a])  engine.text(str, x,y[, size[, r,g,b,a]])  engine.text_width(str[, size])
engine.quad(x1,y1, x2,y2, x3,y3, x4,y4, r,g,b[,a])  engine.clip(x,y,w,h) / engine.clip()

-- saves (one plain value per key: tables, strings, numbers, booleans; see "Saves")
engine.save(key, value) -> true | nil, err     -- value nil deletes the key
engine.load(key) -> value | nil[, err]         engine.saves() -> {keys}

-- misc
engine.time()  engine.ticks()  engine.stats()  engine.files(dir)  engine.dirs(dir)  engine.quit()
engine.reload()                                -- start the scripts afresh after this frame, as F5 does
engine.load_mods(folder)  engine.load_mod(folder)        -- sandboxed
```

## Events

Subscribe with `engine.on(name, function(...) ... end)`. The engine emits
`init`, `tick(dt)`, `frame(dt)`, `key(name, down)`, `touch(phase, id, x, y)`,
`contact(a, b, speed, broke)`, `quit`, `minimized`, `menu_key(name, down)`,
`pad_connected(name)` and `pad_disconnected(name)`. `engine.off`, `engine.once`
and `engine.emit` support script-defined events. Key names are lowercase.

Scripts live in any folder with a `main.lua`. Files are relative to that folder.
Use `engine.load_mods(folder)` for optional sandboxed extensions. Mods cannot
use `io`, `debug`, `os.execute`, bytecode, absolute paths or parent paths;
their saves are namespaced. Trusted application scripts share one Lua state.

## Terrain

`engine.terrain` accepts a regular grid of heights, optionally colors and road
segments. Rendered triangles, collision queries and height queries share the
same heightfield. `engine.terrain(nil)` removes it. The API above documents the
road array fields. The renderer supports shadows, fog, emissive parts and up
to 16 nearby lights. All scene behavior is controlled by the Lua application.
