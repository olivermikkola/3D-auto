//! The game's files: read from disk, or in a browser from the copy packed
//! into the module (see web/build.rs). Only reads; saves live in save.rs.
use std::io;
use std::path::Path;

#[cfg(not(target_arch = "wasm32"))]
pub fn read(path: &Path) -> io::Result<Vec<u8>> {
    std::fs::read(path)
}

#[cfg(target_arch = "wasm32")]
pub fn read(path: &Path) -> io::Result<Vec<u8>> {
    crate::web::file(&path.to_string_lossy())
        .map(<[u8]>::to_vec)
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "not in the game pack"))
}

pub fn read_to_string(path: &Path) -> io::Result<String> {
    String::from_utf8(read(path)?).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

/// Names in a folder, sorted: its subfolders when `dirs`, else its files.
#[cfg(not(target_arch = "wasm32"))]
pub fn list(dir: &Path, dirs: bool) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .map(|rd| {
            rd.filter_map(|d| {
                let d = d.ok()?;
                (d.file_type().ok()?.is_dir() == dirs).then(|| d.file_name().into_string().ok())?
            })
            .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

#[cfg(target_arch = "wasm32")]
pub fn list(dir: &Path, dirs: bool) -> Vec<String> {
    let mut names = crate::web::list(&dir.to_string_lossy(), dirs);
    names.sort();
    names.dedup();
    names
}
