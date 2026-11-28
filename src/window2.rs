//! The game in a window drawn by the wgpu renderer (`--wgpu`): winit for the
//! window and input, `render2::Renderer2` for the picture. The game logic is
//! the same as the OpenGL window's (`App` in main.rs): fixed 60 Hz ticks,
//! hot reload, keys and pads as named keys, the mouse as a delta.

use super::{Opts, frame_dt, key_event, load, newest_mtime, now, tick};
use crate::engine::{Engine, TICK_HZ};
use crate::render2::{Renderer2, Settings};
use crate::script::{Script, Shared};
use crate::{audio, pad, save};
use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;
use winit::application::ApplicationHandler;
use winit::dpi::PhysicalSize;
use winit::event::{DeviceEvent, DeviceId, ElementState, MouseButton, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{CursorGrabMode, Fullscreen, Window, WindowId};

struct Gfx {
    window: Arc<Window>,
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    renderer: Renderer2,
}

struct App2 {
    eng: Shared,
    script: Option<Script>,
    _audio: Option<audio::Output>,
    instance: wgpu::Instance,
    gfx: Option<Gfx>,
    /// Scene size as a fraction of the window's (the HUD is always full size).
    render_scale: f32,
    base: Settings,
    acc: f64,
    last: f64,
    frame_time: f32,
    frame: u64,
    watch_at: f64,
    mtime: Option<SystemTime>,
    reload: bool,
    grabbed: bool,
    fullscreen: bool,
    pads: pad::Pads,
    shot: Option<(String, u64)>,
    quit_after: Option<u64>,
    ticks_per_frame: u32,
    closed: bool,
    failed: bool,
    /// Frames drawn and seconds spent, for the "wgpu window:" line every 2 s.
    fps_frames: u32,
    fps_since: f64,
    /// The window's size when it opens.
    size_hint: (u32, u32),
}

pub fn run(o: Opts, saves: save::Store) -> Result<(), String> {
    let event_loop = EventLoop::new().map_err(|e| e.to_string())?;
    event_loop.set_control_flow(ControlFlow::Poll);
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_with_display_handle(Box::new(event_loop.owned_display_handle())));
    let mixer = Arc::new(Mutex::new(audio::Mixer::default()));
    let out = audio::start(mixer.clone());
    let eng: Shared = Rc::new(RefCell::new(Engine::new(o.root.clone(), mixer)));
    eng.borrow_mut().saves = saves;
    eng.borrow_mut().fullscreen = o.fullscreen;
    eng.borrow_mut().skinning = true;
    eng.borrow_mut().screen = (o.size.0 as f32, o.size.1 as f32);
    let script = load(&eng);
    let shot = o.screenshot.clone().map(|p| (p, o.frames.unwrap_or(120)));
    // The textures come from GAME_DIR/materials when the map can take them
    // (a heightfield with surface classes); --material-pack picks another.
    let material_pack = o.material_pack.clone().or_else(|| {
        let dir = o.root.join("materials");
        let classes = eng.borrow().terrain.as_ref().is_some_and(|t| t.material_classes.is_some());
        (classes && dir.join("albedo.ktx2").is_file()).then_some(dir)
    });
    if let Some(dir) = &material_pack {
        println!("wgpu window: materials from {}", dir.display());
    }
    let mut app = App2 {
        mtime: newest_mtime(&o.root),
        eng,
        script,
        _audio: out,
        instance,
        gfx: None,
        render_scale: o.render_scale,
        base: Settings { internal: (1, 1), output: (1, 1), upscale: o.upscale.unwrap_or_default(), material_pack, hdr: o.hdr },
        acc: 0.0,
        last: now(),
        frame_time: (1.0 / TICK_HZ) as f32,
        frame: 0,
        watch_at: 0.0,
        reload: false,
        grabbed: false,
        fullscreen: o.fullscreen,
        pads: pad::Pads::new(),
        quit_after: if shot.is_none() { o.frames } else { None },
        shot,
        ticks_per_frame: o.ticks_per_frame.max(1),
        closed: false,
        failed: false,
        fps_frames: 0,
        fps_since: now(),
        size_hint: (o.size.0.max(1) as u32, o.size.1.max(1) as u32),
    };
    event_loop.run_app(&mut app).map_err(|e| e.to_string())?;
    if app.failed {
        std::process::exit(1);
    }
    Ok(())
}

impl App2 {
    fn sizes(&self, width: u32, height: u32) -> ((u32, u32), (u32, u32)) {
        let s = self.render_scale.clamp(0.25, 1.0);
        let internal = (((width as f32 * s) as u32).max(1), ((height as f32 * s) as u32).max(1));
        ((internal.0.min(width), internal.1.min(height)), (width.max(1), height.max(1)))
    }

    fn close(&mut self) {
        if !std::mem::replace(&mut self.closed, true)
            && let Some(s) = &self.script
        {
            s.emit(&self.eng, "quit", ());
        }
        self.failed |= self.eng.borrow().error.is_some();
    }

    fn reload(&mut self) {
        if let Some(s) = &self.script {
            s.emit(&self.eng, "quit", ());
        }
        self.failed |= self.eng.borrow().error.is_some();
        let (root, screen, mixer, saves, fullscreen) = {
            let mut e = self.eng.borrow_mut();
            (e.root.clone(), e.screen, e.mixer.clone(), std::mem::take(&mut e.saves), e.fullscreen)
        };
        self.script = None;
        *self.eng.borrow_mut() = Engine::new(root, mixer);
        {
            let mut e = self.eng.borrow_mut();
            e.screen = screen;
            e.saves = saves;
            e.fullscreen = fullscreen;
            e.skinning = true;
        }
        self.script = load(&self.eng);
        self.acc = 0.0;
        println!("reloaded");
    }

    fn press(&mut self, name: &str, down: bool) {
        if name.is_empty() {
            return;
        }
        if down {
            self.eng.borrow_mut().keys.insert(name.to_string());
        } else {
            self.eng.borrow_mut().keys.remove(name);
        }
        if let Some(s) = &self.script {
            s.emit(&self.eng, key_event(&self.eng), (name, down));
        }
    }

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

    /// Game time: hot reload, pads, fixed ticks (as `App::update`).
    fn update(&mut self) {
        let now = now();
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
        let fixed = self.shot.is_some() || self.quit_after.is_some();
        self.acc += if fixed { self.ticks_per_frame as f64 / TICK_HZ } else { dt };
        while self.acc >= 1.0 / TICK_HZ {
            self.acc -= 1.0 / TICK_HZ;
            tick(&self.eng, script);
        }
    }

    /// One frame: the scripts' frame handler, then the picture.
    fn draw(&mut self, event_loop: &ActiveEventLoop) {
        let Some(gfx) = &self.gfx else { return };
        let size = gfx.window.inner_size();
        {
            let mut e = self.eng.borrow_mut();
            e.screen = (size.width as f32, size.height as f32);
            e.hud.clear();
            e.hud_clip = None;
        }
        let fixed = self.shot.is_some() || self.quit_after.is_some();
        let along = if fixed || self.eng.borrow().paused { 1.0 } else { (self.acc * TICK_HZ).clamp(0.0, 1.0) as f32 };
        let saved = self.eng.borrow_mut().blend(along);
        if let Some(s) = &self.script {
            let dt = if fixed { self.ticks_per_frame as f32 / TICK_HZ as f32 } else { self.frame_time };
            s.emit(&self.eng, "frame", frame_dt(&self.eng, dt));
        }
        self.eng.borrow_mut().update_audio();
        self.eng.borrow_mut().update_stream(fixed);
        {
            let mut e = self.eng.borrow_mut();
            e.mouse_delta = (0.0, 0.0);
            if let Some(err) = e.error.clone() {
                let msg: String = err.lines().take(12).collect::<Vec<_>>().join("\n");
                let w = e.screen.0;
                e.hud_rect(0.0, 0.0, w, 20.0 + 18.0 * msg.lines().count() as f32, [0.3, 0.0, 0.0, 0.85]);
                e.hud_text(&msg, 10.0, 10.0, 12.0, [1.0, 0.8, 0.8, 1.0]);
            }
        }
        let (fullscreen, grab) = {
            let e = self.eng.borrow();
            (e.fullscreen, e.mouse_grab)
        };
        let gfx = self.gfx.as_mut().expect("window");
        if fullscreen != self.fullscreen {
            self.fullscreen = fullscreen;
            gfx.window.set_fullscreen(fullscreen.then_some(Fullscreen::Borderless(None)));
        }
        if grab != self.grabbed {
            self.grabbed = grab;
            if grab {
                let _ =
                    gfx.window.set_cursor_grab(CursorGrabMode::Locked).or_else(|_| gfx.window.set_cursor_grab(CursorGrabMode::Confined));
            } else {
                let _ = gfx.window.set_cursor_grab(CursorGrabMode::None);
            }
            gfx.window.set_cursor_visible(!grab);
        }
        let result = (|| -> Result<(), String> {
            let (mut encoder, _stats) = gfx.renderer.encode(&self.eng.borrow())?;
            match gfx.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(frame) | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => {
                    let view = frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
                    gfx.renderer.present_onto(&mut encoder, &view, gfx.config.format);
                    gfx.renderer.submit(encoder);
                    gfx.window.pre_present_notify();
                    frame.present();
                }
                wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                    gfx.renderer.submit(encoder);
                    gfx.surface.configure(gfx.renderer.device(), &gfx.config);
                }
                _ => gfx.renderer.submit(encoder),
            }
            Ok(())
        })();
        self.eng.borrow_mut().unblend(saved);
        if let Err(e) = result {
            eprintln!("wgpu window: {e}");
            self.failed = true;
            self.close();
            event_loop.exit();
            return;
        }
        self.frame += 1;
        self.fps_frames += 1;
        let t = now();
        if t - self.fps_since >= 2.0 {
            let gfx = self.gfx.as_ref().expect("window");
            let info = gfx.renderer.adapter_info();
            let s = gfx.renderer.settings();
            println!(
                "wgpu window: {:.1} fps on {} ({:?}); scene {}x{}, window {}x{}",
                self.fps_frames as f64 / (t - self.fps_since),
                info.name,
                info.backend,
                s.internal.0,
                s.internal.1,
                s.output.0,
                s.output.1
            );
            self.fps_frames = 0;
            self.fps_since = t;
        }
        if let Some((path, at)) = &self.shot
            && self.frame == *at
        {
            let gfx = self.gfx.as_ref().expect("window");
            match gfx.renderer.save_output(Path::new(path)) {
                Ok(()) => println!("screenshot: {path} (wgpu window)"),
                Err(e) => {
                    eprintln!("screenshot failed: {e}");
                    self.failed = true;
                }
            }
            self.close();
            event_loop.exit();
            return;
        }
        if self.eng.borrow().quit || self.quit_after == Some(self.frame) {
            self.close();
            event_loop.exit();
        }
    }
}

impl ApplicationHandler for App2 {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.gfx.is_some() {
            return;
        }
        let (w, h) = self.size_hint;
        let mut attributes = Window::default_attributes().with_title("auto").with_inner_size(PhysicalSize::new(w, h));
        if self.fullscreen {
            attributes = attributes.with_fullscreen(Some(Fullscreen::Borderless(None)));
        }
        let made = (|| -> Result<Gfx, String> {
            let window = Arc::new(event_loop.create_window(attributes).map_err(|e| e.to_string())?);
            let surface = self.instance.create_surface(window.clone()).map_err(|e| e.to_string())?;
            let size = window.inner_size();
            let (internal, output) = self.sizes(size.width, size.height);
            let settings = Settings { internal, output, ..self.base.clone() };
            let renderer = Renderer2::new(&self.eng.borrow(), settings, &self.instance, Some(&surface))?;
            let mut config = surface
                .get_default_config(&renderer_adapter(&self.instance, &surface)?, output.0, output.1)
                .ok_or("the window's surface isn't supported by this adapter")?;
            // The renderer's output is display values already: a non-sRGB
            // surface format, so they aren't encoded twice.
            config.format = config.format.remove_srgb_suffix();
            config.present_mode = wgpu::PresentMode::AutoVsync;
            surface.configure(renderer.device(), &config);
            Ok(Gfx { window, surface, config, renderer })
        })();
        match made {
            Ok(gfx) => {
                let info = gfx.renderer.adapter_info();
                println!("wgpu window: {} ({:?}, {:?}); surface {:?}", info.name, info.backend, info.device_type, gfx.config.format);
                gfx.window.request_redraw();
                self.gfx = Some(gfx);
            }
            Err(e) => {
                eprintln!("wgpu window: {e}");
                self.failed = true;
                event_loop.exit();
            }
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                self.close();
                event_loop.exit();
            }
            WindowEvent::Resized(size) if size.width > 0 && size.height > 0 => {
                let (internal, output) = self.sizes(size.width, size.height);
                if let Some(gfx) = &mut self.gfx {
                    gfx.config.width = output.0;
                    gfx.config.height = output.1;
                    gfx.surface.configure(gfx.renderer.device(), &gfx.config);
                    if let Err(e) = gfx.renderer.resize(&self.eng.borrow(), internal, output) {
                        eprintln!("wgpu window: {e}");
                    }
                }
            }
            WindowEvent::KeyboardInput { event, .. } => {
                let PhysicalKey::Code(code) = event.physical_key else { return };
                let down = event.state == ElementState::Pressed;
                if code == KeyCode::F5 && down {
                    self.reload = true;
                    return;
                }
                if code == KeyCode::Escape && down {
                    self.eng.borrow_mut().mouse_grab = false;
                }
                if event.repeat {
                    return;
                }
                self.press(key_name(code), down);
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let name = match button {
                    MouseButton::Left => "mouse1",
                    MouseButton::Right => "mouse2",
                    MouseButton::Middle => "mouse3",
                    _ => return,
                };
                self.press(name, state == ElementState::Pressed);
            }
            WindowEvent::CursorMoved { position, .. } => {
                self.eng.borrow_mut().cursor = (position.x as f32, position.y as f32);
            }
            WindowEvent::RedrawRequested => {
                self.update();
                self.draw(event_loop);
                if let Some(gfx) = &self.gfx {
                    gfx.window.request_redraw();
                }
            }
            _ => {}
        }
    }

    fn device_event(&mut self, _event_loop: &ActiveEventLoop, _id: DeviceId, event: DeviceEvent) {
        if let DeviceEvent::MouseMotion { delta } = event {
            let mut e = self.eng.borrow_mut();
            e.mouse_delta.0 += delta.0 as f32;
            e.mouse_delta.1 += delta.1 as f32;
        }
    }
}

/// The adapter the renderer would pick for this surface (for its default config).
fn renderer_adapter(instance: &wgpu::Instance, surface: &wgpu::Surface<'_>) -> Result<wgpu::Adapter, String> {
    pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: Some(surface),
        ..Default::default()
    }))
    .map_err(|e| e.to_string())
}

/// winit's physical keys to the engine's key names (as `key_name` in main.rs).
fn key_name(k: KeyCode) -> &'static str {
    use KeyCode::*;
    match k {
        KeyA => "a",
        KeyB => "b",
        KeyC => "c",
        KeyD => "d",
        KeyE => "e",
        KeyF => "f",
        KeyG => "g",
        KeyH => "h",
        KeyI => "i",
        KeyJ => "j",
        KeyK => "k",
        KeyL => "l",
        KeyM => "m",
        KeyN => "n",
        KeyO => "o",
        KeyP => "p",
        KeyQ => "q",
        KeyR => "r",
        KeyS => "s",
        KeyT => "t",
        KeyU => "u",
        KeyV => "v",
        KeyW => "w",
        KeyX => "x",
        KeyY => "y",
        KeyZ => "z",
        Digit0 => "0",
        Digit1 => "1",
        Digit2 => "2",
        Digit3 => "3",
        Digit4 => "4",
        Digit5 => "5",
        Digit6 => "6",
        Digit7 => "7",
        Digit8 => "8",
        Digit9 => "9",
        Space => "space",
        Enter => "enter",
        Escape => "escape",
        Tab => "tab",
        Backspace => "backspace",
        ArrowUp => "up",
        ArrowDown => "down",
        ArrowLeft => "left",
        ArrowRight => "right",
        ShiftLeft | ShiftRight => "shift",
        ControlLeft | ControlRight => "ctrl",
        AltLeft | AltRight => "alt",
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
