//! World streaming: meshes that are loaded only while the camera is near
//! them. The game registers each map tile's mesh with a centre and a radius
//! (`engine.stream`) and spawns its entity as usual; the mesh stays empty, so
//! nothing is drawn, until the camera comes within the radius. Then a worker
//! thread reads it (a packed `.mesh` file when there is one, see `meshbin`)
//! and the next frame puts it in place. Further than the radius plus a margin
//! the mesh is emptied again and the renderer drops its buffers.
use crate::mesh::Mesh;
use std::path::PathBuf;
#[cfg(not(target_arch = "wasm32"))]
use std::sync::mpsc;

/// Unload only past the radius plus this much, so a camera on the line
/// doesn't load and drop a tile every frame.
const MARGIN: f32 = 40.0;
/// Most vertices put in place in one frame: each one is copied to the GPU
/// on that frame, so a burst of tiles is spread over a few.
const VERTS_PER_FRAME: usize = 600_000;

#[derive(Clone, Copy, PartialEq, Debug)]
enum State {
    Out,
    /// Asked for; the number is which request, so an answer to an older one
    /// (the tile was dropped and asked for again meanwhile) is thrown away.
    Loading(u32),
    In,
}

struct Item {
    mesh: usize,
    path: PathBuf,
    x: f32,
    z: f32,
    radius: f32,
    state: State,
    asked: u32,
}

/// What a frame's update did, for the game and the profile.
#[derive(Default, Debug, Clone, Copy)]
pub struct Stats {
    pub loaded: usize,
    pub dropped: usize,
    pub waiting: usize,
    pub resident: usize,
}

type Done = (usize, u32, Result<Mesh, String>);

pub struct Streamer {
    items: Vec<Item>,
    #[cfg(not(target_arch = "wasm32"))]
    jobs: Option<mpsc::Sender<(usize, u32, PathBuf)>>,
    #[cfg(not(target_arch = "wasm32"))]
    done: mpsc::Receiver<Done>,
    #[cfg(not(target_arch = "wasm32"))]
    done_tx: mpsc::Sender<Done>,
    /// Finished loads not yet put in place (over a frame's budget).
    ready: Vec<Done>,
    pub stats: Stats,
    pub errors: Vec<String>,
}

impl Default for Streamer {
    fn default() -> Self {
        Self::new()
    }
}

impl Streamer {
    pub fn new() -> Streamer {
        #[cfg(not(target_arch = "wasm32"))]
        let (done_tx, done) = mpsc::channel();
        Streamer {
            items: Vec::new(),
            #[cfg(not(target_arch = "wasm32"))]
            jobs: None,
            #[cfg(not(target_arch = "wasm32"))]
            done,
            #[cfg(not(target_arch = "wasm32"))]
            done_tx,
            ready: Vec::new(),
            stats: Stats::default(),
            errors: Vec::new(),
        }
    }

    pub fn add(&mut self, mesh: usize, path: PathBuf, x: f32, z: f32, radius: f32) {
        self.items.push(Item { mesh, path, x, z, radius, state: State::Out, asked: 0 });
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// Start the worker threads on first use.
    #[cfg(not(target_arch = "wasm32"))]
    fn sender(&mut self) -> &mpsc::Sender<(usize, u32, PathBuf)> {
        if self.jobs.is_none() {
            let (tx, rx) = mpsc::channel::<(usize, u32, PathBuf)>();
            let rx = std::sync::Arc::new(std::sync::Mutex::new(rx));
            for k in 0..3 {
                let (rx, done) = (rx.clone(), self.done_tx.clone());
                std::thread::Builder::new()
                    .name(format!("stream {k}"))
                    .spawn(move || {
                        loop {
                            let job = rx.lock().unwrap().recv();
                            let Ok((item, asked, path)) = job else { break };
                            if done.send((item, asked, crate::meshbin::load(&path))).is_err() {
                                break;
                            }
                        }
                    })
                    .expect("stream thread");
            }
            self.jobs = Some(tx);
        }
        self.jobs.as_ref().unwrap()
    }

    fn ask(&mut self, i: usize) {
        let item = &mut self.items[i];
        item.asked += 1;
        item.state = State::Loading(item.asked);
        let (asked, path) = (item.asked, item.path.clone());
        #[cfg(not(target_arch = "wasm32"))]
        {
            let _ = self.sender().send((i, asked, path));
        }
        #[cfg(target_arch = "wasm32")]
        self.ready.push((i, asked, crate::meshbin::load(&path)));
    }

    /// One frame: ask for what came in range (nearest first), drop what went
    /// out of it, and hand back finished meshes to put in place (mesh id,
    /// mesh), empty ones for drops. With `settle`, wait for every load in
    /// range and return them all (screenshots, tests).
    pub fn update(&mut self, eye_x: f32, eye_z: f32, settle: bool) -> Vec<(usize, Mesh)> {
        let mut out = Vec::new();
        let mut wanted: Vec<(f32, usize)> = Vec::new();
        let (mut dropped, mut resident) = (0, 0);
        for (i, item) in self.items.iter_mut().enumerate() {
            let d = ((item.x - eye_x).powi(2) + (item.z - eye_z).powi(2)).sqrt();
            match item.state {
                State::Out if d < item.radius => wanted.push((d, i)),
                State::In | State::Loading(_) if d > item.radius + MARGIN => {
                    if item.state == State::In {
                        out.push((item.mesh, Mesh::default()));
                        dropped += 1;
                    }
                    item.state = State::Out;
                }
                State::In => resident += 1,
                _ => {}
            }
        }
        wanted.sort_by(|a, b| a.0.total_cmp(&b.0));
        for &(_, i) in &wanted {
            self.ask(i);
        }
        #[cfg(not(target_arch = "wasm32"))]
        loop {
            let waiting = self.items.iter().filter(|it| matches!(it.state, State::Loading(_))).count();
            let pending = self.ready.iter().filter(|(i, asked, _)| self.items[*i].state == State::Loading(*asked)).count();
            if settle && pending < waiting {
                if let Ok(d) = self.done.recv() {
                    self.ready.push(d);
                }
                continue;
            }
            while let Ok(d) = self.done.try_recv() {
                self.ready.push(d);
            }
            break;
        }
        let mut budget = if settle { usize::MAX } else { VERTS_PER_FRAME };
        let mut loaded = 0;
        let mut keep = Vec::new();
        for (i, asked, result) in std::mem::take(&mut self.ready) {
            let item = &mut self.items[i];
            if item.state != State::Loading(asked) {
                continue; // dropped, or asked for again since
            }
            match result {
                Ok(m) if m.verts.len() <= budget || loaded == 0 => {
                    budget = budget.saturating_sub(m.verts.len());
                    item.state = State::In;
                    out.push((item.mesh, m));
                    loaded += 1;
                    resident += 1;
                }
                Ok(m) => keep.push((i, asked, Ok(m))),
                Err(e) => {
                    item.state = State::In; // don't ask again every frame
                    self.errors.push(e);
                }
            }
        }
        self.ready = keep;
        let waiting = self.items.iter().filter(|it| matches!(it.state, State::Loading(_))).count();
        self.stats = Stats { loaded, dropped, waiting, resident };
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::math::v3;

    fn write_tile(dir: &std::path::Path, name: &str) -> PathBuf {
        let mut m = Mesh::default();
        m.tri(v3(0.0, 0.0, 0.0), v3(1.0, 0.0, 0.0), v3(0.0, 1.0, 0.0), v3(1.0, 1.0, 1.0));
        let p = dir.join(format!("{name}.obj"));
        std::fs::write(&p, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap();
        std::fs::write(crate::meshbin::beside(&p), crate::meshbin::encode(&m)).unwrap();
        p
    }

    #[test]
    fn loads_near_and_drops_far() {
        let dir = std::env::temp_dir().join(format!("auto-stream-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut s = Streamer::new();
        s.add(10, write_tile(&dir, "a"), 0.0, 0.0, 100.0);
        s.add(11, write_tile(&dir, "b"), 500.0, 0.0, 100.0);
        let got = s.update(0.0, 0.0, true);
        assert_eq!(got.iter().map(|g| g.0).collect::<Vec<_>>(), vec![10]);
        assert_eq!(got[0].1.indices.len(), 3);
        // Past the radius but inside the margin: kept.
        assert!(s.update(120.0, 0.0, true).is_empty());
        // Walk to the other tile: the first is emptied, the second loads.
        let got = s.update(500.0, 0.0, true);
        let mut ids: Vec<_> = got.iter().map(|g| (g.0, g.1.indices.len())).collect();
        ids.sort();
        assert_eq!(ids, vec![(10, 0), (11, 3)]);
        assert_eq!((s.stats.dropped, s.stats.resident), (1, 1));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
