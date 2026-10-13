//! The Lua boundary. The engine exposes one table, `engine`, and drives the
//! game purely by emitting events into a tiny pub/sub bus written in Lua.
//! Everything else -- the city, the car, missions -- is script.

#![allow(clippy::unit_arg, clippy::type_complexity)] // binding one-liners mirror the Lua signatures

use crate::audio::{self, Synth, Wave};
use crate::engine::{Engine, Entity};
use crate::math::{Quat, Vec3, v3};
use crate::mesh::{self, Mesh};
use crate::physics::{Body, Kind, RoadSeg, Terrain};
use crate::save;
use mlua::{Function, IntoLuaMulti, Lua, LuaOptions, MultiValue, Result, StdLib, Table, Value};
use std::cell::RefCell;
use std::rc::Rc;

pub type Shared = Rc<RefCell<Engine>>;

const KERNEL: &str = r#"
local handlers = {}
local traceback = debug.traceback
-- Handler lists are copy-on-write so (un)subscribing during dispatch is safe.
function engine.on(ev, fn)
  local t = {table.unpack(handlers[ev] or {})}
  t[#t + 1] = fn
  handlers[ev] = t
  return fn
end
function engine.off(ev, fn)
  local t = {}
  for _, f in ipairs(handlers[ev] or {}) do if f ~= fn then t[#t + 1] = f end end
  handlers[ev] = t
end
-- Pausing stops ticks, and key events arrive as "menu_key" instead of "key"
-- until resumed. Keys held at the moment of pausing are released to the game
-- first, so a held trigger or accelerator doesn't stick through the menu.
local set_paused = engine._pause
engine._pause = nil
function engine.pause(on)
  for _, k in ipairs(set_paused(on == true)) do engine.emit("key", k, false) end
end
function engine.once(ev, fn)
  local function w(...) engine.off(ev, w); return fn(...) end
  return engine.on(ev, w)
end
function engine.emit(ev, ...)
  local t = handlers[ev]
  if not t then return end
  for i = 1, #t do
    local ok, err = xpcall(t[i], traceback, ...)
    if not ok then engine._error(ev, tostring(err)) end
  end
end

-- ---- mods ------------------------------------------------------------------
-- A mod is a folder with an init.lua. It runs in its own environment with the
-- safe standard library and the engine API: no os/io/debug, no bytecode, and
-- every path it passes to the engine is rooted in its own folder.
local ROOT = __ROOT
__ROOT = nil
local G, trusted_require, loadfile, load, print, package = _G, require, loadfile, load, print, package
local mod_roots = {} -- folders whose files may only ever run sandboxed
getmetatable("").__metatable = false

local function under_mod(rel)
  rel = rel .. "/"
  for _, prefix in ipairs(mod_roots) do
    if rel:sub(1, #prefix) == prefix then return true end
  end
end

local function check_module(m)
  if type(m) ~= "string" or not m:match("^[%w_][%w_%.]*$") then error("bad module name: " .. tostring(m), 3) end
  return (m:gsub("%.", "/"))
end

-- The game's own require, refusing to run mod files with full privileges.
require = function(m)
  if under_mod(check_module(m)) then error("mod code cannot be loaded outside its sandbox: " .. m, 2) end
  return trusted_require(m)
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end
local BASE = {}
for _, k in ipairs{"assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawlen", "rawset",
                   "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "xpcall", "_VERSION"} do
  BASE[k] = G[k]
end
local LIBS = {math = math, string = string, table = table, coroutine = coroutine, utf8 = utf8}
local OS = {time = os.time, clock = os.clock, date = os.date}

function engine.load_mod(dir)
  dir = tostring(dir):gsub("\\", "/"):gsub("/+$", "")
  if dir:find("%.%.") or dir:find("^/") or dir:find(":") then error("bad mod folder: " .. dir, 2) end
  local name = dir:match("([^/]+)$")
  mod_roots[#mod_roots + 1] = dir .. "/"

  local env = copy(BASE)
  for k, lib in pairs(LIBS) do env[k] = copy(lib) end
  env.os = copy(OS)
  env.print = function(...) print("[" .. name .. "]", ...) end
  env.load = function(chunk, cname, _, e) return load(chunk, cname, "t", e or env) end
  env._G = env

  -- engine, with file access rooted in the mod's folder
  local api = setmetatable({}, {__index = engine, __metatable = false})
  for _, f in ipairs{"load_obj", "load_wav"} do
    api[f] = function(n, path, ...) return engine[f](n, dir .. "/" .. path, ...) end
  end
  for _, f in ipairs{"files", "dirs"} do
    api[f] = function(path) return engine[f](dir .. "/" .. (path or ".")) end
  end
  -- saves, namespaced as "mod.<name>.<key>" so mods can't touch each other's or the game's
  local function mod_key(k)
    if type(k) ~= "string" then error("save key must be a string", 3) end
    return "mod." .. name .. "." .. k
  end
  api.save = function(k, v) return engine.save(mod_key(k), v) end
  api.load = function(k) return engine.load(mod_key(k)) end
  api.saves = function()
    local mine, prefix = {}, "mod." .. name .. "."
    for _, k in ipairs(engine.saves()) do
      if k:sub(1, #prefix) == prefix then mine[#mine + 1] = k:sub(#prefix + 1) end
    end
    return mine
  end
  api.mod_name = name
  env.engine = api

  -- require: the mod's own modules first (sandboxed), then the game's.
  local loaded = {}
  env.require = function(m)
    local rel = check_module(m)
    if loaded[m] ~= nil then return loaded[m] end
    local chunk = loadfile(ROOT .. "/" .. dir .. "/" .. rel .. ".lua", "t", env)
    if chunk then
      local r = chunk(m)
      loaded[m] = r == nil and true or r
      return loaded[m]
    end
    -- Only the game's own script files; never built-in libraries like os/io.
    if not package.searchpath(m, package.path) then error("module '" .. m .. "' not found", 2) end
    return require(m)
  end

  local main, err = loadfile(ROOT .. "/" .. dir .. "/init.lua", "t", env)
  if not main then error(err, 2) end
  main()
  return env
end

-- Load every mod folder in `container` (default "mods"), in name order.
-- A broken mod is reported and skipped; the others still load.
function engine.load_mods(container)
  container = container or "mods"
  mod_roots[#mod_roots + 1] = container .. "/"
  local names = {}
  for _, d in ipairs(engine.dirs(container)) do
    local ok, err = xpcall(engine.load_mod, traceback, container .. "/" .. d)
    if ok then
      names[#names + 1] = d
    else
      engine._error("mod " .. d, tostring(err))
    end
  end
  if #names > 0 then print("mods: " .. table.concat(names, ", ")) end
  return names
end
"#;

pub struct Script {
    pub lua: Lua,
    emit: Function,
}

impl Script {
    /// Fresh Lua state, API bound, `main.lua` executed.
    pub fn load(eng: &Shared) -> Result<Script> {
        // Game scripts are trusted local code; `debug` gives us tracebacks.
        let lua = unsafe { Lua::unsafe_new_with(StdLib::ALL_SAFE | StdLib::DEBUG, LuaOptions::default()) };
        let root = eng.borrow().root.clone();
        let api = bind(&lua, eng)?;
        lua.globals().set("engine", api)?;
        lua.globals().set("__ROOT", root.to_string_lossy().replace('\\', "/"))?;
        lua.load(KERNEL).set_name("=kernel").exec()?;
        let pkg: Table = lua.globals().get("package")?;
        let r = root.display();
        pkg.set("path", format!("{r}/?.lua;{r}/?/init.lua"))?;
        let main = root.join("main.lua");
        let src = std::fs::read_to_string(&main).map_err(|e| mlua::Error::external(format!("{}: {e}", main.display())))?;
        lua.load(src).set_name("@main.lua").exec()?;
        let emit = lua.globals().get::<Table>("engine")?.get::<Function>("emit")?;
        Ok(Script { lua, emit })
    }

    /// Emit an event. Handler errors are caught inside the bus, so this only
    /// fails if the bus itself is broken.
    pub fn emit(&self, eng: &Shared, ev: &str, args: impl IntoLuaMulti) {
        let mut a = match args.into_lua_multi(&self.lua) {
            Ok(a) => a,
            Err(e) => return report(eng, ev, &e.to_string()),
        };
        a.push_front(Value::String(self.lua.create_string(ev).unwrap()));
        if let Err(e) = self.emit.call::<()>(a) {
            report(eng, ev, &e.to_string());
        }
    }
}

pub fn report(eng: &Shared, ev: &str, msg: &str) {
    eprintln!("[lua:{ev}] {msg}");
    eng.borrow_mut().error = Some(format!("{ev}: {msg}"));
}

fn vec3(v: &Value, default: Vec3) -> Result<Vec3> {
    Ok(match v {
        Value::Nil => default,
        Value::Integer(n) => Vec3::ONE * *n as f32,
        Value::Number(n) => Vec3::ONE * *n as f32,
        Value::Table(t) => v3(
            t.get::<Option<f32>>(1)?.or(t.get("x")?).unwrap_or(default.x),
            t.get::<Option<f32>>(2)?.or(t.get("y")?).unwrap_or(default.y),
            t.get::<Option<f32>>(3)?.or(t.get("z")?).unwrap_or(default.z),
        ),
        _ => return Err(mlua::Error::runtime("expected vector {x,y,z} or number")),
    })
}

fn color(v: &Value) -> Result<[f32; 4]> {
    Ok(match v {
        Value::Table(t) => [
            t.get::<Option<f32>>(1)?.unwrap_or(1.0),
            t.get::<Option<f32>>(2)?.unwrap_or(1.0),
            t.get::<Option<f32>>(3)?.unwrap_or(1.0),
            t.get::<Option<f32>>(4)?.unwrap_or(1.0),
        ],
        _ => [1.0; 4],
    })
}

/// Several return values, or none at all (Lua sees nil).
fn multi(lua: &Lua, v: Option<impl IntoLuaMulti>) -> Result<MultiValue> {
    v.map_or(Ok(MultiValue::new()), |v| v.into_lua_multi(lua))
}

/// Resolve a script-supplied path under the game root. Absolute paths and
/// `..` are refused, so neither the game nor a mod can reach outside it.
pub fn game_path(root: &std::path::Path, rel: &str) -> Result<std::path::PathBuf> {
    use std::path::Component;
    let p = std::path::Path::new(rel);
    if p.components().all(|c| matches!(c, Component::Normal(_) | Component::CurDir)) {
        Ok(root.join(p))
    } else {
        Err(mlua::Error::runtime(format!("path '{rel}' must be relative and stay inside the game folder")))
    }
}

fn mesh_id(e: &Engine, name: &str) -> Result<usize> {
    e.mesh_ids.get(name).copied().ok_or_else(|| mlua::Error::runtime(format!("unknown mesh '{name}'")))
}

fn bind(lua: &Lua, eng: &Shared) -> Result<Table> {
    let api = lua.create_table()?;
    macro_rules! f {
        ($name:literal, |$e:ident, $lua:ident, $args:tt : $ty:ty| $body:expr) => {{
            let eng = eng.clone();
            api.set(
                $name,
                lua.create_function(move |$lua, $args: $ty| {
                    #[allow(unused_mut)]
                    let mut $e = eng.borrow_mut();
                    $body
                })?,
            )?;
        }};
    }

    // ---- entities -------------------------------------------------------
    f!("spawn", |e, _lua, t: Table| {
        let size = vec3(&t.get("size")?, Vec3::ONE)?;
        let mut ent = Entity::new(vec3(&t.get("pos")?, Vec3::ZERO)?);
        let angle = |k: &str| -> Result<f32> { Ok(t.get::<Option<f32>>(k)?.unwrap_or(0.0)) };
        ent.rot = Quat::euler(angle("yaw")?, angle("pitch")?, angle("roll")?);
        let mesh: Option<String> = t.get("mesh")?;
        ent.mesh = match &mesh {
            Some(m) => Some(mesh_id(&e, m)?),
            None => None,
        };
        // Built-in unit primitives scale to `size`; custom meshes default to 1.
        let unit = mesh.as_deref().is_none_or(mesh::builtins_contains);
        ent.scale = vec3(&t.get("scale")?, if unit { size } else { Vec3::ONE })?;
        ent.color = color(&t.get("color")?)?;
        ent.tag = t.get::<Option<String>>("tag")?.unwrap_or_default();
        ent.visible = t.get::<Option<bool>>("visible")?.unwrap_or(true);
        ent.glow = t.get::<Option<f32>>("glow")?.unwrap_or(0.0);
        if let Some(kind) = t.get::<Option<String>>("body")? {
            let k = match kind.as_str() {
                "static" => Kind::Static,
                "dynamic" => Kind::Dynamic,
                "kinematic" => Kind::Kinematic,
                o => return Err(mlua::Error::runtime(format!("unknown body kind '{o}'"))),
            };
            let mut b = Body::new(k, size * 0.5);
            b.lock_rotation = t.get::<Option<bool>>("lock_rotation")?.unwrap_or(false);
            b.set_mass(t.get::<Option<f32>>("mass")?.unwrap_or(1.0));
            b.friction = t.get::<Option<f32>>("friction")?.unwrap_or(b.friction);
            b.restitution = t.get::<Option<f32>>("restitution")?.unwrap_or(b.restitution);
            b.gravity = t.get::<Option<f32>>("gravity")?.unwrap_or(b.gravity);
            b.sensor = t.get::<Option<bool>>("sensor")?.unwrap_or(false);
            b.step = t.get::<Option<f32>>("step")?.unwrap_or(0.0);
            ent.body = Some(b);
        }
        Ok(e.spawn(ent))
    });
    f!("despawn", |e, _lua, id: u32| Ok(e.despawn(id)));
    f!("exists", |e, _lua, id: u32| Ok(e.get(id).is_some()));
    f!("pos", |e, lua, id: u32| multi(lua, e.get(id).map(|x| (x.pos.x, x.pos.y, x.pos.z))));
    f!("set_pos", |e, _lua, (id, x, y, z): (u32, f32, f32, f32)| {
        if let Some(en) = e.pose_mut(id) {
            en.pos = v3(x, y, z);
            en.prev = None; // a teleport: don't draw it sliding there
        }
        Ok(())
    });
    f!("yaw", |e, _lua, id: u32| Ok(e.get(id).map(|x| x.rot.yaw())));
    // Turns about the world up axis, keeping any pitch and roll.
    f!("set_yaw", |e, _lua, (id, y): (u32, f32)| {
        if let Some(en) = e.pose_mut(id) {
            en.rot = (Quat::axis_angle(Vec3::UP, y - en.rot.yaw()) * en.rot).norm();
        }
        Ok(())
    });
    f!("orient", |e, _lua, (id, yaw, pitch, roll): (u32, f32, Option<f32>, Option<f32>)| {
        if let Some(en) = e.pose_mut(id) {
            en.rot = Quat::euler(yaw, pitch.unwrap_or(0.0), roll.unwrap_or(0.0));
        }
        Ok(())
    });
    f!("rot", |e, lua, id: u32| multi(lua, e.get(id).map(|x| (x.rot.x, x.rot.y, x.rot.z, x.rot.w))));
    f!("set_rot", |e, _lua, (id, x, y, z, w): (u32, f32, f32, f32, f32)| {
        if let Some(en) = e.pose_mut(id) {
            en.rot = Quat { x, y, z, w }.norm();
        }
        Ok(())
    });
    // Local axes in world space. Forward is +Z, up is +Y, right is -X.
    for (name, local) in [("forward", v3(0., 0., 1.)), ("up", Vec3::UP), ("right", v3(-1., 0., 0.))] {
        let eng = eng.clone();
        api.set(
            name,
            lua.create_function(move |lua, id: u32| {
                multi(lua, eng.borrow().get(id).map(|x| x.rot.rotate(local)).map(|v| (v.x, v.y, v.z)))
            })?,
        )?;
    }
    f!("vel", |e, lua, id: u32| multi(lua, e.get(id).and_then(|x| x.body.as_ref()).map(|b| (b.vel.x, b.vel.y, b.vel.z))));
    f!("set_vel", |e, _lua, (id, x, y, z): (u32, f32, f32, f32)| {
        if let Some(b) = e.get_mut(id).and_then(|en| en.body.as_mut()) {
            b.vel = v3(x, y, z);
        }
        Ok(())
    });
    f!("angvel", |e, lua, id: u32| multi(lua, e.get(id).and_then(|x| x.body.as_ref()).map(|b| (b.ang_vel.x, b.ang_vel.y, b.ang_vel.z))));
    f!("set_angvel", |e, _lua, (id, x, y, z): (u32, f32, f32, f32)| {
        if let Some(b) = e.get_mut(id).and_then(|en| en.body.as_mut()) {
            b.ang_vel = v3(x, y, z);
        }
        Ok(())
    });
    // Impulse, optionally at a world point (which also adds spin).
    f!("push", |e, _lua, (id, x, y, z, px, py, pz): (u32, f32, f32, f32, Option<f32>, Option<f32>, Option<f32>)| {
        if let Some(en) = e.get_mut(id) {
            let (pos, rot) = (en.pos, en.rot);
            if let Some(b) = en.body.as_mut() {
                let imp = v3(x, y, z);
                b.vel += imp * b.inv_mass;
                if let (Some(px), Some(py), Some(pz)) = (px, py, pz) {
                    let r = v3(px, py, pz) - pos;
                    let local = rot.conj().rotate(r.cross(imp)).mul(b.inv_inertia);
                    b.ang_vel += rot.rotate(local);
                }
            }
        }
        Ok(())
    });
    f!("grounded", |e, _lua, id: u32| Ok(e.get(id).and_then(|x| x.body.as_ref()).is_some_and(|b| b.grounded)));
    f!("set_color", |e, _lua, (id, r, g, b, a): (u32, f32, f32, f32, Option<f32>)| {
        if let Some(en) = e.get_mut(id) {
            en.color = [r, g, b, a.unwrap_or(1.0)];
        }
        Ok(())
    });
    f!("set_glow", |e, _lua, (id, g): (u32, f32)| {
        if let Some(en) = e.get_mut(id) {
            en.glow = g;
        }
        Ok(())
    });
    f!("set_visible", |e, _lua, (id, v): (u32, bool)| {
        if let Some(en) = e.get_mut(id) {
            en.visible = v;
        }
        Ok(())
    });
    f!("set_scale", |e, _lua, (id, s): (u32, Value)| {
        let s = vec3(&s, Vec3::ONE)?;
        if let Some(en) = e.get_mut(id) {
            en.scale = s;
        }
        Ok(())
    });
    f!("tag", |e, _lua, id: u32| Ok(e.get(id).map(|x| x.tag.clone())));
    // Swap an entity's model, e.g. a respray. Its body and scale stay as they are.
    f!("set_mesh", |e, _lua, (id, name): (u32, String)| {
        let m = mesh_id(&e, &name)?;
        if let Some(en) = e.get_mut(id) {
            en.mesh = Some(m);
        }
        Ok(())
    });
    f!("mesh_of", |e, _lua, id: u32| {
        let m = e.get(id).and_then(|x| x.mesh);
        Ok(m.and_then(|m| e.mesh_ids.iter().find(|(_, i)| **i == m).map(|(n, _)| n.clone())))
    });
    f!("find", |e, _lua, tag: String| Ok(e.find(&tag)));
    f!("nearest", |e, lua, (x, y, z, r, tag, ignore): (f32, f32, f32, f32, Option<String>, Option<u32>)| {
        let p = v3(x, y, z);
        let best = e
            .ents
            .iter()
            .enumerate()
            .filter_map(|(i, en)| Some((i as u32, en.as_ref()?)))
            .filter(|(i, en)| Some(*i) != ignore && tag.as_ref().is_none_or(|t| &en.tag == t))
            .map(|(i, en)| (i, (en.pos - p).len()))
            .filter(|&(_, d)| d <= r)
            .min_by(|a, b| a.1.total_cmp(&b.1));
        multi(lua, best)
    });
    f!("raycast", |e, lua, (ox, oy, oz, dx, dy, dz, max, ignore): (f32, f32, f32, f32, f32, f32, Option<f32>, Option<u32>)| {
        let dir = v3(dx, dy, dz).norm();
        match e.raycast(v3(ox, oy, oz), dir, max.unwrap_or(1000.0), ignore) {
            Some(h) => (h.id, h.dist, h.point.x, h.point.y, h.point.z, h.normal.x, h.normal.y, h.normal.z).into_lua_multi(lua),
            None => Ok(MultiValue::new()),
        }
    });

    // The ground as a heightfield: {x0, z0, step, w, d, heights = {w * d
    // numbers, row by row toward +z}, colors = {r, g, b per height}?, roads =
    // {ax, az, ay, bx, bz, by, half width, road number, ...}?}; nil removes it.
    f!("terrain", |e, _lua, t: Option<Table>| {
        let Some(t) = t else {
            e.set_terrain(None, None);
            return Ok(());
        };
        let (w, d): (usize, usize) = (t.get("w")?, t.get("d")?);
        let step: f32 = t.get("step")?;
        if w < 2 || d < 2 || step <= 0.0 {
            return Err(mlua::Error::runtime("terrain needs w, d >= 2 and step > 0"));
        }
        // Heights as numbers, or a file: w * d little-endian i16 centimeters,
        // then optionally a byte per point picking its color from `palette`.
        let (heights, classes): (Vec<f32>, Option<Vec<u8>>) = match t.get::<Value>("heights")? {
            Value::String(rel) => {
                let path = game_path(&e.root, &rel.to_str()?)?;
                let bytes = std::fs::read(&path).map_err(|err| mlua::Error::runtime(format!("{}: {err}", path.display())))?;
                let n = w * d;
                if bytes.len() != 2 * n && bytes.len() != 3 * n {
                    return Err(mlua::Error::runtime(format!("{} is {} bytes, not {} or {}", rel.to_str()?, bytes.len(), 2 * n, 3 * n)));
                }
                let hs = bytes[..2 * n].chunks(2).map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 100.0).collect();
                (hs, (bytes.len() == 3 * n).then(|| bytes[2 * n..].to_vec()))
            }
            Value::Table(tb) => (tb.sequence_values().collect::<Result<_>>()?, None),
            _ => return Err(mlua::Error::runtime("terrain heights must be a table of numbers or a file name")),
        };
        if heights.len() != w * d {
            return Err(mlua::Error::runtime(format!("terrain has {} heights, not w * d = {}", heights.len(), w * d)));
        }
        let palette = match t.get::<Option<Table>>("palette")? {
            None => None,
            Some(p) => Some(
                p.sequence_values::<Table>().map(|c| color(&Value::Table(c?)).map(|c| [c[0], c[1], c[2]])).collect::<Result<Vec<_>>>()?,
            ),
        };
        let colors = match t.get::<Option<Table>>("colors")? {
            None => match (classes, palette) {
                (Some(cl), Some(pal)) if !pal.is_empty() => Some(cl.iter().map(|&k| pal[(k as usize).min(pal.len() - 1)]).collect()),
                _ => None,
            },
            Some(c) => {
                let v: Vec<f32> = c.sequence_values().collect::<Result<_>>()?;
                if v.len() != 3 * w * d {
                    return Err(mlua::Error::runtime(format!("terrain has {} color values, not 3 * w * d = {}", v.len(), 3 * w * d)));
                }
                Some(v.chunks(3).map(|c| [c[0], c[1], c[2]]).collect())
            }
        };
        // Roads over it, level across: {ax, az, ay, bx, bz, by, half width,
        // which road, ...}.
        let roads = match t.get::<Option<Table>>("roads")? {
            None => Vec::new(),
            Some(r) => {
                let v: Vec<f32> = r.sequence_values().collect::<Result<_>>()?;
                if !v.len().is_multiple_of(8) {
                    return Err(mlua::Error::runtime("terrain roads come in eights: ax, az, ay, bx, bz, by, half width, road"));
                }
                v.chunks(8).map(|c| RoadSeg { a: v3(c[0], c[2], c[1]), b: v3(c[3], c[5], c[4]), half: c[6], road: c[7] as u32 }).collect()
            }
        };
        let terrain = Terrain::new(t.get("x0")?, t.get("z0")?, step, w, d, heights).with_roads(roads);
        e.set_terrain(Some(terrain), colors);
        Ok(())
    });
    // Ground height and normal at (x, z); nothing off the heightfield.
    f!("terrain_height", |e, lua, (x, z): (f32, f32)| {
        multi(lua, e.terrain.as_ref().and_then(|t| t.surface(x, z)).map(|(h, n)| (h, n.x, n.y, n.z)))
    });

    // ---- meshes ---------------------------------------------------------
    f!("mesh", |e, _lua, (name, parts): (String, Table)| {
        let mut out = Mesh::default();
        for p in parts.sequence_values::<Table>() {
            let p = p?;
            let src = mesh_id(&e, &p.get::<Option<String>>("mesh")?.unwrap_or("cube".into()))?;
            let c = color(&p.get("color")?)?;
            let size = vec3(&p.get("size")?, Vec3::ONE)?;
            let mut src = e.meshes[src].clone();
            if let Some(axis) = p.get::<Option<String>>("axis")? {
                src.reorient(&axis).map_err(mlua::Error::runtime)?;
            }
            let angle = |k: &str| -> Result<f32> { Ok(p.get::<Option<f32>>(k)?.unwrap_or(0.0)) };
            let turn = (angle("yaw")?, angle("pitch")?, angle("roll")?);
            let glow = p.get::<Option<f32>>("emissive")?.unwrap_or(0.0);
            out.append_tilted(&src, vec3(&p.get("pos")?, Vec3::ZERO)?, turn, size, v3(c[0], c[1], c[2]), glow);
        }
        let tris = out.tri_count();
        e.add_mesh(&name, out);
        Ok(tris)
    });
    f!("load_obj", |e, _lua, (name, path): (String, String)| {
        let m = mesh::load_obj(&game_path(&e.root, &path)?).map_err(mlua::Error::runtime)?;
        let tris = m.tri_count();
        e.add_mesh(&name, m);
        Ok(tris)
    });

    // ---- audio ----------------------------------------------------------
    f!("synth", |e, _lua, (name, t): (String, Table)| {
        let d = Synth::default();
        let num = |k: &str, def: f32| -> Result<f32> { Ok(t.get::<Option<f32>>(k)?.unwrap_or(def)) };
        let wave = match t.get::<Option<String>>("wave")?.as_deref().unwrap_or("square") {
            "sine" => Wave::Sine,
            "square" => Wave::Square,
            "saw" => Wave::Saw,
            "triangle" => Wave::Triangle,
            "noise" => Wave::Noise,
            o => return Err(mlua::Error::runtime(format!("unknown wave '{o}'"))),
        };
        let notes = match t.get::<Option<Table>>("notes")? {
            Some(n) => n.sequence_values::<f32>().collect::<Result<Vec<_>>>()?,
            None => Vec::new(),
        };
        let s = Synth {
            wave,
            freq: num("freq", d.freq)?,
            freq_end: num("freq_end", 0.0)?,
            dur: num("dur", d.dur)?,
            attack: num("attack", d.attack)?,
            release: num("release", d.release)?,
            volume: num("volume", d.volume)?,
            lowpass: num("lowpass", 1.0)?,
            notes,
            note_len: num("note_len", d.note_len)?,
            looped: t.get::<Option<bool>>("loop")?.unwrap_or(false),
        };
        let buf = s.render();
        let secs = buf.len() as f32 / audio::RATE as f32;
        e.sounds.insert(name, std::sync::Arc::new(buf));
        Ok(secs)
    });
    f!("load_wav", |e, _lua, (name, path): (String, String)| {
        let full = game_path(&e.root, &path)?;
        let bytes = std::fs::read(&full).map_err(|err| mlua::Error::runtime(format!("{}: {err}", full.display())))?;
        let buf = audio::load_wav(&bytes).map_err(|err| mlua::Error::runtime(format!("{path}: {err}")))?;
        let secs = buf.len() as f32 / audio::RATE as f32;
        e.sounds.insert(name, std::sync::Arc::new(buf));
        Ok(secs)
    });
    f!("play", |e, _lua, (name, t): (String, Option<Table>)| {
        let data = e.sounds.get(&name).cloned().ok_or_else(|| mlua::Error::runtime(format!("unknown sound '{name}'")))?;
        let get = |k: &str| -> Result<Option<f32>> { t.as_ref().map_or(Ok(None), |t| t.get::<Option<f32>>(k)) };
        let (volume, pitch) = (get("volume")?.unwrap_or(1.0), get("pitch")?.unwrap_or(1.0));
        let looped = t.as_ref().map_or(Ok(None), |t| t.get::<Option<bool>>("loop"))?.unwrap_or(false);
        let follow = t.as_ref().map_or(Ok(None), |t| t.get::<Option<u32>>("follow"))?;
        let mut world = match t.as_ref().map_or(Ok(Value::Nil), |t| t.get::<Value>("pos"))? {
            Value::Nil => None,
            v => Some(vec3(&v, Vec3::ZERO)?),
        };
        if let Some(f) = follow {
            world = e.get(f).map(|x| x.pos);
        }
        let ui = t.as_ref().map_or(Ok(None), |t| t.get::<Option<bool>>("ui"))?.unwrap_or(false);
        let id = e.mixer.lock().unwrap().play(data, volume, pitch, looped, world, ui);
        if let Some(f) = follow {
            e.follow.push((id, f));
        }
        Ok(id)
    });
    f!("set_voice", |e, _lua, (id, t): (u32, Table)| {
        let world = match t.get::<Value>("pos")? {
            Value::Nil => None,
            v => Some(vec3(&v, Vec3::ZERO)?),
        };
        e.mixer.lock().unwrap().set(id, t.get("volume")?, t.get("pitch")?, world);
        Ok(())
    });
    f!("stop", |e, _lua, id: u32| Ok(e.mixer.lock().unwrap().stop(id)));
    f!("playing", |e, _lua, id: u32| Ok(e.mixer.lock().unwrap().playing(id)));
    f!("volume", |e, _lua, v: Option<f32>| {
        let mut m = e.mixer.lock().unwrap();
        if let Some(v) = v {
            m.master = v.clamp(0.0, 4.0);
        }
        Ok(m.master)
    });

    // ---- lights -------------------------------------------------------------
    fn apply_light(l: &mut crate::engine::Light, t: &Table) -> Result<()> {
        l.pos = vec3(&t.get("pos")?, l.pos)?;
        l.dir = vec3(&t.get("dir")?, l.dir)?.norm();
        if let Value::Table(_) = t.get::<Value>("color")? {
            let c = color(&t.get("color")?)?;
            l.color = [c[0], c[1], c[2]];
        }
        l.intensity = t.get::<Option<f32>>("intensity")?.unwrap_or(l.intensity);
        l.radius = t.get::<Option<f32>>("radius")?.unwrap_or(l.radius);
        if let Some(deg) = t.get::<Option<f32>>("cone")? {
            l.cone = if deg >= 180.0 { -1.0 } else { deg.to_radians().cos() };
        }
        if let Some(f) = t.get::<Option<u32>>("follow")? {
            l.follow = Some(f);
        }
        Ok(())
    }
    f!("light", |e, _lua, t: Table| {
        let mut l = crate::engine::Light {
            pos: Vec3::ZERO,
            dir: v3(0., -1., 0.),
            color: [1.0, 0.9, 0.7],
            intensity: 1.0,
            radius: 12.0,
            cone: -1.0,
            follow: None,
        };
        apply_light(&mut l, &t)?;
        e.lights.push(Some(l));
        Ok(e.lights.len() as u32 - 1)
    });
    f!("set_light", |e, _lua, (id, t): (u32, Table)| {
        if let Some(Some(l)) = e.lights.get_mut(id as usize) {
            apply_light(l, &t)?;
        }
        Ok(())
    });
    f!("remove_light", |e, _lua, id: u32| {
        if let Some(l) = e.lights.get_mut(id as usize) {
            *l = None;
        }
        Ok(())
    });
    f!("lighting", |e, _lua, t: Table| {
        let rgb = |k: &str, cur: [f32; 3]| -> Result<[f32; 3]> {
            Ok(match t.get::<Value>(k)? {
                Value::Table(_) => {
                    let c = color(&t.get(k)?)?;
                    [c[0], c[1], c[2]]
                }
                _ => cur,
            })
        };
        let env = &mut e.env;
        env.sky = rgb("sky", env.sky)?;
        env.sky_top = rgb("sky_top", env.sky_top)?;
        env.sun_color = rgb("sun_color", env.sun_color)?;
        env.ambient = rgb("ambient", env.ambient)?;
        env.ground = rgb("ground", env.ground)?;
        if let Value::Table(_) = t.get::<Value>("sun")? {
            env.sun = vec3(&t.get("sun")?, env.sun)?.norm();
        }
        env.glow = t.get::<Option<f32>>("glow")?.unwrap_or(env.glow).clamp(0.0, 1.0);
        env.shadows = t.get::<Option<bool>>("shadows")?.unwrap_or(env.shadows);
        Ok(())
    });

    // ---- camera & environment ------------------------------------------
    f!("camera", |e, _lua, (ex, ey, ez, tx, ty, tz, fov): (f32, f32, f32, f32, f32, f32, Option<f32>)| {
        e.camera.eye = v3(ex, ey, ez);
        e.camera.target = v3(tx, ty, tz);
        if let Some(f) = fov {
            e.camera.fov = f.to_radians();
        }
        Ok(())
    });
    f!("camera_pos", |e, _lua, (): ()| Ok((e.camera.eye.x, e.camera.eye.y, e.camera.eye.z)));
    f!("sky", |e, _lua, (r, g, b): (f32, f32, f32)| Ok(e.env.sky = [r, g, b]));
    f!("fog", |e, _lua, (s, en): (f32, f32)| {
        e.env.fog_start = s;
        e.env.fog_end = en;
        Ok(())
    });
    f!("sun", |e, _lua, (x, y, z): (f32, f32, f32)| Ok(e.env.sun = v3(x, y, z).norm()));
    f!("gravity", |e, _lua, g: f32| Ok(e.env.gravity = g));

    // ---- input ----------------------------------------------------------
    f!("key", |e, _lua, k: String| Ok(e.keys.contains(&k)));
    f!("mouse", |e, _lua, (): ()| Ok(e.mouse_delta));
    f!("grab_mouse", |e, _lua, g: bool| Ok(e.mouse_grab = g));
    f!("cursor", |e, _lua, (): ()| Ok(e.cursor));
    // The first gamepad: sticks -1..1 (up and right positive), triggers 0..1. Nil without one.
    f!("pad", |e, lua, (): ()| {
        let Some(p) = &e.pad else { return Ok(Value::Nil) };
        let t = lua.create_table()?;
        t.set("name", p.name.as_str())?;
        for (k, v) in [("lx", p.lx), ("ly", p.ly), ("rx", p.rx), ("ry", p.ry), ("lt", p.lt), ("rt", p.rt)] {
            t.set(k, v)?;
        }
        Ok(Value::Table(t))
    });
    f!("_pause", |e, _lua, on: bool| Ok(e.set_paused(on)));
    f!("paused", |e, _lua, (): ()| Ok(e.paused));
    f!("fullscreen", |e, _lua, on: Option<bool>| {
        if let Some(on) = on {
            e.fullscreen = on;
        }
        Ok(e.fullscreen)
    });

    // ---- HUD ------------------------------------------------------------
    f!("screen", |e, _lua, (): ()| Ok(e.screen));
    f!("rect", |e, _lua, (x, y, w, h, r, g, b, a): (f32, f32, f32, f32, f32, f32, f32, Option<f32>)| {
        Ok(e.hud_rect(x, y, w, h, [r, g, b, a.unwrap_or(1.0)]))
    });
    f!(
        "text",
        |e, _lua, (s, x, y, size, r, g, b, a): (String, f32, f32, Option<f32>, Option<f32>, Option<f32>, Option<f32>, Option<f32>)| {
            let c = [r.unwrap_or(1.0), g.unwrap_or(1.0), b.unwrap_or(1.0), a.unwrap_or(1.0)];
            Ok(e.hud_text(&s, x, y, size.unwrap_or(14.0), c))
        }
    );
    f!("text_width", |_e, _lua, (s, size): (String, Option<f32>)| Ok(Engine::text_width(&s, size.unwrap_or(14.0))));

    // ---- misc -----------------------------------------------------------
    f!("time", |e, _lua, (): ()| Ok(e.time));
    f!("ticks", |e, _lua, (): ()| Ok(e.tick));
    f!("quit", |e, _lua, (): ()| Ok(e.quit = true));
    f!("reload", |e, _lua, (): ()| Ok(e.reload = true));
    f!("stats", |e, lua, (): ()| {
        let t = lua.create_table()?;
        t.set("entities", e.live)?;
        t.set("meshes", e.meshes.len())?;
        t.set("lights", e.lights.iter().flatten().count())?;
        t.set("voices", e.mixer.lock().unwrap().voice_count())?;
        Ok(t)
    });
    // Directory listings (sorted names), files and subfolders separately.
    for (name, want_dir) in [("files", false), ("dirs", true)] {
        let eng = eng.clone();
        api.set(
            name,
            lua.create_function(move |_lua, dir: String| {
                let path = game_path(&eng.borrow().root, &dir)?;
                let mut names: Vec<String> = std::fs::read_dir(path)
                    .map(|rd| {
                        rd.filter_map(|d| {
                            let d = d.ok()?;
                            (d.file_type().ok()?.is_dir() == want_dir).then(|| d.file_name().into_string().ok())?
                        })
                        .collect()
                    })
                    .unwrap_or_default();
                names.sort();
                Ok(names)
            })?,
        )?;
    }
    // ---- saves ----------------------------------------------------------
    // One plain value per key. Bad keys or unsavable values are script bugs
    // and raise; disk trouble returns nil, message so the game can carry on.
    f!("save", |e, _lua, (key, v): (String, Value)| {
        save::check_key(&key).map_err(mlua::Error::runtime)?;
        let text = match v {
            Value::Nil => None,
            v => Some(save::encode(&v).map_err(|err| mlua::Error::runtime(format!("save '{key}': {err}")))?),
        };
        let keys = e.saves.keys();
        if text.is_some() && !keys.contains(&key) {
            if keys.len() >= save::MAX_KEYS {
                return Err(mlua::Error::runtime(format!("save '{key}': already {} saved keys", save::MAX_KEYS)));
            }
            // Mod keys are "mod.<name>.<key>"; one mod gets a quarter of the room.
            if let Some(m) = key.strip_prefix("mod.").and_then(|k| k.split_once('.')).map(|(m, _)| format!("mod.{m}."))
                && keys.iter().filter(|k| k.starts_with(&m)).count() >= save::MAX_KEYS / 4
            {
                return Err(mlua::Error::runtime(format!("save '{key}': this mod already has {} saved keys", save::MAX_KEYS / 4)));
            }
        }
        Ok(match e.saves.write(&key, text.as_deref()) {
            Ok(()) => (true, None),
            Err(err) => (false, Some(format!("save '{key}': {err}"))),
        })
    });
    f!("load", |e, lua, key: String| {
        save::check_key(&key).map_err(mlua::Error::runtime)?;
        let text = match e.saves.read(&key) {
            Ok(Some(t)) => t,
            Ok(None) => return Ok((Value::Nil, None)),
            Err(err) => return Ok((Value::Nil, Some(format!("load '{key}': {err}")))),
        };
        Ok(match save::decode(lua, &text) {
            Ok(v) => (v, None),
            Err(err) => {
                let moved = e.saves.quarantine(&key).map_or(String::new(), |p| format!("; moved it to {}", p.display()));
                (Value::Nil, Some(format!("load '{key}': {err}{moved}")))
            }
        })
    });
    f!("saves", |e, _lua, (): ()| Ok(e.saves.keys()));

    f!("_error", |e, _lua, (ev, msg): (String, String)| {
        eprintln!("[lua:{ev}] {msg}");
        e.error = Some(format!("{ev}: {msg}"));
        Ok(())
    });
    Ok(api)
}
