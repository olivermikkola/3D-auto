//! Gamepads. Buttons become ordinary key names (`pad_a`, `pad_start`,
//! `pad_up`, ...) so they travel the same road as the keyboard; sticks and
//! triggers are read with `engine.pad()`.
//!
//! On Linux the kernel's evdev interface is read directly (no udev, so still
//! no build dependencies); every driver that follows the kernel gamepad API
//! (xpad, hid-playstation, hid-nintendo, ...) reports the same codes. On
//! Windows and macOS, gilrs does the work.

/// The first connected pad, normalized: sticks -1..1 with up and right
/// positive, triggers 0..1.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct State {
    pub name: String,
    pub lx: f32,
    pub ly: f32,
    pub rx: f32,
    pub ry: f32,
    pub lt: f32,
    pub rt: f32,
}

/// What happened since the last poll.
#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    Connected(String),
    Disconnected(String),
    Button(&'static str, bool),
}

/// Triggers also act as buttons once pressed past this.
const TRIGGER_DOWN: f32 = 0.5;

/// Track analog triggers crossing the button threshold.
fn trigger_edge(name: &'static str, old: f32, new: f32, out: &mut Vec<Event>) {
    if (old >= TRIGGER_DOWN) != (new >= TRIGGER_DOWN) {
        out.push(Event::Button(name, new >= TRIGGER_DOWN));
    }
}

#[cfg(target_os = "linux")]
pub use evdev::Pads;
#[cfg(not(target_os = "linux"))]
pub use gil::Pads;

// ---- Linux: evdev ---------------------------------------------------------------
#[cfg(any(target_os = "linux", test))]
mod evdev {
    use super::{Event, State, trigger_edge};
    use std::fs::File;
    use std::io::Read;
    use std::os::fd::AsRawFd;

    unsafe extern "C" {
        fn ioctl(fd: i32, request: std::ffi::c_ulong, ...) -> i32;
    }

    // <linux/input.h>
    const EV_KEY: u16 = 0x01;
    const EV_ABS: u16 = 0x03;
    const BTN_GAMEPAD: u16 = 0x130;
    const ABS_X: u16 = 0x00;
    const ABS_Y: u16 = 0x01;
    const ABS_Z: u16 = 0x02;
    const ABS_RX: u16 = 0x03;
    const ABS_RY: u16 = 0x04;
    const ABS_RZ: u16 = 0x05;
    const ABS_GAS: u16 = 0x09;
    const ABS_BRAKE: u16 = 0x0a;
    const ABS_HAT0X: u16 = 0x10;
    const ABS_HAT0Y: u16 = 0x11;
    const ABS_COUNT: usize = 0x40;

    /// struct input_event: a timeval, then type, code and value.
    const EVENT_SIZE: usize = 2 * std::mem::size_of::<std::ffi::c_long>() + 8;

    const fn ioc_read(nr: u32, size: usize) -> std::ffi::c_ulong {
        ((2 << 30) | ((size as u32) << 16) | ((b'E' as u32) << 8) | nr) as std::ffi::c_ulong
    }
    pub(super) const fn eviocgname(len: usize) -> std::ffi::c_ulong {
        ioc_read(0x06, len)
    }
    pub(super) const fn eviocgbit(ev: u16, len: usize) -> std::ffi::c_ulong {
        ioc_read(0x20 + ev as u32, len)
    }
    pub(super) const fn eviocgabs(abs: u16) -> std::ffi::c_ulong {
        ioc_read(0x40 + abs as u32, 24)
    }

    pub(super) fn button(code: u16) -> Option<&'static str> {
        Some(match code {
            0x130 => "pad_a",
            0x131 => "pad_b",
            0x133 => "pad_y",
            0x134 => "pad_x",
            0x136 => "pad_lb",
            0x137 => "pad_rb",
            0x13a => "pad_back",
            0x13b => "pad_start",
            0x13c => "pad_guide",
            0x13d => "pad_l3",
            0x13e => "pad_r3",
            0x220 => "pad_up",
            0x221 => "pad_down",
            0x222 => "pad_left",
            0x223 => "pad_right",
            _ => return None,
        })
    }

    /// An axis's range, from EVIOCGABS: value, min, max, fuzz, flat, resolution.
    #[derive(Clone, Copy, Default)]
    pub(super) struct Range {
        pub min: i32,
        pub max: i32,
        pub flat: i32,
    }

    impl Range {
        /// -1..1 for sticks (with the driver's dead zone), 0..1 for triggers.
        pub fn stick(&self, v: i32) -> f32 {
            let mid = (self.min as f32 + self.max as f32) / 2.0;
            let half = (self.max as f32 - self.min as f32) / 2.0;
            if half <= 0.0 || (v as f32 - mid).abs() <= self.flat as f32 {
                return 0.0;
            }
            ((v as f32 - mid) / half).clamp(-1.0, 1.0)
        }
        pub fn trigger(&self, v: i32) -> f32 {
            let span = (self.max - self.min) as f32;
            if span <= 0.0 { 0.0 } else { ((v - self.min) as f32 / span).clamp(0.0, 1.0) }
        }
    }

    /// One open gamepad and its decoded state.
    pub(super) struct Device {
        file: Option<File>,
        pub path: std::path::PathBuf,
        pub state: State,
        pub ranges: [Range; ABS_COUNT],
        hat: (i32, i32),
    }

    impl Device {
        fn open(path: &std::path::Path) -> Option<Device> {
            use std::os::unix::fs::OpenOptionsExt;
            const O_NONBLOCK: i32 = 0o4000;
            let file = std::fs::OpenOptions::new().read(true).custom_flags(O_NONBLOCK).open(path).ok()?;
            let fd = file.as_raw_fd();
            // A gamepad has the gamepad buttons and at least one stick.
            let mut keys = [0u8; 96];
            let mut abs = [0u8; 8];
            unsafe {
                if ioctl(fd, eviocgbit(EV_KEY, keys.len()), keys.as_mut_ptr()) < 0
                    || ioctl(fd, eviocgbit(EV_ABS, abs.len()), abs.as_mut_ptr()) < 0
                {
                    return None;
                }
            }
            let has = |bits: &[u8], n: u16| bits.get(n as usize / 8).is_some_and(|b| b & (1 << (n % 8)) != 0);
            if !has(&keys, BTN_GAMEPAD) || !has(&abs, ABS_X) {
                return None;
            }
            let mut name = [0u8; 128];
            unsafe { ioctl(fd, eviocgname(name.len()), name.as_mut_ptr()) };
            let end = name.iter().position(|&c| c == 0).unwrap_or(name.len());
            let mut d = Device::new(path, String::from_utf8_lossy(&name[..end]).trim().to_string());
            for code in 0..ABS_COUNT as u16 {
                if has(&abs, code) {
                    let mut info = [0i32; 6];
                    if unsafe { ioctl(fd, eviocgabs(code), info.as_mut_ptr()) } >= 0 {
                        d.ranges[code as usize] = Range { min: info[1], max: info[2], flat: info[4] };
                    }
                }
            }
            d.file = Some(file);
            Some(d)
        }

        #[cfg(test)]
        pub(super) fn attach(&mut self, file: File) {
            self.file = Some(file);
        }

        pub(super) fn new(path: &std::path::Path, name: String) -> Device {
            Device {
                file: None,
                path: path.to_path_buf(),
                state: State { name, ..Default::default() },
                ranges: [Range::default(); ABS_COUNT],
                hat: (0, 0),
            }
        }

        /// Apply one input_event.
        pub(super) fn apply(&mut self, ty: u16, code: u16, value: i32, out: &mut Vec<Event>) {
            match ty {
                EV_KEY => {
                    // Digital triggers are covered by the analog ones (or added below).
                    if let Some(name) = button(code) {
                        out.push(Event::Button(name, value != 0));
                    } else if code == 0x138 || code == 0x139 {
                        let (name, now) = if code == 0x138 { ("pad_lt", &mut self.state.lt) } else { ("pad_rt", &mut self.state.rt) };
                        let new = if value != 0 { 1.0 } else { 0.0 };
                        let old = std::mem::replace(now, new);
                        trigger_edge(name, old, new, out);
                    }
                }
                EV_ABS => {
                    let r = self.ranges.get(code as usize).copied().unwrap_or_default();
                    let s = &mut self.state;
                    match code {
                        ABS_X => s.lx = r.stick(value),
                        ABS_Y => s.ly = -r.stick(value),
                        ABS_RX => s.rx = r.stick(value),
                        ABS_RY => s.ry = -r.stick(value),
                        ABS_Z | ABS_BRAKE => {
                            let new = r.trigger(value);
                            trigger_edge("pad_lt", std::mem::replace(&mut s.lt, new), new, out);
                        }
                        ABS_RZ | ABS_GAS => {
                            let new = r.trigger(value);
                            trigger_edge("pad_rt", std::mem::replace(&mut s.rt, new), new, out);
                        }
                        ABS_HAT0X | ABS_HAT0Y => {
                            let v = value.signum();
                            let (old, names) = if code == ABS_HAT0X {
                                (std::mem::replace(&mut self.hat.0, v), ("pad_left", "pad_right"))
                            } else {
                                (std::mem::replace(&mut self.hat.1, v), ("pad_up", "pad_down"))
                            };
                            if old != v {
                                if old != 0 {
                                    out.push(Event::Button(if old < 0 { names.0 } else { names.1 }, false));
                                }
                                if v != 0 {
                                    out.push(Event::Button(if v < 0 { names.0 } else { names.1 }, true));
                                }
                            }
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }

        /// Read everything pending. False once the device is gone.
        pub(super) fn read(&mut self, out: &mut Vec<Event>) -> bool {
            let mut buf = [0u8; EVENT_SIZE * 64];
            loop {
                let Some(file) = self.file.as_mut() else { return false };
                match file.read(&mut buf) {
                    Ok(0) => return false,
                    Ok(n) => {
                        for ev in buf[..n].as_chunks::<EVENT_SIZE>().0 {
                            let t = EVENT_SIZE - 8;
                            let ty = u16::from_ne_bytes([ev[t], ev[t + 1]]);
                            let code = u16::from_ne_bytes([ev[t + 2], ev[t + 3]]);
                            let value = i32::from_ne_bytes([ev[t + 4], ev[t + 5], ev[t + 6], ev[t + 7]]);
                            self.apply(ty, code, value, out);
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return true,
                    Err(_) => return false,
                }
            }
        }
    }

    pub struct Pads {
        devices: Vec<Device>,
        next_scan: f64,
    }

    impl Pads {
        pub fn new() -> Pads {
            Pads { devices: Vec::new(), next_scan: 0.0 }
        }

        /// Read input, and look for newly plugged-in pads every couple of seconds.
        pub fn poll(&mut self, now: f64, out: &mut Vec<Event>) {
            if now >= self.next_scan {
                self.next_scan = now + 2.0;
                let mut paths: Vec<_> = std::fs::read_dir("/dev/input")
                    .map(|rd| {
                        rd.flatten()
                            .map(|e| e.path())
                            .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("event")))
                            .collect()
                    })
                    .unwrap_or_default();
                paths.sort();
                for p in paths {
                    if self.devices.iter().any(|d| d.path == p) {
                        continue;
                    }
                    if let Some(d) = Device::open(&p) {
                        out.push(Event::Connected(d.state.name.clone()));
                        self.devices.push(d);
                    }
                }
            }
            self.devices.retain_mut(|d| {
                let alive = d.read(out);
                if !alive {
                    out.push(Event::Disconnected(d.state.name.clone()));
                }
                alive
            });
        }

        pub fn state(&self) -> Option<&State> {
            self.devices.first().map(|d| &d.state)
        }
    }
}

// ---- Windows and macOS: gilrs -----------------------------------------------------
#[cfg(not(target_os = "linux"))]
mod gil {
    use super::{Event, State, trigger_edge};
    use gilrs::{Axis, Button, EventType, Gilrs};

    fn button(b: Button) -> Option<&'static str> {
        Some(match b {
            Button::South => "pad_a",
            Button::East => "pad_b",
            Button::North => "pad_y",
            Button::West => "pad_x",
            Button::LeftTrigger => "pad_lb",
            Button::RightTrigger => "pad_rb",
            Button::Select => "pad_back",
            Button::Start => "pad_start",
            Button::Mode => "pad_guide",
            Button::LeftThumb => "pad_l3",
            Button::RightThumb => "pad_r3",
            Button::DPadUp => "pad_up",
            Button::DPadDown => "pad_down",
            Button::DPadLeft => "pad_left",
            Button::DPadRight => "pad_right",
            _ => return None,
        })
    }

    pub struct Pads {
        gilrs: Option<Gilrs>,
        state: Option<State>,
    }

    impl Pads {
        pub fn new() -> Pads {
            let gilrs = Gilrs::new().map_err(|e| eprintln!("gamepads unavailable: {e}")).ok();
            Pads { gilrs, state: None }
        }

        pub fn poll(&mut self, _now: f64, out: &mut Vec<Event>) {
            let Some(g) = self.gilrs.as_mut() else { return };
            while let Some(ev) = g.next_event() {
                let name = g.gamepad(ev.id).name().to_string();
                match ev.event {
                    EventType::Connected => out.push(Event::Connected(name)),
                    EventType::Disconnected => out.push(Event::Disconnected(name)),
                    EventType::ButtonPressed(b, _) => out.extend(button(b).map(|n| Event::Button(n, true))),
                    EventType::ButtonReleased(b, _) => out.extend(button(b).map(|n| Event::Button(n, false))),
                    _ => {}
                }
            }
            let pad = g.gamepads().find(|(_, p)| p.is_connected()).map(|(_, p)| p);
            let old = self.state.take().unwrap_or_default();
            self.state = pad.map(|p| {
                let trig = |b| p.button_data(b).map_or(0.0, |d| d.value());
                State {
                    name: p.name().to_string(),
                    lx: p.value(Axis::LeftStickX),
                    ly: p.value(Axis::LeftStickY),
                    rx: p.value(Axis::RightStickX),
                    ry: p.value(Axis::RightStickY),
                    lt: trig(Button::LeftTrigger2),
                    rt: trig(Button::RightTrigger2),
                }
            });
            let new = self.state.clone().unwrap_or_default();
            trigger_edge("pad_lt", old.lt, new.lt, out);
            trigger_edge("pad_rt", old.rt, new.rt, out);
        }

        pub fn state(&self) -> Option<&State> {
            self.state.as_ref()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::evdev::*;
    use super::*;

    #[test]
    fn ioctl_numbers_match_linux_input_h() {
        assert_eq!(eviocgname(256), 0x8100_4506);
        assert_eq!(eviocgbit(1, 96), 0x8060_4521); // EV_KEY
        assert_eq!(eviocgabs(0), 0x8018_4540); // ABS_X
    }

    fn pad() -> Device {
        let mut d = Device::new(std::path::Path::new("/dev/input/event9"), "Test Pad".into());
        for code in [0, 1, 3, 4] {
            d.ranges[code] = Range { min: -32768, max: 32767, flat: 4000 };
        }
        for code in [2, 5] {
            d.ranges[code] = Range { min: 0, max: 255, flat: 0 };
        }
        d
    }

    #[test]
    fn sticks_triggers_and_buttons_decode() {
        let mut d = pad();
        let mut ev = Vec::new();
        d.apply(3, 0, 32767, &mut ev); // left stick right
        d.apply(3, 1, -32768, &mut ev); // left stick up (evdev: negative is up)
        d.apply(3, 3, 2000, &mut ev); // right stick inside the dead zone
        assert_eq!((d.state.lx, d.state.ly, d.state.rx), (1.0, 1.0, 0.0));
        d.apply(3, 5, 255, &mut ev); // right trigger fully in
        d.apply(1, 0x130, 1, &mut ev); // A down
        d.apply(1, 0x13b, 0, &mut ev); // Start up
        d.apply(1, 0x2ff, 1, &mut ev); // unknown key: ignored
        assert_eq!(d.state.rt, 1.0);
        assert_eq!(ev, vec![Event::Button("pad_rt", true), Event::Button("pad_a", true), Event::Button("pad_start", false)]);
        ev.clear();
        d.apply(3, 5, 100, &mut ev); // trigger eased off below half: released
        d.apply(3, 5, 60, &mut ev); // further: no repeat
        assert_eq!(ev, vec![Event::Button("pad_rt", false)]);
    }

    #[test]
    fn raw_input_events_are_read_from_the_device() {
        // The bytes the kernel writes: struct input_event {timeval; u16 type, code; i32 value}.
        let tv = 2 * std::mem::size_of::<std::ffi::c_long>();
        let mut bytes = Vec::new();
        for (ty, code, value) in [(1u16, 0x133u16, 1i32), (3, 1, 32767), (0, 0, 0), (1, 0x133, 0)] {
            bytes.extend(std::iter::repeat_n(0u8, tv));
            bytes.extend(ty.to_ne_bytes());
            bytes.extend(code.to_ne_bytes());
            bytes.extend(value.to_ne_bytes());
        }
        let path = std::env::temp_dir().join(format!("auto-pad-test-{}", std::process::id()));
        std::fs::write(&path, &bytes).unwrap();
        let mut d = pad();
        d.attach(std::fs::File::open(&path).unwrap());
        let mut ev = Vec::new();
        assert!(!d.read(&mut ev), "end of file reads as the device going away");
        assert_eq!(ev, vec![Event::Button("pad_y", true), Event::Button("pad_y", false)]);
        assert_eq!(d.state.ly, -1.0, "stick pulled down");
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn dpad_hat_becomes_buttons() {
        let mut d = pad();
        let mut ev = Vec::new();
        d.apply(3, 0x11, -1, &mut ev); // up
        d.apply(3, 0x11, 1, &mut ev); // straight to down
        d.apply(3, 0x11, 0, &mut ev); // centred
        d.apply(3, 0x10, 1, &mut ev); // right
        assert_eq!(
            ev,
            vec![
                Event::Button("pad_up", true),
                Event::Button("pad_up", false),
                Event::Button("pad_down", true),
                Event::Button("pad_down", false),
                Event::Button("pad_right", true),
            ]
        );
    }
}
