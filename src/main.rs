//! auto: a minimal 3D sandbox kernel. The binary renders, simulates and
//! forwards input; the game is whatever Lua scripts the data directory holds.
//!
//!   auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--frames N] [--size WxH] [--save-dir DIR]

mod audio;
mod engine;
mod font;
mod math;
mod mesh;
mod pad;
mod physics;
mod render;
mod save;
mod script;
mod vfs;
#[cfg(target_arch = "wasm32")]
mod web;

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
    frames: Option<u64>,
    ticks_per_frame: u32,
    size: (i32, i32),
    save_dir: Option<PathBuf>,
    fps: u32,
    fullscreen: bool,
}

fn parse_args() -> Result<Opts, String> {
    let mut o = Opts {
        root: PathBuf::from("game"),
        headless: None,
        screenshot: None,
        frames: None,
        ticks_per_frame: 1,
        size: (1280, 720),
        save_dir: None,
        fps: 60,
        fullscreen: false,
    };
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = |name: &str| args.next().ok_or(format!("{name} needs a value"));
        match a.as_str() {
            "--headless" => o.headless = Some(val("--headless")?.parse().map_err(|_| "bad tick count")?),
            "--screenshot" => o.screenshot = Some(val("--screenshot")?),
            "--frames" => o.frames = Some(val("--frames")?.parse().map_err(|_| "bad frame count")?),
            "--ticks-per-frame" => o.ticks_per_frame = val("--ticks-per-frame")?.parse().map_err(|_| "bad tick count")?,
            "--save-dir" => o.save_dir = Some(PathBuf::from(val("--save-dir")?)),
            "--fps" => o.fps = val("--fps")?.parse().map_err(|_| "bad fps")?,
            "--fullscreen" => o.fullscreen = true,
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
                    "usage: auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--frames N] [--ticks-per-frame K] [--size WxH] [--save-dir DIR] [--fps N] [--fullscreen]"
                );
                std::process::exit(0);
            }
            s if s.starts_with('-') => return Err(format!("unknown flag {s}")),
            s => o.root = PathBuf::from(s),
        }
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
        return save::Store::default(); // for now: gone when the page closes
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
        script.emit(eng, "contact", (c.a, c.b, c.speed));
    }
    (t1 - t0 + now() - t2, t2 - t1)
}

/// Seconds on a clock that also works in the browser (`Instant` doesn't).
fn now() -> f64 {
    miniquad::date::now()
}

/// PROFILE=1: every two seconds, print where the frames' time went.
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
}

impl Profile {
    fn frame_done(&mut self, draw_calls: usize, triangles: usize) {
        if !self.on {
            return;
        }
        self.frames += 1;
        let secs = now() - *self.since.get_or_insert_with(now);
        if secs < 2.0 {
            return;
        }
        let (f, ms) = (self.frames as f64, |s: f64| s * 1e3 / self.frames as f64);
        println!(
            "profile: {:.1} fps | {:.2} ticks/frame: Lua {:.1} ms + physics {:.1} ms | frame Lua {:.1} ms | \
             draw {:.1} ms, {draw_calls} calls, {:.2} M triangles | waiting {:.1} ms",
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
        *self = Profile { on: true, ..Default::default() };
    }
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
    // Mix (and discard) audio in step with ticks so headless runs exercise it too.
    let mut sink = vec![0.0f32; 2 * (audio::RATE as f64 / TICK_HZ) as usize];
    let mut script = load(&eng);
    let t0 = std::time::Instant::now();
    let mut n = 0;
    while let Some(s) = &script {
        if n >= ticks {
            s.emit(&eng, "quit", ());
            break;
        }
        n += 1;
        if !eng.borrow().paused {
            let _ = tick(&eng, s);
        }
        eng.borrow_mut().hud.clear();
        s.emit(&eng, "frame", frame_dt(&eng, (1.0 / TICK_HZ) as f32));
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
    gfx: render::Renderer,
    profile: Profile,
    acc: f64,
    last: f64,
    /// Seconds between the last two frames.
    frame_time: f32,
    watch_at: f64,
    mtime: Option<SystemTime>,
    reload: bool,
    frame: u64,
    grabbed: bool,
    shot: Option<(String, u64)>,
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
        self.gfx.draw(&self.eng.borrow());
        self.profile.draw += now() - t;
        let uploaded = self.gfx.take_uploaded();
        self.eng.borrow_mut().release_uploaded(&uploaded);
        self.eng.borrow_mut().unblend(saved);
        self.frame += 1;
        if let Some((path, at)) = &self.shot
            && self.frame == *at
        {
            match self.gfx.screenshot(path, w as i32, h as i32) {
                Ok(()) => println!("screenshot: {path} ({} draw calls)", self.gfx.draw_calls),
                Err(e) => eprintln!("screenshot failed: {e}"),
            }
            self.close();
            window::order_quit();
        }
        self.gfx.commit();
        self.profile.frame_done(self.gfx.draw_calls, self.gfx.triangles);
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
        self.eng.borrow_mut().cursor = (x, y);
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
    let (root, shot, frames, ticks_per_frame, fps, fullscreen) =
        (o.root, o.screenshot, o.frames, o.ticks_per_frame.max(1), o.fps, o.fullscreen);
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
        let script = load(&eng);
        let mtime = newest_mtime(&root);
        Box::new(App {
            eng,
            _audio: out,
            script,
            gfx: render::Renderer::new(),
            acc: 0.0,
            frame_time: (1.0 / TICK_HZ) as f32,
            last: miniquad::date::now(),
            watch_at: 0.0,
            mtime,
            reload: false,
            frame: 0,
            grabbed: false,
            quit_after: if shot.is_none() { frames } else { None },
            shot: shot.map(|p| (p, frames.unwrap_or(120))),
            ticks_per_frame,
            closed: false,
            fullscreen,
            pads: pad::Pads::new(),
            target_frame,
            frame_start: miniquad::date::now(),
            profile: Profile { on: std::env::var("PROFILE").is_ok_and(|v| v == "1"), ..Default::default() },
            failed,
        })
    });
    if result.get() {
        std::process::exit(1);
    }
}
