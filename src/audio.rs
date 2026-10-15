//! Audio: a software mixer with pitch and 3D panning, an sfxr-style synth so
//! games need no sound files, a WAV loader for when they want them, and
//! the smallest output backend per platform (ALSA via dlopen on Linux, so
//! there is no build dependency; cpal elsewhere). No device means silence,
//! never an error.

use crate::math::Vec3;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// Rate every sound is stored at. The mixer resamples to the device.
pub const RATE: u32 = 44100;

pub type Samples = Arc<Vec<f32>>;

struct Voice {
    id: u32,
    data: Samples,
    pos: f64,
    pitch: f32,
    volume: f32,
    looped: bool,
    world: Option<Vec3>,
    gains: (f32, f32),
    /// Interface sounds keep playing while the game is paused.
    ui: bool,
}

pub struct Mixer {
    voices: Vec<Voice>,
    next: u32,
    pub out_rate: u32,
    pub listener: Vec3,
    pub listener_right: Vec3,
    pub master: f32,
    /// Freezes every voice except `ui` ones, where they are.
    pub paused: bool,
}

impl Default for Mixer {
    fn default() -> Mixer {
        Mixer { voices: Vec::new(), next: 1, out_rate: RATE, listener: Vec3::ZERO, listener_right: Vec3::ZERO, master: 0.7, paused: false }
    }
}

/// Distance rolloff and equal-power pan for a voice at `world`.
fn spatial(world: Option<Vec3>, listener: Vec3, right: Vec3) -> (f32, f32) {
    let Some(p) = world else { return (1.0, 1.0) };
    let d = p - listener;
    let dist = d.len();
    let att = 1.0 / (1.0 + (dist / 12.0).powi(2));
    let pan = if dist > 0.01 { d.norm().dot(right).clamp(-1.0, 1.0) * 0.8 } else { 0.0 };
    let a = (pan + 1.0) * std::f32::consts::FRAC_PI_4;
    (att * a.cos() * std::f32::consts::SQRT_2, att * a.sin() * std::f32::consts::SQRT_2)
}

impl Mixer {
    pub fn play(&mut self, data: Samples, volume: f32, pitch: f32, looped: bool, world: Option<Vec3>, ui: bool) -> u32 {
        let id = self.next;
        self.next += 1;
        let gains = spatial(world, self.listener, self.listener_right);
        self.voices.push(Voice { id, data, pos: 0.0, pitch, volume, looped, world, gains, ui });
        id
    }

    pub fn set(&mut self, id: u32, volume: Option<f32>, pitch: Option<f32>, world: Option<Vec3>) {
        if let Some(v) = self.voices.iter_mut().find(|v| v.id == id) {
            v.volume = volume.unwrap_or(v.volume);
            v.pitch = pitch.unwrap_or(v.pitch);
            v.world = world.or(v.world);
        }
    }

    pub fn stop(&mut self, id: u32) {
        self.voices.retain(|v| v.id != id);
    }

    pub fn stop_all(&mut self) {
        self.voices.clear();
        self.paused = false;
    }

    pub fn playing(&self, id: u32) -> bool {
        self.voices.iter().any(|v| v.id == id)
    }

    pub fn voice_count(&self) -> usize {
        self.voices.len()
    }

    /// Mix into interleaved stereo `out` (overwrites it).
    pub fn mix(&mut self, out: &mut [f32]) {
        out.fill(0.0);
        let frames = out.len() / 2;
        let ratio = RATE as f64 / self.out_rate as f64;
        let (listener, right) = (self.listener, self.listener_right);
        for v in &mut self.voices {
            if self.paused && !v.ui {
                continue;
            }
            let n = v.data.len();
            if n == 0 {
                v.looped = false;
                v.pos = 0.0;
                continue;
            }
            // Ramp gains across the buffer so moving sources don't click.
            let (gl0, gr0) = v.gains;
            let (gl1, gr1) = spatial(v.world, listener, right);
            v.gains = (gl1, gr1);
            let step = v.pitch.max(0.0) as f64 * ratio;
            for f in 0..frames {
                if v.pos >= n as f64 {
                    if !v.looped {
                        break;
                    }
                    v.pos %= n as f64;
                }
                let i = v.pos as usize;
                let frac = (v.pos - i as f64) as f32;
                let next = if i + 1 < n {
                    v.data[i + 1]
                } else if v.looped {
                    v.data[0]
                } else {
                    0.0
                };
                let s = (v.data[i] + (next - v.data[i]) * frac) * v.volume;
                let t = f as f32 / frames as f32;
                out[2 * f] += s * (gl0 + (gl1 - gl0) * t);
                out[2 * f + 1] += s * (gr0 + (gr1 - gr0) * t);
                v.pos += step;
            }
        }
        self.voices.retain(|v| v.looped || v.pos < v.data.len() as f64);
        for s in out.iter_mut() {
            *s = (*s * self.master).clamp(-1.0, 1.0);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Wave {
    Sine,
    Square,
    Saw,
    Triangle,
    Noise,
}

pub struct Synth {
    pub wave: Wave,
    pub freq: f32,
    pub freq_end: f32,
    pub dur: f32,
    pub attack: f32,
    pub release: f32,
    pub volume: f32,
    /// One-pole lowpass amount: 1 = off, smaller = darker.
    pub lowpass: f32,
    /// If non-empty, play these frequencies in sequence, `note_len` each.
    pub notes: Vec<f32>,
    pub note_len: f32,
    /// Make the buffer loop seamlessly (whole periods, no envelope).
    pub looped: bool,
}

impl Default for Synth {
    fn default() -> Synth {
        Synth {
            wave: Wave::Square,
            freq: 440.0,
            freq_end: 0.0,
            dur: 0.3,
            attack: 0.005,
            release: 0.05,
            volume: 0.5,
            lowpass: 1.0,
            notes: Vec::new(),
            note_len: 0.12,
            looped: false,
        }
    }
}

impl Synth {
    pub fn render(&self) -> Vec<f32> {
        let sr = RATE as f32;
        let segments: Vec<(f32, f32, f32)> = if self.notes.is_empty() {
            let end = if self.freq_end > 0.0 { self.freq_end } else { self.freq };
            vec![(self.freq, end, self.dur)]
        } else {
            self.notes.iter().map(|&f| (f, f, self.note_len)).collect()
        };
        let mut out = Vec::new();
        let mut rng: u32 = 0x9E37_79B9;
        let mut noise = 0.0f32;
        let mut lp = 0.0f32;
        let a = self.lowpass.clamp(0.001, 1.0).powi(2);
        for (f0, f1, dur) in segments {
            let (mut f0, mut dur) = (f0, dur);
            let looped = self.looped && self.wave != Wave::Noise;
            if looped {
                // Whole number of samples per period, whole number of periods.
                let period = (sr / f0).round().max(2.0);
                f0 = sr / period;
                dur = ((dur * f0).round().max(1.0)) / f0;
            }
            let n = (dur * sr).round() as usize;
            let mut phase = 0.0f32;
            for k in 0..n {
                let t = k as f32 / n as f32;
                let f = if looped { f0 } else { f0 * (f1 / f0).powf(t) };
                let prev = phase;
                phase = (phase + f / sr).fract();
                let x = match self.wave {
                    Wave::Sine => (phase * std::f32::consts::TAU).sin(),
                    Wave::Square => {
                        if phase < 0.5 {
                            1.0
                        } else {
                            -1.0
                        }
                    }
                    Wave::Saw => 2.0 * phase - 1.0,
                    Wave::Triangle => 1.0 - 4.0 * (phase - 0.5).abs(),
                    Wave::Noise => {
                        // Sample-and-hold white noise: lower freq = rumblier.
                        if phase < prev || k == 0 {
                            rng ^= rng << 13;
                            rng ^= rng >> 17;
                            rng ^= rng << 5;
                            noise = (rng as f32 / u32::MAX as f32) * 2.0 - 1.0;
                        }
                        noise
                    }
                };
                let secs = k as f32 / sr;
                let env = if looped {
                    1.0
                } else {
                    let att = if self.attack > 0.0 { (secs / self.attack).min(1.0) } else { 1.0 };
                    let rel = if self.release > 0.0 { ((dur - secs) / self.release).clamp(0.0, 1.0) } else { 1.0 };
                    att * rel
                };
                lp += a * (x - lp);
                out.push(lp * env * self.volume);
            }
        }
        out
    }
}

/// 8/16-bit PCM WAV, any channel count and rate, to mono at `RATE`.
pub fn load_wav(bytes: &[u8]) -> Result<Vec<f32>, String> {
    let u16le = |b: &[u8], o: usize| u16::from_le_bytes([b[o], b[o + 1]]);
    let u32le = |b: &[u8], o: usize| u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]);
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err("not a RIFF/WAVE file".into());
    }
    let (mut fmt, mut data) = (None, None);
    let mut o = 12;
    while o + 8 <= bytes.len() {
        let size = u32le(bytes, o + 4) as usize;
        let body = &bytes[o + 8..(o + 8 + size).min(bytes.len())];
        match &bytes[o..o + 4] {
            b"fmt " if body.len() >= 16 => fmt = Some((u16le(body, 0), u16le(body, 2), u32le(body, 4), u16le(body, 14))),
            b"data" => data = Some(body),
            _ => {}
        }
        o += 8 + size + (size & 1);
    }
    let (format, channels, rate, bits) = fmt.ok_or("no fmt chunk")?;
    let data = data.ok_or("no data chunk")?;
    if format != 1 || !(bits == 8 || bits == 16) || channels == 0 {
        return Err(format!("unsupported WAV (format {format}, {bits}-bit); use 8/16-bit PCM"));
    }
    let width = bits as usize / 8 * channels as usize;
    let mono: Vec<f32> = data
        .chunks_exact(width)
        .map(|fr| {
            let ch = (0..channels as usize).map(|c| {
                if bits == 8 { (fr[c] as f32 - 128.0) / 128.0 } else { i16::from_le_bytes([fr[2 * c], fr[2 * c + 1]]) as f32 / 32768.0 }
            });
            ch.sum::<f32>() / channels as f32
        })
        .collect();
    if rate == RATE || mono.is_empty() {
        return Ok(mono);
    }
    let ratio = rate as f64 / RATE as f64;
    let n = (mono.len() as f64 / ratio) as usize;
    Ok((0..n)
        .map(|k| {
            let p = k as f64 * ratio;
            let i = p as usize;
            let f = (p - i as f64) as f32;
            let b = mono.get(i + 1).copied().unwrap_or(mono[i]);
            mono[i] + (b - mono[i]) * f
        })
        .collect())
}

/// Keeps the output device alive; dropping it stops playback.
pub struct Output {
    stop: Arc<AtomicBool>,
    #[allow(dead_code)]
    stream: Option<Box<dyn std::any::Any>>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl Drop for Output {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

pub fn start(mixer: Arc<Mutex<Mixer>>) -> Option<Output> {
    let stop = Arc::new(AtomicBool::new(false));
    match backend::start(mixer, stop.clone()) {
        Ok((thread, stream)) => Some(Output { stop, stream, thread }),
        Err(e) => {
            eprintln!("audio: {e} (running silent)");
            None
        }
    }
}

#[cfg(target_os = "linux")]
mod backend {
    //! ALSA through dlopen: works wherever libasound.so.2 exists (including
    //! PulseAudio/PipeWire setups), and needs nothing at build time.
    use super::{Mixer, RATE};
    use std::ffi::{CString, c_char, c_int, c_long, c_uint, c_ulong, c_void};
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};

    unsafe extern "C" {
        fn dlopen(file: *const c_char, flag: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    }
    type Open = unsafe extern "C" fn(*mut *mut c_void, *const c_char, c_int, c_int) -> c_int;
    type SetParams = unsafe extern "C" fn(*mut c_void, c_int, c_int, c_uint, c_uint, c_int, c_uint) -> c_int;
    type Writei = unsafe extern "C" fn(*mut c_void, *const c_void, c_ulong) -> c_long;
    type Recover = unsafe extern "C" fn(*mut c_void, c_int, c_int) -> c_int;
    type Close = unsafe extern "C" fn(*mut c_void) -> c_int;

    struct Pcm(*mut c_void);
    unsafe impl Send for Pcm {}

    const FRAMES: usize = 512;

    pub type Started = (Option<std::thread::JoinHandle<()>>, Option<Box<dyn std::any::Any>>);

    pub fn start(mixer: Arc<Mutex<Mixer>>, stop: Arc<AtomicBool>) -> Result<Started, String> {
        unsafe {
            let lib = dlopen(c"libasound.so.2".as_ptr(), 2 /* RTLD_NOW */);
            if lib.is_null() {
                return Err("libasound.so.2 not found".into());
            }
            let sym = |name: &str| {
                let c = CString::new(name).unwrap();
                let p = dlsym(lib, c.as_ptr());
                if p.is_null() { Err(format!("missing {name}")) } else { Ok(p) }
            };
            let open: Open = std::mem::transmute(sym("snd_pcm_open")?);
            let set_params: SetParams = std::mem::transmute(sym("snd_pcm_set_params")?);
            let writei: Writei = std::mem::transmute(sym("snd_pcm_writei")?);
            let recover: Recover = std::mem::transmute(sym("snd_pcm_recover")?);
            let close: Close = std::mem::transmute(sym("snd_pcm_close")?);

            let mut pcm = std::ptr::null_mut();
            if open(&mut pcm, c"default".as_ptr(), 0 /* playback */, 0) < 0 {
                return Err("no ALSA output device".into());
            }
            // S16_LE, interleaved, stereo, resampling allowed, 40 ms latency.
            if set_params(pcm, 2, 3, 2, RATE, 1, 40_000) < 0 {
                close(pcm);
                return Err("ALSA rejected 44.1 kHz stereo".into());
            }
            mixer.lock().unwrap().out_rate = RATE;
            let pcm = Pcm(pcm);
            let thread = std::thread::spawn(move || {
                let pcm = pcm;
                let mut f = vec![0.0f32; FRAMES * 2];
                let mut s = vec![0i16; FRAMES * 2];
                while !stop.load(Ordering::Relaxed) {
                    mixer.lock().unwrap().mix(&mut f);
                    for (d, x) in s.iter_mut().zip(&f) {
                        *d = (x * 32767.0) as i16;
                    }
                    let r = writei(pcm.0, s.as_ptr() as *const c_void, FRAMES as c_ulong);
                    if r < 0 {
                        recover(pcm.0, r as c_int, 1);
                    }
                }
                close(pcm.0);
            });
            Ok((Some(thread), None))
        }
    }
}

// The browser: silent for now (WebAudio to come).
#[cfg(target_arch = "wasm32")]
mod backend {
    use super::Mixer;
    use std::sync::atomic::AtomicBool;
    use std::sync::{Arc, Mutex};

    pub type Started = (Option<std::thread::JoinHandle<()>>, Option<Box<dyn std::any::Any>>);

    pub fn start(_mixer: Arc<Mutex<Mixer>>, _stop: Arc<AtomicBool>) -> Result<Started, String> {
        Err("no sound in the browser yet".into())
    }
}

#[cfg(not(any(target_os = "linux", target_arch = "wasm32")))]
mod backend {
    use super::Mixer;
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use std::sync::atomic::AtomicBool;
    use std::sync::{Arc, Mutex};

    pub type Started = (Option<std::thread::JoinHandle<()>>, Option<Box<dyn std::any::Any>>);

    pub fn start(mixer: Arc<Mutex<Mixer>>, _stop: Arc<AtomicBool>) -> Result<Started, String> {
        let device = cpal::default_host().default_output_device().ok_or("no output device")?;
        let config = device.default_output_config().map_err(|e| e.to_string())?;
        if config.sample_format() != cpal::SampleFormat::F32 {
            return Err(format!("unsupported sample format {:?}", config.sample_format()));
        }
        let channels = config.channels() as usize;
        mixer.lock().unwrap().out_rate = config.sample_rate().0;
        let mut buf = Vec::new();
        let stream = device
            .build_output_stream(
                &config.into(),
                move |data: &mut [f32], _| {
                    let frames = data.len() / channels;
                    buf.resize(frames * 2, 0.0);
                    mixer.lock().unwrap().mix(&mut buf);
                    for (f, out) in data.chunks_mut(channels).enumerate() {
                        for (c, s) in out.iter_mut().enumerate() {
                            *s = buf[2 * f + (c & 1)];
                        }
                    }
                },
                |e| eprintln!("audio: {e}"),
                None,
            )
            .map_err(|e| e.to_string())?;
        stream.play().map_err(|e| e.to_string())?;
        Ok((None, Some(Box::new(stream))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::math::v3;

    #[test]
    fn synth_loops_seamlessly_and_respects_duration() {
        let s = Synth { wave: Wave::Saw, freq: 110.0, dur: 0.5, looped: true, ..Default::default() };
        let buf = s.render();
        let period = (RATE as f32 / 110.0).round() as usize;
        assert_eq!(buf.len() % period, 0, "loop must be whole periods");
        let one = Synth { wave: Wave::Sine, dur: 0.25, ..Default::default() }.render();
        assert_eq!(one.len(), (RATE as f32 * 0.25) as usize);
        assert!(one[0].abs() < 0.01 && one.last().unwrap().abs() < 0.01, "attack and release envelopes");
        let jingle = Synth { notes: vec![440.0, 660.0, 880.0], note_len: 0.1, ..Default::default() }.render();
        assert_eq!(jingle.len(), 3 * (RATE as f32 * 0.1) as usize);
    }

    #[test]
    fn mixer_plays_pans_and_finishes() {
        let mut m = Mixer::default();
        m.listener_right = v3(-1.0, 0.0, 0.0); // camera looks down +Z
        let data: Samples = Arc::new(vec![0.5; 1000]);
        // A source on the listener's right (-X) is louder in the right channel.
        let id = m.play(data.clone(), 1.0, 1.0, false, Some(v3(-5.0, 0.0, 0.0)), false);
        let mut out = vec![0.0; 2 * 256];
        m.mix(&mut out);
        let (l, r) = (out[200], out[201]);
        assert!(r > l * 2.0 && l > 0.0, "l={l} r={r}");
        // Double pitch finishes in half the time.
        m.set(id, None, Some(2.0), None);
        let mut out = vec![0.0; 2 * 512];
        m.mix(&mut out);
        assert!(!m.playing(id));
        // Loops keep going; stop removes them.
        let lp = m.play(data, 1.0, 1.0, true, None, false);
        m.mix(&mut vec![0.0; 2 * 4096]);
        assert!(m.playing(lp));
        m.stop(lp);
        assert_eq!(m.voice_count(), 0);
    }

    #[test]
    fn pausing_freezes_all_but_ui_voices() {
        let mut m = Mixer::default();
        let data: Samples = Arc::new(vec![0.5; 300]);
        let game = m.play(data.clone(), 1.0, 1.0, false, None, false);
        let click = m.play(data, 1.0, 1.0, false, None, true);
        m.paused = true;
        let mut out = vec![0.0; 2 * 400];
        m.mix(&mut out);
        assert!(out[0] > 0.0, "the ui voice is heard");
        assert!(m.playing(game) && !m.playing(click), "the game voice waits, the ui voice finishes");
        m.paused = false;
        m.mix(&mut out);
        assert!(!m.playing(game), "unpaused, the game voice resumes and finishes");
    }

    #[test]
    fn wav_roundtrip() {
        // 16-bit stereo 22050 Hz: left = +half, right = -half -> mono 0, upsampled x2.
        let mut w = Vec::new();
        let frames = 100u32;
        let data_len = frames * 4;
        w.extend_from_slice(b"RIFF");
        w.extend_from_slice(&(36 + data_len).to_le_bytes());
        w.extend_from_slice(b"WAVEfmt ");
        w.extend_from_slice(&16u32.to_le_bytes());
        for v in [1u16, 2] {
            w.extend_from_slice(&v.to_le_bytes());
        }
        w.extend_from_slice(&22050u32.to_le_bytes());
        w.extend_from_slice(&(22050u32 * 4).to_le_bytes());
        for v in [4u16, 16] {
            w.extend_from_slice(&v.to_le_bytes());
        }
        w.extend_from_slice(b"data");
        w.extend_from_slice(&data_len.to_le_bytes());
        for _ in 0..frames {
            w.extend_from_slice(&16384i16.to_le_bytes());
            w.extend_from_slice(&8192i16.to_le_bytes());
        }
        let s = load_wav(&w).unwrap();
        assert_eq!(s.len(), 200);
        assert!(s.iter().all(|x| (x - 0.375).abs() < 1e-3));
        assert!(load_wav(b"nope").is_err());
    }
}
