//! Packs the game folder into the module: one blob of (name, bytes) records,
//! each a little-endian u32 length and then the bytes. Names are relative to
//! the repository ("game/main.lua"), the way the game sees them under "/".
use std::fs;
use std::path::Path;

fn walk(dir: &Path, base: &Path, out: &mut Vec<u8>, n: &mut usize) {
    let mut entries: Vec<_> = fs::read_dir(dir).unwrap().flatten().map(|e| e.path()).collect();
    entries.sort();
    for p in entries {
        if p.is_dir() {
            walk(&p, base, out, n);
        } else {
            let name = p.strip_prefix(base).unwrap().to_string_lossy().replace('\\', "/");
            let data = fs::read(&p).unwrap();
            for chunk in [name.as_bytes(), &data[..]] {
                out.extend_from_slice(&(chunk.len() as u32).to_le_bytes());
                out.extend_from_slice(chunk);
            }
            *n += 1;
        }
    }
}

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let game = root.join("game");
    println!("cargo:rerun-if-changed={}", game.display());
    let (mut out, mut n) = (Vec::new(), 0);
    walk(&game, root, &mut out, &mut n);
    let pack = Path::new(&std::env::var("OUT_DIR").unwrap()).join("game.pack");
    fs::write(&pack, &out).unwrap();
    println!("cargo:rustc-env=GAME_PACK={}", pack.display());
    println!("cargo:warning=packed {n} game files, {:.1} MB", out.len() as f64 / 1e6);
}
