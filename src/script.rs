//! The Lua boundary. The engine exposes one table, `engine`, and drives the
//! game purely by emitting events into a tiny pub/sub bus written in Lua.
//! Everything else -- the city, the car, missions -- is script.

#![allow(clippy::unit_arg, clippy::type_complexity)] // binding one-liners mirror the Lua signatures

use crate::engine::{Engine, Entity};
use crate::math::{Vec3, v3};
use crate::mesh::{self, Mesh};
use crate::physics::{self, Body, Kind};
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
        ent.yaw = t.get::<Option<f32>>("yaw")?.unwrap_or(0.0);
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
        if let Some(kind) = t.get::<Option<String>>("body")? {
            let k = match kind.as_str() {
                "static" => Kind::Static,
                "dynamic" => Kind::Dynamic,
                "kinematic" => Kind::Kinematic,
                o => return Err(mlua::Error::runtime(format!("unknown body kind '{o}'"))),
            };
            let mut b = Body::new(k, size * 0.5);
            if let Some(m) = t.get::<Option<f32>>("mass")? {
                b.inv_mass = if m > 0.0 && k == Kind::Dynamic { 1.0 / m } else { 0.0 };
            }
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
        if let Some(en) = e.get_mut(id) {
            en.pos = v3(x, y, z);
        }
        Ok(())
    });
    f!("yaw", |e, _lua, id: u32| Ok(e.get(id).map(|x| x.yaw)));
    f!("set_yaw", |e, _lua, (id, y): (u32, f32)| {
        if let Some(en) = e.get_mut(id) {
            en.yaw = y;
        }
        Ok(())
    });
    f!("vel", |e, lua, id: u32| multi(lua, e.get(id).and_then(|x| x.body.as_ref()).map(|b| (b.vel.x, b.vel.y, b.vel.z))));
    f!("set_vel", |e, _lua, (id, x, y, z): (u32, f32, f32, f32)| {
        if let Some(b) = e.get_mut(id).and_then(|en| en.body.as_mut()) {
            b.vel = v3(x, y, z);
        }
        Ok(())
    });
    f!("push", |e, _lua, (id, x, y, z): (u32, f32, f32, f32)| {
        if let Some(b) = e.get_mut(id).and_then(|en| en.body.as_mut()) {
            let im = b.inv_mass;
            b.vel += v3(x, y, z) * im;
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
    f!("find", |e, _lua, tag: String| {
        Ok(e.ents.iter().enumerate().filter(|(_, x)| x.as_ref().is_some_and(|x| x.tag == tag)).map(|(i, _)| i as u32).collect::<Vec<_>>())
    });
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
        match physics::raycast(&e.ents, v3(ox, oy, oz), dir, max.unwrap_or(1000.0), ignore) {
            Some(h) => (h.id, h.dist, h.point.x, h.point.y, h.point.z, h.normal.x, h.normal.y, h.normal.z).into_lua_multi(lua),
            None => Ok(MultiValue::new()),
        }
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
            out.append(&src, vec3(&p.get("pos")?, Vec3::ZERO)?, p.get::<Option<f32>>("yaw")?.unwrap_or(0.0), size, v3(c[0], c[1], c[2]));
        }
        let tris = out.tri_count();
        e.add_mesh(&name, out);
        Ok(tris)
    });
    f!("load_obj", |e, _lua, (name, path): (String, String)| {
        let m = mesh::load_obj(&e.root.join(&path)).map_err(mlua::Error::runtime)?;
        let tris = m.tri_count();
        e.add_mesh(&name, m);
        Ok(tris)
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
    f!("stats", |e, lua, (): ()| {
        let t = lua.create_table()?;
        t.set("entities", e.live)?;
        t.set("meshes", e.meshes.len())?;
        Ok(t)
    });
    f!("files", |e, _lua, dir: String| {
        let mut names: Vec<String> = std::fs::read_dir(e.root.join(&dir))
            .map(|rd| rd.filter_map(|d| d.ok()?.file_name().into_string().ok()).collect())
            .unwrap_or_default();
        names.sort();
        Ok(names)
    });
    f!("_error", |e, _lua, (ev, msg): (String, String)| {
        eprintln!("[lua:{ev}] {msg}");
        e.error = Some(format!("{ev}: {msg}"));
        Ok(())
    });
    Ok(api)
}
