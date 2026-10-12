//! auto: a minimal 3D sandbox kernel. The binary renders, simulates and
//! forwards input; the game is whatever Lua scripts the data directory holds.
//!
//!   auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--frames N] [--size WxH] [--save-dir DIR]

mod audio;
mod engine;
mod font;
mod math;
mod mesh;
mod physics;
mod render;
mod save;
mod script;

use engine::{Engine, TICK_HZ};
use miniquad::{EventHandler, KeyCode, KeyMods, MouseButton, conf, window};
use script::{Script, Shared};
use std::cell::RefCell;
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
                    "usage: auto [GAME_DIR] [--headless TICKS] [--screenshot OUT.ppm] [--frames N] [--ticks-per-frame K] [--size WxH] [--save-dir DIR]"
                );
                std::process::exit(0);
            }
            s if s.starts_with('-') => return Err(format!("unknown flag {s}")),
            s => o.root = PathBuf::from(s),
        }
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
    let mut best = None;
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let t = if entry.file_type().ok()?.is_dir() { newest_mtime(&entry.path()) } else { entry.metadata().ok()?.modified().ok() };
        best = best.max(t);
    }
    best
}

/// The frame event's dt: zero while paused, so anything animated per frame holds still.
fn frame_dt(eng: &Shared) -> f32 {
    if eng.borrow().paused { 0.0 } else { (1.0 / TICK_HZ) as f32 }
}

/// Key events go to the game, or to menus while it's paused.
fn key_event(eng: &Shared) -> &'static str {
    if eng.borrow().paused { "menu_key" } else { "key" }
}

/// One simulation tick: scripts think, physics moves, contacts are reported.
fn tick(eng: &Shared, script: &Script) {
    let dt = (1.0 / TICK_HZ) as f32;
    script.emit(eng, "tick", dt);
    let contacts = eng.borrow_mut().step(dt);
    for c in contacts {
        script.emit(eng, "contact", (c.a, c.b, c.speed));
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

fn run_headless(root: PathBuf, ticks: u64, saves: save::Store) {
    let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
    let eng: Shared = Rc::new(RefCell::new(Engine::new(root, mixer.clone())));
    eng.borrow_mut().saves = saves;
    // Mix (and discard) audio in step with ticks so headless runs exercise it too.
    let mut sink = vec![0.0f32; 2 * (audio::RATE as f64 / TICK_HZ) as usize];
    let script = load(&eng);
    let t0 = std::time::Instant::now();
    if let Some(s) = &script {
        for _ in 0..ticks {
            if !eng.borrow().paused {
                tick(&eng, s);
            }
            eng.borrow_mut().hud.clear();
            s.emit(&eng, "frame", frame_dt(&eng));
            eng.borrow_mut().update_audio();
            mixer.lock().unwrap().mix(&mut sink);
            if eng.borrow().quit {
                break;
            }
        }
        s.emit(&eng, "quit", ());
    }
    let e = eng.borrow();
    println!("headless: {} ticks in {:.1} ms, {} entities, {} meshes", e.tick, t0.elapsed().as_secs_f64() * 1e3, e.live, e.meshes.len());
    if e.error.is_some() {
        std::process::exit(1);
    }
}

struct App {
    eng: Shared,
    _audio: Option<audio::Output>,
    script: Option<Script>,
    gfx: render::Renderer,
    acc: f64,
    last: f64,
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
}

impl App {
    /// Tell scripts the game is closing (once), so they can save.
    fn close(&mut self) {
        if !std::mem::replace(&mut self.closed, true)
            && let Some(s) = &self.script
        {
            s.emit(&self.eng, "quit", ());
        }
    }

    fn reload(&mut self) {
        // The old scripts get to save before they're replaced.
        if let Some(s) = &self.script {
            s.emit(&self.eng, "quit", ());
        }
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
        if now >= self.watch_at {
            self.watch_at = now + 0.5;
            let m = newest_mtime(&self.eng.borrow().root);
            if m != self.mtime {
                self.reload |= self.mtime.is_some();
                self.mtime = m;
            }
        }
        if std::mem::take(&mut self.reload) {
            self.reload();
        }
        let Some(script) = &self.script else { return };
        if self.eng.borrow().paused {
            self.acc = 0.0;
            return;
        }
        // Fixed timestep; in screenshot mode advance exactly one tick per frame.
        self.acc += if self.shot.is_some() || self.quit_after.is_some() { self.ticks_per_frame as f64 / TICK_HZ } else { dt };
        while self.acc >= 1.0 / TICK_HZ {
            self.acc -= 1.0 / TICK_HZ;
            tick(&self.eng, script);
        }
    }

    fn draw(&mut self) {
        let (w, h) = window::screen_size();
        {
            let mut e = self.eng.borrow_mut();
            e.screen = (w, h);
            e.hud.clear();
        }
        if let Some(s) = &self.script {
            s.emit(&self.eng, "frame", frame_dt(&self.eng));
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
        self.gfx.draw(&self.eng.borrow());
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
        self.eng.borrow_mut().keys.insert(name.to_string());
        if let Some(s) = &self.script {
            s.emit(&self.eng, key_event(&self.eng), (name, true));
        }
    }

    fn key_up_event(&mut self, key: KeyCode, _m: KeyMods) {
        let name = key_name(key);
        self.eng.borrow_mut().keys.remove(name);
        if let Some(s) = &self.script {
            s.emit(&self.eng, key_event(&self.eng), (name, false));
        }
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
    fn mouse_button(&mut self, b: MouseButton, down: bool) {
        let name = match b {
            MouseButton::Left => "mouse1",
            MouseButton::Right => "mouse2",
            MouseButton::Middle => "mouse3",
            MouseButton::Unknown => return,
        };
        if down {
            self.eng.borrow_mut().keys.insert(name.into())
        } else {
            self.eng.borrow_mut().keys.remove(name)
        };
        if let Some(s) = &self.script {
            s.emit(&self.eng, key_event(&self.eng), (name, down));
        }
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
    let o = match parse_args() {
        Ok(o) => o,
        Err(e) => {
            eprintln!("auto: {e}");
            std::process::exit(2);
        }
    };
    let saves = save_store(&o);
    if let Some(ticks) = o.headless {
        return run_headless(o.root, ticks, saves);
    }
    let conf = conf::Conf {
        window_title: "auto".into(),
        window_width: o.size.0,
        window_height: o.size.1,
        sample_count: 4,
        window_resizable: true,
        ..Default::default()
    };
    let (root, shot, frames, ticks_per_frame) = (o.root, o.screenshot, o.frames, o.ticks_per_frame.max(1));
    miniquad::start(conf, move || {
        let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
        let out = audio::start(mixer.clone());
        let eng: Shared = Rc::new(RefCell::new(Engine::new(root.clone(), mixer)));
        eng.borrow_mut().saves = saves;
        let script = load(&eng);
        let mtime = newest_mtime(&root);
        Box::new(App {
            eng,
            _audio: out,
            script,
            gfx: render::Renderer::new(),
            acc: 0.0,
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
            fullscreen: false,
        })
    });
}
