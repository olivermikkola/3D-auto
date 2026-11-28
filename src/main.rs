//! auto: a minimal 3D sandbox kernel. The binary renders, simulates and
//! forwards input; the game is whatever Lua scripts the data directory holds.
//!
//!   auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--record OUT.rgb] [--frames N] [--size WxH] [--save-dir DIR]

mod audio;
mod engine;
mod font;
mod gltf_anim;
mod gltf_mesh;
mod humans;
mod math;
mod mesh;
mod meshbin;
mod pad;
mod physics;
#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
mod postcard_materials;
mod render;
#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
mod render2;
mod save;
mod script;
mod stream;
mod vfs;
#[cfg(target_arch = "wasm32")]
mod web;
#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
mod window2;

use engine::{Engine, TICK_HZ};
use miniquad::{EventHandler, KeyCode, KeyMods, MouseButton, conf, window};
use script::{Script, Shared};
use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

struct Opts {
    root: PathBuf,
    headless: Option<u64>,
    screenshot: Option<String>,
    record: Option<String>,
    frames: Option<u64>,
    ticks_per_frame: u32,
    size: (i32, i32),
    save_dir: Option<PathBuf>,
    fps: u32,
    fullscreen: bool,
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    render_size: Option<(u32, u32)>,
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    upscale: Option<render2::Upscale>,
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    material_pack: Option<PathBuf>,
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    hdr: bool,
    /// Play in a window drawn by the wgpu renderer: the default, unless
    /// --gl (or --record, which only the GL window does) asks for the old one.
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    wgpu: bool,
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    gl: bool,
    /// --no-hdr: the wgpu window without HDR (on by default there).
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    no_hdr: bool,
    /// --render-scale: the 3D scene's size as a fraction of the window's.
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    render_scale: f32,
}

fn parse_args() -> Result<Opts, String> {
    let mut o = Opts {
        root: PathBuf::from("game"),
        headless: None,
        screenshot: None,
        record: None,
        frames: None,
        ticks_per_frame: 1,
        size: (1280, 720),
        save_dir: None,
        fps: 60,
        fullscreen: false,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        render_size: None,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        upscale: None,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        material_pack: None,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        hdr: false,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        wgpu: false,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        gl: false,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        no_hdr: false,
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        render_scale: 1.0,
    };
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = |name: &str| args.next().ok_or(format!("{name} needs a value"));
        match a.as_str() {
            "--headless" => o.headless = Some(val("--headless")?.parse().map_err(|_| "bad tick count")?),
            "--screenshot" => o.screenshot = Some(val("--screenshot")?),
            "--record" => o.record = Some(val("--record")?),
            "--frames" => o.frames = Some(val("--frames")?.parse().map_err(|_| "bad frame count")?),
            "--ticks-per-frame" => o.ticks_per_frame = val("--ticks-per-frame")?.parse().map_err(|_| "bad tick count")?,
            "--save-dir" => o.save_dir = Some(PathBuf::from(val("--save-dir")?)),
            "--fps" => o.fps = val("--fps")?.parse().map_err(|_| "bad fps")?,
            // Write a packed .mesh beside every OBJ in DIR (meshbin.rs), then exit.
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--pack-meshes" => {
                let dir = PathBuf::from(val("--pack-meshes")?);
                let t = std::time::Instant::now();
                let (packed, fresh) = meshbin::pack_dir(&dir)?;
                println!("packed {packed} meshes in {:.1} s ({fresh} already up to date)", t.elapsed().as_secs_f64());
                std::process::exit(0);
            }
            "--fullscreen" => o.fullscreen = true,
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--render-size" => {
                let value = val("--render-size")?;
                let (w, h) = value.split_once('x').ok_or("render size is WxH")?;
                o.render_size = Some((w.parse().map_err(|_| "bad render width")?, h.parse().map_err(|_| "bad render height")?));
            }
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--upscale" => o.upscale = Some(val("--upscale")?.parse()?),
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--material-pack" => o.material_pack = Some(val("--material-pack")?.into()),
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--hdr" => o.hdr = true,
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--wgpu" => o.wgpu = true, // the wgpu window (the default one with the `wgpu-window` feature)
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--gl" => o.gl = true,
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--no-hdr" => o.no_hdr = true,
            #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
            "--render-scale" => o.render_scale = val("--render-scale")?.parse().map_err(|_| "bad render scale")?,
            "--size" => {
                let v = val("--size")?;
                let (w, h) = v.split_once('x').ok_or("size is WxH")?;
                o.size = (w.parse().map_err(|_| "bad width")?, h.parse().map_err(|_| "bad height")?);
            }
            "-V" | "--version" => {
                println!("auto {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "-h" | "--help" => {
                println!(
                    "usage: auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--record OUT.rgb] [--frames N] [--ticks-per-frame K] [--size WxH] [--save-dir DIR] [--fps N] [--fullscreen]"
                );
                #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
                {
                    println!("--render-size WxH opts a --screenshot run into wgpu; --upscale bilinear|easu|easu-rcas selects the filter");
                    println!("--material-pack DIR applies a material pack (KTX2 arrays: docs/RENDERER.md)");
                    println!("--hdr draws in linear light with haze, glass reflections and a filmic tone map");
                    println!(
                        "--wgpu plays in a window drawn by the wgpu renderer{}, with HDR (--no-hdr: without) and the textures in GAME_DIR/materials",
                        if cfg!(feature = "wgpu-window") { " (the default in this build)" } else { "" }
                    );
                    println!("  (--material-pack DIR: others) at --render-scale 0.25..1; --gl plays in the OpenGL window");
                }
                std::process::exit(0);
            }
            s if s.starts_with('-') => return Err(format!("unknown flag {s}")),
            s => o.root = PathBuf::from(s),
        }
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    {
        // A window to play in: the wgpu one (with HDR) if asked for with
        // --wgpu, or by default in a build with the `wgpu-window` feature
        // unless --gl asks for the OpenGL one. --record only works in that.
        let asked = o.wgpu || cfg!(feature = "wgpu-window");
        if o.record.is_some() && asked && !o.gl && o.headless.is_none() && o.render_size.is_none() {
            eprintln!("auto: --record uses the OpenGL window");
            o.gl = true;
        }
        o.wgpu = asked && !o.gl && o.headless.is_none() && o.render_size.is_none();
        if o.wgpu && !o.no_hdr {
            o.hdr = true;
        }
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    if o.upscale.is_some() && o.render_size.is_none() && !o.wgpu {
        return Err("--upscale requires --render-size".into());
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    if o.hdr && o.render_size.is_none() && !o.wgpu {
        return Err("--hdr requires --render-size".into());
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    if o.material_pack.is_some() && o.render_size.is_none() && !o.wgpu {
        return Err("--material-pack requires --render-size".into());
    }
    // In a browser the game folder is packed into the module, under "/".
    if cfg!(target_arch = "wasm32") {
        o.root = PathBuf::from("/game");
        return Ok(o);
    }
    // Released builds ship `game/` next to the executable; find it from anywhere.
    if !o.root.join("main.lua").exists()
        && o.root == Path::new("game")
        && let Some(beside) = std::env::current_exe().ok().and_then(|p| Some(p.parent()?.join("game")))
    {
        o.root = beside;
    }
    if !o.root.join("main.lua").exists() {
        return Err(format!("no main.lua in {}", o.root.display()));
    }
    o.root = plain_path(o.root.canonicalize().map_err(|e| e.to_string())?);
    if let Some(d) = &o.save_dir {
        // Saves inside the game folder would trip hot reload on every autosave.
        let d = std::path::absolute(d).map_err(|e| format!("--save-dir {}: {e}", d.display()))?;
        if d.starts_with(&o.root) {
            return Err(format!("--save-dir {} is inside the game folder; put saves somewhere else", d.display()));
        }
        o.save_dir = Some(d);
    }
    Ok(o)
}

/// Windows canonicalizes to `\\?\C:\...`, which Lua's file functions don't
/// understand; drop the prefix when it's a plain drive path.
fn plain_path(p: PathBuf) -> PathBuf {
    match p.to_str().and_then(|s| s.strip_prefix(r"\\?\")) {
        Some(rest) if !rest.starts_with("UNC") => PathBuf::from(rest),
        _ => p,
    }
}

/// Saves go to the user's data folder when a person is playing. Headless,
/// screenshot and timed runs keep them in memory so tests and docs never read
/// or overwrite real progress, unless `--save-dir` names a folder.
fn save_store(o: &Opts) -> save::Store {
    if cfg!(target_arch = "wasm32") {
        return save::Store::browser();
    }
    let dir = match &o.save_dir {
        Some(d) => Some(d.clone()),
        None if o.headless.is_some() || o.screenshot.is_some() || o.frames.is_some() => None,
        None => {
            let game = o
                .root
                .file_name()
                .map_or("game".into(), |n| n.to_string_lossy().replace(|c: char| !c.is_ascii_alphanumeric() && c != '-', "_"));
            let d = save::user_dir(&game);
            if d.is_none() {
                eprintln!("saves: no user data folder found; progress won't be kept");
            }
            d
        }
    };
    match dir {
        Some(d) => {
            println!("saves: {}", d.display());
            save::Store::Dir(d)
        }
        None => save::Store::default(),
    }
}

/// Newest modification time of any file under `dir`.
fn newest_mtime(dir: &Path) -> Option<SystemTime> {
    if cfg!(target_arch = "wasm32") {
        return None; // the pack doesn't change
    }
    let mut best = None;
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let t = if entry.file_type().ok()?.is_dir() { newest_mtime(&entry.path()) } else { entry.metadata().ok()?.modified().ok() };
        best = best.max(t);
    }
    best
}

/// The frame event's dt: the time since the last frame, zero while paused
/// so anything animated per frame holds still.
fn frame_dt(eng: &Shared, dt: f32) -> f32 {
    if eng.borrow().paused { 0.0 } else { dt }
}

/// Key events go to the game, or to menus while it's paused.
fn key_event(eng: &Shared) -> &'static str {
    if eng.borrow().paused { "menu_key" } else { "key" }
}

/// One simulation tick: scripts think, physics moves, contacts are reported.
/// One fixed step. Returns the seconds spent in Lua and in physics.
fn tick(eng: &Shared, script: &Script) -> (f64, f64) {
    let dt = (1.0 / TICK_HZ) as f32;
    let t0 = now();
    eng.borrow_mut().snapshot();
    script.emit(eng, "tick", dt);
    let t1 = now();
    let contacts = eng.borrow_mut().step(dt);
    let t2 = now();
    for c in contacts {
        script.emit(eng, "contact", (c.a, c.b, c.speed, c.broke));
    }
    (t1 - t0 + now() - t2, t2 - t1)
}

/// Seconds on a clock that also works in the browser (`Instant` doesn't).
fn now() -> f64 {
    miniquad::date::now()
}

/// PROFILE=1: every two seconds, print where the frames' time went: the
/// average frame, the worst one, and the Lua handlers slowest in one call.
#[derive(Default)]
struct Profile {
    on: bool,
    since: Option<f64>,
    frames: u32,
    ticks: u32,
    tick_lua: f64,
    physics: f64,
    frame_lua: f64,
    draw: f64,
    /// The totals above as they were when the last frame ended.
    last: Option<(f64, f64, f64, f64, f64, u32)>,
    /// The longest frame: its seconds, its share of each total, its ticks.
    worst: (f64, [f64; 4], u32),
    /// Frames longer than LONG_FRAME.
    long: u32,
    /// GPU seconds over that many frames (GL timer queries; None if the
    /// driver has none).
    gpu: Option<(f64, u32)>,
    /// Which GPU, printed once with the first report.
    gpu_name: Option<String>,
}

/// A frame this long (two frames missed at 60 fps) is a visible stutter.
const LONG_FRAME: f64 = 0.050;

impl Profile {
    fn frame_done(&mut self, draw_calls: usize, triangles: usize, script: Option<&Script>) {
        if !self.on {
            return;
        }
        let t = now();
        self.frames += 1;
        let (end, lua, physics, frame_lua, draw, ticks) =
            self.last.unwrap_or((*self.since.get_or_insert(t), self.tick_lua, self.physics, self.frame_lua, self.draw, self.ticks));
        let took = t - end;
        let parts = [self.tick_lua - lua, self.physics - physics, self.frame_lua - frame_lua, self.draw - draw];
        if took > self.worst.0 {
            self.worst = (took, parts, self.ticks - ticks);
        }
        self.long += (took > LONG_FRAME) as u32;
        self.last = Some((t, self.tick_lua, self.physics, self.frame_lua, self.draw, self.ticks));
        let secs = t - *self.since.get_or_insert(t);
        if secs < 2.0 {
            return;
        }
        let (f, ms) = (self.frames as f64, |s: f64| s * 1e3 / self.frames as f64);
        if let Some(name) = self.gpu_name.take() {
            println!("profile: GPU {name}");
            let soft = ["llvmpipe", "softpipe", "software", "swrast", "Microsoft Basic Render"];
            if soft.iter().any(|s| name.to_lowercase().contains(&s.to_lowercase())) {
                println!("profile:   that is SOFTWARE rendering on the CPU, not the graphics card: fix the GPU driver first");
            }
        }
        let gpu = match self.gpu {
            Some((s, n)) if n > 0 => format!("gpu {:.1} ms", s * 1e3 / n as f64),
            Some(_) => "gpu ?".to_string(),
            None => "gpu not timed".to_string(),
        };
        println!(
            "profile: {:.1} fps | {:.2} ticks/frame: Lua {:.1} ms + physics {:.1} ms | frame Lua {:.1} ms | \
             draw {:.1} ms, {draw_calls} calls, {:.2} M triangles | {gpu} | waiting {:.1} ms",
            f / secs,
            self.ticks as f64 / f,
            ms(self.tick_lua),
            ms(self.physics),
            ms(self.frame_lua),
            ms(self.draw),
            triangles as f64 / 1e6,
            // The rest of the frame: the GPU and the display. High here and
            // low elsewhere means the GPU is the limit.
            (secs - self.tick_lua - self.physics - self.frame_lua - self.draw) * 1e3 / f
        );
        let (took, [lua, physics, frame_lua, draw], ticks) = self.worst;
        let ms = |s: f64| s * 1e3;
        println!(
            "profile:   worst frame {:.1} ms: {ticks} ticks Lua {:.1} + physics {:.1}, frame Lua {:.1}, draw {:.1}, \
             waiting {:.1} | {} frames over {:.0} ms",
            ms(took),
            ms(lua),
            ms(physics),
            ms(frame_lua),
            ms(draw),
            ms(took - lua - physics - frame_lua - draw),
            self.long,
            ms(LONG_FRAME)
        );
        for line in script.map(|s| s.slowest(3)).unwrap_or_default() {
            println!("profile:   slowest Lua: {line}");
        }
        let gpu = self.gpu.map(|_| (0.0, 0));
        *self = Profile { on: true, since: Some(t), gpu, ..Default::default() };
    }
}

/// Engine::uploader for the windowed game: straight to this renderer.
fn uploader(gfx: &Rc<RefCell<render::Renderer>>) -> engine::Uploader {
    let gfx = gfx.clone();
    Box::new(move |epoch, id, rev, m| gfx.borrow_mut().upload(epoch, id, rev, m))
}

fn load(eng: &Shared) -> Option<Script> {
    match Script::load(eng) {
        Ok(s) => {
            s.emit(eng, "init", ());
            Some(s)
        }
        Err(e) => {
            script::report(eng, "load", &e.to_string());
            None
        }
    }
}

fn run_headless(root: PathBuf, ticks: u64, saves: save::Store, fullscreen: bool) {
    let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
    let eng: Shared = Rc::new(RefCell::new(Engine::new(root, mixer.clone())));
    eng.borrow_mut().saves = saves;
    eng.borrow_mut().fullscreen = fullscreen;
    eng.borrow_mut().headless = true;
    // Mix (and discard) audio in step with ticks so headless runs exercise it too.
    let mut sink = vec![0.0f32; 2 * (audio::RATE as f64 / TICK_HZ) as usize];
    let mut script = load(&eng);
    let t0 = std::time::Instant::now();
    let mut n = 0;
    // PROFILE=1: each tick is a frame (no drawing), timed the same way.
    let mut profile = Profile { on: script::profiling(), ..Default::default() };
    while let Some(s) = &script {
        if n >= ticks {
            s.emit(&eng, "quit", ());
            break;
        }
        n += 1;
        if !eng.borrow().paused {
            let (lua, physics) = tick(&eng, s);
            profile.ticks += 1;
            profile.tick_lua += lua;
            profile.physics += physics;
        }
        eng.borrow_mut().hud.clear();
        eng.borrow_mut().hud_clip = None;
        let t = now();
        s.emit(&eng, "frame", frame_dt(&eng, (1.0 / TICK_HZ) as f32));
        profile.frame_lua += now() - t;
        profile.frame_done(0, 0, Some(s));
        eng.borrow_mut().update_audio();
        mixer.lock().unwrap().mix(&mut sink);
        if eng.borrow().quit {
            s.emit(&eng, "quit", ());
            break;
        }
        // engine.reload(), as the windowed game does it: the old scripts
        // save, then everything starts afresh, saves kept.
        if std::mem::take(&mut eng.borrow_mut().reload) {
            s.emit(&eng, "quit", ());
            let (root, saves, fullscreen) = {
                let mut e = eng.borrow_mut();
                (e.root.clone(), std::mem::take(&mut e.saves), e.fullscreen)
            };
            drop(script.take()); // the old Lua state goes before the new one is built
            *eng.borrow_mut() = Engine::new(root, mixer.clone());
            eng.borrow_mut().saves = saves;
            eng.borrow_mut().fullscreen = fullscreen;
            script = load(&eng);
            println!("reloaded");
        }
    }
    let e = eng.borrow();
    // MESH_REPORT=1: where the mesh memory goes, by name with its chunk or
    // road number dropped ("road12" and "road7" are both "road").
    if std::env::var_os("MESH_REPORT").is_some() {
        let mut by: std::collections::HashMap<&str, (usize, usize)> = Default::default();
        for (name, &id) in &e.mesh_ids {
            let m = &e.meshes[id];
            let v = by.entry(name.trim_end_matches(|c: char| c.is_ascii_digit() || ",-_".contains(c))).or_default();
            v.0 += m.verts.len() * size_of::<mesh::Vertex>() + m.indices.len() * 4;
            v.1 += 1;
        }
        let mut by: Vec<_> = by.into_iter().collect();
        by.sort_by_key(|(_, (bytes, _))| std::cmp::Reverse(*bytes));
        for (name, (bytes, n)) in by.iter().take(12) {
            println!("mesh {name:24} {:6.1} MB in {n}", *bytes as f64 / 1e6);
        }
    }
    let mesh_mb = e.meshes.iter().map(|m| m.verts.len() * size_of::<mesh::Vertex>() + m.indices.len() * 4).sum::<usize>() as f64 / 1e6;
    println!(
        "headless: {} ticks in {:.1} ms, {} entities, {} meshes ({mesh_mb:.0} MB)",
        e.tick,
        t0.elapsed().as_secs_f64() * 1e3,
        e.live,
        e.meshes.len()
    );
    if e.error.is_some() {
        std::process::exit(1);
    }
}

struct App {
    eng: Shared,
    _audio: Option<audio::Output>,
    script: Option<Script>,
    gfx: Rc<RefCell<render::Renderer>>,
    profile: Profile,
    acc: f64,
    last: f64,
    /// When a key, button, the mouse or a touch last did anything.
    input_at: f64,
    /// Seconds between the last two frames.
    frame_time: f32,
    watch_at: f64,
    mtime: Option<SystemTime>,
    reload: bool,
    frame: u64,
    grabbed: bool,
    shot: Option<(String, u64)>,
    /// --record: every drawn frame appended here, raw RGB, top row first.
    record: Option<std::io::BufWriter<std::fs::File>>,
    quit_after: Option<u64>,
    ticks_per_frame: u32,
    closed: bool,
    fullscreen: bool,
    pads: pad::Pads,
    /// Seconds per frame to hold to (--fps), and when this frame began.
    target_frame: Option<f64>,
    frame_start: f64,
    failed: Rc<Cell<bool>>,
}

impl App {
    /// Tell scripts the game is closing (once), so they can save.
    fn close(&mut self) {
        if let Some(out) = &mut self.record {
            use std::io::Write;
            let _ = out.flush();
        }
        if !std::mem::replace(&mut self.closed, true)
            && let Some(s) = &self.script
        {
            s.emit(&self.eng, "quit", ());
        }
        self.failed.set(self.failed.get() || self.eng.borrow().error.is_some());
    }

    fn reload(&mut self) {
        // The old scripts get to save before they're replaced.
        if let Some(s) = &self.script {
            s.emit(&self.eng, "quit", ());
        }
        self.failed.set(self.failed.get() || self.eng.borrow().error.is_some());
        let (root, screen, mixer, saves, fullscreen) = {
            let mut e = self.eng.borrow_mut();
            (e.root.clone(), e.screen, e.mixer.clone(), std::mem::take(&mut e.saves), e.fullscreen)
        };
        // Drop the old Lua state before building the new one.
        self.script = None;
        *self.eng.borrow_mut() = Engine::new(root, mixer);
        self.eng.borrow_mut().uploader = Some(uploader(&self.gfx));
        self.eng.borrow_mut().screen = screen;
        self.eng.borrow_mut().saves = saves;
        self.eng.borrow_mut().fullscreen = fullscreen;
        self.script = load(&self.eng);
        self.acc = 0.0;
        println!("reloaded");
    }
}

impl EventHandler for App {
    fn update(&mut self) {
        let now = miniquad::date::now();
        let dt = (now - self.last).min(0.25);
        self.last = now;
        self.frame_time = dt as f32;
        if now >= self.watch_at {
            self.watch_at = now + 0.5;
            let m = newest_mtime(&self.eng.borrow().root);
            if m != self.mtime {
                self.reload |= self.mtime.is_some();
                self.mtime = m;
            }
        }
        let asked = std::mem::take(&mut self.eng.borrow_mut().reload);
        if std::mem::take(&mut self.reload) || asked {
            self.reload();
        }
        self.poll_pads(now);
        let Some(script) = &self.script else { return };
        if self.eng.borrow().paused {
            self.acc = 0.0;
            // Paused, nothing moves: about 20 frames a second is plenty for
            // the menu, and 4 once it's been left alone for a few seconds
            // (lib/menu pauses a game left alone), so the machine gets its
            // cores back: a game left in its menu drew the whole city at
            // full rate. A pad's sticks count as a touch too.
            #[cfg(not(target_arch = "wasm32"))]
            {
                let stick =
                    self.eng.borrow().pad.as_ref().is_some_and(|p| [p.lx, p.ly, p.rx, p.ry, p.lt, p.rt].iter().any(|v| v.abs() > 0.2));
                if stick {
                    self.input_at = now;
                }
                let ms = if now - self.input_at > 5.0 { 250 } else { 45 };
                std::thread::sleep(std::time::Duration::from_millis(ms));
            }
            return;
        }
        // Fixed timestep; in screenshot mode advance exactly one tick per frame.
        self.acc += if self.shot.is_some() || self.quit_after.is_some() { self.ticks_per_frame as f64 / TICK_HZ } else { dt };
        while self.acc >= 1.0 / TICK_HZ {
            self.acc -= 1.0 / TICK_HZ;
            let (lua, physics) = tick(&self.eng, script);
            self.profile.ticks += 1;
            self.profile.tick_lua += lua;
            self.profile.physics += physics;
        }
    }

    fn draw(&mut self) {
        let (w, h) = window::screen_size();
        {
            let mut e = self.eng.borrow_mut();
            e.screen = (w, h);
            e.hud.clear();
            e.hud_clip = None;
        }
        // Draw between the last two ticks, as far along as the clock is
        // toward the next (screenshots step whole ticks, so are always at one).
        let fixed = self.shot.is_some() || self.quit_after.is_some();
        let along = if fixed || self.eng.borrow().paused { 1.0 } else { (self.acc * TICK_HZ).clamp(0.0, 1.0) as f32 };
        let saved = self.eng.borrow_mut().blend(along);
        if let Some(s) = &self.script {
            let dt = if fixed { self.ticks_per_frame as f32 / TICK_HZ as f32 } else { self.frame_time };
            let t = now();
            s.emit(&self.eng, "frame", frame_dt(&self.eng, dt));
            self.profile.frame_lua += now() - t;
        }
        self.eng.borrow_mut().update_audio();
        self.eng.borrow_mut().update_stream(fixed);
        {
            let mut e = self.eng.borrow_mut();
            e.mouse_delta = (0.0, 0.0);
            if let Some(err) = e.error.clone() {
                let msg: String = err.lines().take(12).collect::<Vec<_>>().join("\n");
                e.hud_rect(0.0, 0.0, w, 20.0 + 18.0 * msg.lines().count() as f32, [0.3, 0.0, 0.0, 0.85]);
                e.hud_text(&msg, 10.0, 10.0, 12.0, [1.0, 0.8, 0.8, 1.0]);
            }
            if e.fullscreen != self.fullscreen {
                self.fullscreen = e.fullscreen;
                window::set_fullscreen(self.fullscreen);
            }
            if e.mouse_grab != self.grabbed {
                self.grabbed = e.mouse_grab;
                window::set_cursor_grab(self.grabbed);
                window::show_mouse(!self.grabbed);
            }
        }
        let t = now();
        // (The borrow ends before anything can run Lua: a script making a big
        // mesh sends it to this renderer.)
        let gfx_rc = self.gfx.clone();
        let mut gfx = gfx_rc.borrow_mut();
        gfx.draw(&self.eng.borrow());
        self.profile.draw += now() - t;
        let uploaded = gfx.take_uploaded();
        self.eng.borrow_mut().release_uploaded(&uploaded);
        if gfx.take_ground()
            && let Some(g) = self.eng.borrow_mut().ground_map.as_mut()
        {
            g.idx = Vec::new();
        }
        self.eng.borrow_mut().unblend(saved);
        self.frame += 1;
        let mut shot_done = false;
        if let Some((path, at)) = &self.shot
            && self.frame == *at
        {
            match gfx.screenshot(path, w as i32, h as i32) {
                Ok(()) => println!("screenshot: {path} ({} draw calls)", gfx.draw_calls),
                Err(e) => eprintln!("screenshot failed: {e}"),
            }
            shot_done = true;
        }
        if let Some(out) = &mut self.record {
            use std::io::Write;
            if let Err(e) = out.write_all(&gfx.read_rgb(w as i32, h as i32)) {
                eprintln!("record failed: {e}");
                self.record = None;
            }
        }
        gfx.commit();
        if let (Some(timer), Some(gpu)) = (&mut gfx.gpu_timer, &mut self.profile.gpu) {
            let (s, n) = timer.take();
            *gpu = (gpu.0 + s, gpu.1 + n);
        }
        self.profile.frame_done(gfx.draw_calls, gfx.triangles, self.script.as_ref());
        drop(gfx);
        if shot_done {
            self.close();
            window::order_quit();
        }
        if let Some(target) = self.target_frame {
            let elapsed = miniquad::date::now() - self.frame_start;
            if elapsed < target {
                std::thread::sleep(std::time::Duration::from_secs_f64(target - elapsed));
            }
            self.frame_start = miniquad::date::now();
        }
        if self.eng.borrow().quit || self.quit_after == Some(self.frame) {
            self.close();
            window::order_quit();
        }
    }

    fn key_down_event(&mut self, key: KeyCode, _m: KeyMods, repeat: bool) {
        if key == KeyCode::F5 {
            self.reload = true;
            return;
        }
        if key == KeyCode::Escape {
            self.eng.borrow_mut().mouse_grab = false;
        }
        let name = key_name(key);
        if repeat || name.is_empty() {
            return;
        }
        self.press(name, true);
    }

    fn key_up_event(&mut self, key: KeyCode, _m: KeyMods) {
        self.press(key_name(key), false);
    }

    fn mouse_button_down_event(&mut self, b: MouseButton, _x: f32, _y: f32) {
        self.mouse_button(b, true);
    }

    fn mouse_button_up_event(&mut self, b: MouseButton, _x: f32, _y: f32) {
        self.mouse_button(b, false);
    }

    fn mouse_motion_event(&mut self, x: f32, y: f32) {
        self.input_at = miniquad::date::now();
        self.eng.borrow_mut().cursor = (x, y);
    }

    /// Touches go to the scripts as they are (lib/touch.lua draws the
    /// controls), not as mouse clicks: a tap would fire the gun.
    fn touch_event(&mut self, phase: miniquad::TouchPhase, id: u64, x: f32, y: f32) {
        self.input_at = miniquad::date::now();
        let phase = match phase {
            miniquad::TouchPhase::Started => "start",
            miniquad::TouchPhase::Moved => "move",
            miniquad::TouchPhase::Ended => "end",
            miniquad::TouchPhase::Cancelled => "cancel",
        };
        if let Some(s) = &self.script {
            s.emit(&self.eng, "touch", (phase, id, x, y));
        }
    }

    fn window_minimized_event(&mut self) {
        if let Some(s) = &self.script {
            s.emit(&self.eng, "minimized", ());
        }
    }

    fn quit_requested_event(&mut self) {
        self.close();
    }

    fn raw_mouse_motion(&mut self, dx: f32, dy: f32) {
        let mut e = self.eng.borrow_mut();
        e.mouse_delta.0 += dx;
        e.mouse_delta.1 += dy;
    }
}

impl App {
    /// A key, mouse button or pad button went down or up.
    fn press(&mut self, name: &str, down: bool) {
        self.input_at = miniquad::date::now();
        if down {
            self.eng.borrow_mut().keys.insert(name.to_string());
        } else {
            self.eng.borrow_mut().keys.remove(name);
        }
        if let Some(s) = &self.script {
            s.emit(&self.eng, key_event(&self.eng), (name, down));
        }
    }

    /// Gamepad buttons arrive as keys; sticks and triggers are read with engine.pad().
    fn poll_pads(&mut self, now: f64) {
        let mut events = Vec::new();
        self.pads.poll(now, &mut events);
        self.eng.borrow_mut().pad = self.pads.state().cloned();
        for ev in events {
            let (name, connected) = match ev {
                pad::Event::Button(name, down) => {
                    self.press(name, down);
                    continue;
                }
                pad::Event::Connected(name) => (name, true),
                pad::Event::Disconnected(name) => (name, false),
            };
            println!("gamepad {}: {name}", if connected { "connected" } else { "disconnected" });
            if let Some(s) = &self.script {
                s.emit(&self.eng, if connected { "pad_connected" } else { "pad_disconnected" }, name.as_str());
            }
        }
    }

    fn mouse_button(&mut self, b: MouseButton, down: bool) {
        let name = match b {
            MouseButton::Left => "mouse1",
            MouseButton::Right => "mouse2",
            MouseButton::Middle => "mouse3",
            MouseButton::Unknown => return,
        };
        self.press(name, down);
    }
}

fn key_name(k: KeyCode) -> &'static str {
    use KeyCode::*;
    match k {
        A => "a",
        B => "b",
        C => "c",
        D => "d",
        E => "e",
        F => "f",
        G => "g",
        H => "h",
        I => "i",
        J => "j",
        K => "k",
        L => "l",
        M => "m",
        N => "n",
        O => "o",
        P => "p",
        Q => "q",
        R => "r",
        S => "s",
        T => "t",
        U => "u",
        V => "v",
        W => "w",
        X => "x",
        Y => "y",
        Z => "z",
        Key0 => "0",
        Key1 => "1",
        Key2 => "2",
        Key3 => "3",
        Key4 => "4",
        Key5 => "5",
        Key6 => "6",
        Key7 => "7",
        Key8 => "8",
        Key9 => "9",
        Space => "space",
        Enter => "enter",
        Escape => "escape",
        Tab => "tab",
        Backspace => "backspace",
        Up => "up",
        Down => "down",
        Left => "left",
        Right => "right",
        LeftShift | RightShift => "shift",
        LeftControl | RightControl => "ctrl",
        LeftAlt | RightAlt => "alt",
        F1 => "f1",
        F2 => "f2",
        F3 => "f3",
        F4 => "f4",
        F6 => "f6",
        F7 => "f7",
        F8 => "f8",
        F9 => "f9",
        _ => "",
    }
}

fn main() {
    #[cfg(target_arch = "wasm32")]
    web::init();
    let o = match parse_args() {
        Ok(o) => o,
        Err(e) => {
            eprintln!("auto: {e}");
            std::process::exit(2);
        }
    };
    let saves = save_store(&o);
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    if let Some(render_size) = o.render_size {
        if let Err(error) = run_wgpu_postcard(o, render_size, saves) {
            eprintln!("auto: {error}");
            std::process::exit(1);
        }
        return;
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    if o.wgpu && o.headless.is_none() {
        if let Err(error) = window2::run(o, saves) {
            eprintln!("auto: {error}");
            std::process::exit(1);
        }
        return;
    }
    if let Some(ticks) = o.headless {
        return run_headless(o.root, ticks, saves, o.fullscreen);
    }
    let conf = conf::Conf {
        window_title: "auto".into(),
        window_width: o.size.0,
        window_height: o.size.1,
        fullscreen: o.fullscreen,
        sample_count: 4,
        window_resizable: true,
        platform: conf::Platform { webgl_version: conf::WebGLVersion::WebGL2, ..Default::default() },
        ..Default::default()
    };
    let (root, shot, record, frames, ticks_per_frame, fps, fullscreen) =
        (o.root, o.screenshot, o.record, o.frames, o.ticks_per_frame.max(1), o.fps, o.fullscreen);
    // (A browser paces frames itself.)
    let target_frame = (shot.is_none() && frames.is_none() && fps > 0 && !cfg!(target_arch = "wasm32")).then(|| 1.0 / fps as f64);
    let failed = Rc::new(Cell::new(false));
    let result = failed.clone();
    miniquad::start(conf, move || {
        let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
        let out = audio::start(mixer.clone());
        let eng: Shared = Rc::new(RefCell::new(Engine::new(root.clone(), mixer)));
        eng.borrow_mut().saves = saves;
        eng.borrow_mut().fullscreen = fullscreen;
        // The renderer first, so the city's meshes can go to the GPU as
        // they're built (see Engine::uploader).
        let gfx = Rc::new(RefCell::new(render::Renderer::new()));
        eng.borrow_mut().uploader = Some(uploader(&gfx));
        let script = load(&eng);
        let mtime = newest_mtime(&root);
        let mut profile = Profile { on: script::profiling(), ..Default::default() };
        if profile.on {
            let mut g = gfx.borrow_mut();
            g.time_gpu();
            profile.gpu = g.gpu_timer.as_ref().map(|_| (0.0, 0));
            profile.gpu_name = Some(g.gpu_name());
        }
        Box::new(App {
            eng,
            _audio: out,
            script,
            gfx,
            acc: 0.0,
            frame_time: (1.0 / TICK_HZ) as f32,
            last: miniquad::date::now(),
            input_at: miniquad::date::now(),
            watch_at: 0.0,
            mtime,
            reload: false,
            frame: 0,
            grabbed: false,
            quit_after: if shot.is_none() { frames } else { None },
            shot: shot.map(|p| (p, frames.unwrap_or(120))),
            record: record.map(|p| {
                let f = std::fs::File::create(&p).unwrap_or_else(|e| panic!("--record {p}: {e}"));
                std::io::BufWriter::with_capacity(1 << 20, f)
            }),
            ticks_per_frame,
            closed: false,
            fullscreen,
            pads: pad::Pads::new(),
            target_frame,
            frame_start: miniquad::date::now(),
            profile,
            failed,
        })
    });
    if result.get() {
        std::process::exit(1);
    }
}

#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
fn run_wgpu_postcard(o: Opts, render_size: (u32, u32), saves: save::Store) -> Result<(), String> {
    let path = o.screenshot.clone().ok_or("--render-size requires --screenshot")?;
    if o.headless.is_some() || o.record.is_some() || o.fullscreen {
        return Err("--render-size screenshots are a separate capture mode".into());
    }
    let output_size = (u32::try_from(o.size.0).map_err(|_| "bad output width")?, u32::try_from(o.size.1).map_err(|_| "bad output height")?);
    let frames = o.frames.unwrap_or(5);
    if frames == 0 {
        return Err("--frames must be positive".into());
    }
    let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
    let eng: Shared = Rc::new(RefCell::new(Engine::new(o.root.clone(), mixer)));
    eng.borrow_mut().saves = saves;
    eng.borrow_mut().skinning = true;
    eng.borrow_mut().screen = (output_size.0 as f32, output_size.1 as f32);
    let s = load(&eng).ok_or("could not load the Lua game")?;
    let ticks_per_frame = o.ticks_per_frame.max(1);
    let delta = ticks_per_frame as f32 / TICK_HZ as f32;
    if let Some(seconds) = std::env::var("FLY").ok().and_then(|v| v.parse::<f64>().ok()) {
        return fly_bench(&eng, &s, seconds, render_size, output_size, &o);
    }
    for _ in 0..frames {
        if !eng.borrow().paused {
            for _ in 0..ticks_per_frame {
                tick(&eng, &s);
            }
        }
        {
            let mut state = eng.borrow_mut();
            state.hud.clear();
            state.hud_clip = None;
        }
        s.emit(&eng, "frame", frame_dt(&eng, delta));
        eng.borrow_mut().update_stream(true);
        if let Some(error) = &eng.borrow().error {
            return Err(error.clone());
        }
    }
    render2::postcard(
        &eng.borrow(),
        render_size,
        output_size,
        o.upscale.unwrap_or_default(),
        o.material_pack.as_deref(),
        o.hdr,
        Path::new(&path),
    )
}

/// FLY=seconds with --render-size: the game's frames for that long at 60 a
/// second (the game moves the camera: main.lua flies a loop round the map),
/// drawn offscreen with streaming as in play, each frame's CPU time (the
/// scripts, streaming, culling, uploads and recording) and GPU time
/// measured. Stalls from loading tiles show as the worst CPU frames.
#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
fn fly_bench(
    eng: &Shared,
    s: &script::Script,
    seconds: f64,
    render_size: (u32, u32),
    output_size: (u32, u32),
    o: &Opts,
) -> Result<(), String> {
    let mut renderer =
        render2::offscreen(&eng.borrow(), render_size, output_size, o.upscale.unwrap_or_default(), o.material_pack.as_deref(), o.hdr)?;
    let frames = (seconds * 60.0).round() as usize;
    let dt = 1.0 / 60.0;
    let (mut cpu, mut gpu, mut stream_ms, mut shadow_ms) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let (mut loaded, mut dropped, mut most_resident, mut worst_at) = (0, 0, 0, (0.0, 0));
    let mut ticks = 0.0;
    for f in 0..frames {
        let start = std::time::Instant::now();
        ticks += dt * TICK_HZ;
        while ticks >= 1.0 {
            tick(eng, s);
            ticks -= 1.0;
        }
        let ticked = start.elapsed().as_secs_f64() * 1000.0;
        {
            let mut e = eng.borrow_mut();
            e.hud.clear();
            e.hud_clip = None;
        }
        let t = std::time::Instant::now();
        s.emit(eng, "frame", dt as f32);
        let frame_lua = t.elapsed().as_secs_f64() * 1000.0;
        let t = std::time::Instant::now();
        eng.borrow_mut().update_stream(false);
        stream_ms.push(t.elapsed().as_secs_f64() * 1000.0);
        if let Some(error) = &eng.borrow().error {
            return Err(error.clone());
        }
        let (encoder, _) = renderer.encode(&eng.borrow())?;
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        // A slow frame after the start: say where its time went.
        if f >= 60 && ms > 25.0 {
            println!(
                "fly: slow frame {f}: {ms:.1} ms = ticks {ticked:.1} + frame Lua {frame_lua:.1} + streaming {:.1} + drawing {:.1}",
                stream_ms.last().unwrap_or(&0.0),
                ms - ticked - frame_lua - stream_ms.last().unwrap_or(&0.0)
            );
        }
        // The first second is the start: everything near the camera loads.
        if f >= 60 && ms > worst_at.0 {
            worst_at = (ms, f);
        }
        cpu.push(ms);
        if let Some((g, stages)) = renderer.gpu_stages(encoder)? {
            gpu.push(g);
            shadow_ms.push(stages[0]);
        }
        let st = eng.borrow().streamer.stats;
        loaded += st.loaded;
        dropped += st.dropped;
        most_resident = most_resident.max(st.resident);
    }
    let pct = |v: &mut Vec<f64>, q: f64| {
        v.sort_by(f64::total_cmp);
        v.get(((v.len().max(1) - 1) as f64 * q).round() as usize).copied().unwrap_or(0.0)
    };
    let worst_stream = stream_ms.iter().copied().fold(0.0, f64::max);
    println!(
        "fly: sun shadows GPU ms median {:.2}, p99 {:.2}; the cached near layer redrawn in {} of {frames} frames",
        pct(&mut shadow_ms, 0.5),
        pct(&mut shadow_ms, 0.99),
        renderer.still_redraws()
    );
    println!(
        "fly: {frames} frames; CPU ms median {:.2}, p99 {:.2}, worst after the first second {:.2} (frame {}); GPU ms median {:.2}, p99 {:.2}, worst {:.2}",
        pct(&mut cpu, 0.5),
        pct(&mut cpu, 0.99),
        worst_at.0,
        worst_at.1,
        pct(&mut gpu, 0.5),
        pct(&mut gpu, 0.99),
        pct(&mut gpu, 1.0)
    );
    println!(
        "fly: streaming loaded {loaded} and dropped {dropped} meshes, at most {most_resident} of {} in memory; stream update ms median {:.2}, worst {worst_stream:.2}",
        eng.borrow().streamer.len(),
        pct(&mut stream_ms, 0.5)
    );
    Ok(())
}
