//! The browser build: the game folder packed into the module, and the WASI
//! system calls Lua's C library makes, answered here instead of by the page.
//! Files open read-only from the pack under "/", the environment comes from
//! the page's address (`?map=raisio&hour=22` sets MAP and HOUR), and what Lua
//! prints goes to the browser console. Everything else fails as "not
//! supported", which the C library reports as an ordinary error.
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::OnceLock;

static PACK: &[u8] = include_bytes!(env!("GAME_PACK"));

fn files() -> &'static HashMap<String, &'static [u8]> {
    static FILES: OnceLock<HashMap<String, &'static [u8]>> = OnceLock::new();
    FILES.get_or_init(|| {
        let (mut m, mut at) = (HashMap::new(), 0);
        let next = |at: &mut usize| {
            let n = u32::from_le_bytes(PACK[*at..*at + 4].try_into().unwrap()) as usize;
            *at += 4 + n;
            &PACK[*at - n..*at]
        };
        while at < PACK.len() {
            let name = String::from_utf8_lossy(next(&mut at)).into_owned();
            m.insert(name, next(&mut at));
        }
        m
    })
}

/// "/game/./lib/../x.lua" -> "game/x.lua", the pack's way of naming files.
fn normal(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for p in path.split('/') {
        match p {
            "" | "." => {}
            ".." => drop(parts.pop()),
            p => parts.push(p),
        }
    }
    parts.join("/")
}

pub fn file(path: &str) -> Option<&'static [u8]> {
    files().get(&normal(path)).copied()
}

/// The names directly inside `dir`: subfolders when `dirs`, else files.
pub fn list(dir: &str, dirs: bool) -> Vec<String> {
    let prefix = format!("{}/", normal(dir));
    files()
        .keys()
        .filter_map(|k| {
            let rest = k.strip_prefix(&prefix)?;
            match rest.split_once('/') {
                Some((d, _)) if dirs => Some(d.to_string()),
                None if !dirs => Some(rest.to_string()),
                _ => None,
            }
        })
        .collect()
}

#[link(wasm_import_module = "env")]
unsafe extern "C" {
    /// From miniquad's gl.js: a NUL-terminated line to the console.
    fn console_log(msg: *const std::ffi::c_char);
    /// From web/index.html: copies the page's query string ("?a=b") into
    /// `buf` (at most `cap` bytes) and returns its full length.
    fn web_query(buf: *mut u8, cap: usize) -> usize;
}

pub fn log(line: &str) {
    if let Ok(c) = std::ffi::CString::new(line.replace('\0', " ")) {
        unsafe { console_log(c.as_ptr()) }
    }
}

/// The environment from the page's address: each `key=value` becomes KEY=value.
fn environment() -> Vec<String> {
    let mut buf = vec![0u8; 1024];
    let n = unsafe { web_query(buf.as_mut_ptr(), buf.len()) }.min(buf.len());
    let q = String::from_utf8_lossy(&buf[..n]).into_owned();
    q.trim_start_matches('?')
        .split('&')
        .filter_map(|kv| kv.split_once('='))
        .filter(|(k, _)| !k.is_empty() && k.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'))
        .map(|(k, v)| format!("{}={}", k.to_ascii_uppercase(), v.replace("%20", " ")))
        .collect()
}

/// Panics and the game's console lines to the browser console.
pub fn init() {
    std::panic::set_hook(Box::new(|info| log(&format!("panic: {info}"))));
    STATE.with(|s| s.borrow_mut().env = environment());
}

// ---- WASI preview1 ---------------------------------------------------------------

const ESUCCESS: i32 = 0;
const EBADF: i32 = 8;
const EINVAL: i32 = 28;
const ENOENT: i32 = 44;
const ENOSYS: i32 = 52;
const PREOPEN: i32 = 3; // the one directory, "/"

struct State {
    open: HashMap<i32, (&'static [u8], usize)>,
    next_fd: i32,
    env: Vec<String>,
    line: [Vec<u8>; 2],
    seed: u64,
}

thread_local! {
    static STATE: RefCell<State> = RefCell::new(State {
        open: HashMap::new(),
        next_fd: PREOPEN + 1,
        env: Vec::new(),
        line: [Vec::new(), Vec::new()],
        seed: 0x9e37_79b9_7f4a_7c15,
    });
}

unsafe fn mem<'a>(p: i32, n: i32) -> &'a mut [u8] {
    unsafe { std::slice::from_raw_parts_mut(p as u32 as usize as *mut u8, n as u32 as usize) }
}
unsafe fn put_u32(p: i32, v: u32) {
    unsafe { mem(p, 4).copy_from_slice(&v.to_le_bytes()) }
}
unsafe fn put_u64(p: i32, v: u64) {
    unsafe { mem(p, 8).copy_from_slice(&v.to_le_bytes()) }
}
unsafe fn iovecs(at: i32, n: i32) -> Vec<(i32, i32)> {
    (0..n)
        .map(|i| unsafe {
            let b = mem(at + 8 * i, 8);
            (i32::from_le_bytes(b[0..4].try_into().unwrap()), i32::from_le_bytes(b[4..8].try_into().unwrap()))
        })
        .collect()
}

macro_rules! wasi {
    ($($name:ident ($($a:ident: $t:ty),*) $body:block)*) => {$(
        #[unsafe(no_mangle)]
        #[allow(unused_variables, unused_unsafe)]
        pub unsafe extern "C" fn $name($($a: $t),*) -> i32 { unsafe { $body } }
    )*};
}

wasi! {
    __imported_wasi_snapshot_preview1_fd_prestat_get(fd: i32, buf: i32) {
        if fd != PREOPEN { return EBADF; }
        mem(buf, 8).fill(0); // a directory...
        put_u32(buf + 4, 1); // ...named "/"
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_fd_prestat_dir_name(fd: i32, p: i32, n: i32) {
        if fd != PREOPEN || n < 1 { return EBADF; }
        mem(p, 1)[0] = b'/';
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_path_open(dir: i32, dirflags: i32, p: i32, n: i32, oflags: i32, rb: i64, ri: i64, fdflags: i32, out: i32) {
        if dir != PREOPEN { return EBADF; }
        let Some(data) = file(&String::from_utf8_lossy(mem(p, n))) else { return ENOENT };
        STATE.with(|s| {
            let mut s = s.borrow_mut();
            let fd = s.next_fd;
            s.next_fd += 1;
            s.open.insert(fd, (data, 0));
            put_u32(out, fd as u32);
        });
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_fd_read(fd: i32, iovs: i32, n: i32, nread: i32) {
        STATE.with(|s| {
            let mut s = s.borrow_mut();
            let Some((data, pos)) = s.open.get_mut(&fd) else {
                if fd != 0 { return EBADF; }
                put_u32(nread, 0); // stdin: always at its end
                return ESUCCESS;
            };
            let mut total = 0;
            for (p, l) in iovecs(iovs, n) {
                let k = (data.len() - *pos).min(l as usize);
                mem(p, k as i32).copy_from_slice(&data[*pos..*pos + k]);
                *pos += k;
                total += k;
            }
            put_u32(nread, total as u32);
            ESUCCESS
        })
    }
    __imported_wasi_snapshot_preview1_fd_seek(fd: i32, off: i64, whence: i32, out: i32) {
        STATE.with(|s| {
            let mut s = s.borrow_mut();
            let Some((data, pos)) = s.open.get_mut(&fd) else { return EBADF };
            let base = match whence { 0 => 0, 1 => *pos as i64, 2 => data.len() as i64, _ => return EINVAL };
            if base + off < 0 { return EINVAL; }
            *pos = ((base + off) as usize).min(data.len());
            put_u64(out, *pos as u64);
            ESUCCESS
        })
    }
    __imported_wasi_snapshot_preview1_fd_tell(fd: i32, out: i32) {
        STATE.with(|s| match s.borrow().open.get(&fd) {
            Some((_, pos)) => { put_u64(out, *pos as u64); ESUCCESS }
            None => EBADF,
        })
    }
    __imported_wasi_snapshot_preview1_fd_close(fd: i32) {
        STATE.with(|s| if s.borrow_mut().open.remove(&fd).is_some() { ESUCCESS } else { EBADF })
    }
    __imported_wasi_snapshot_preview1_fd_fdstat_get(fd: i32, buf: i32) {
        let kind = match fd {
            0..=2 => 2, // character device
            PREOPEN => 3, // directory
            _ if STATE.with(|s| s.borrow().open.contains_key(&fd)) => 4, // regular file
            _ => return EBADF,
        };
        mem(buf, 24).fill(0);
        mem(buf, 1)[0] = kind;
        put_u64(buf + 8, u64::MAX);
        put_u64(buf + 16, u64::MAX);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_fd_filestat_get(fd: i32, buf: i32) {
        let Some(len) = STATE.with(|s| s.borrow().open.get(&fd).map(|(d, _)| d.len())) else { return EBADF };
        mem(buf, 64).fill(0);
        mem(buf + 16, 1)[0] = 4;
        put_u64(buf + 24, 1);
        put_u64(buf + 32, len as u64);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_path_filestat_get(dir: i32, flags: i32, p: i32, n: i32, buf: i32) {
        if dir != PREOPEN { return EBADF; }
        let path = String::from_utf8_lossy(mem(p, n)).into_owned();
        let (kind, len) = match file(&path) {
            Some(d) => (4, d.len()),
            None if !list(&path, true).is_empty() || !list(&path, false).is_empty() => (3, 0),
            None => return ENOENT,
        };
        mem(buf, 64).fill(0);
        mem(buf + 16, 1)[0] = kind;
        put_u64(buf + 24, 1);
        put_u64(buf + 32, len as u64);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_fd_write(fd: i32, iovs: i32, n: i32, nwritten: i32) {
        if fd != 1 && fd != 2 { return EBADF; }
        let mut total = 0;
        STATE.with(|s| {
            let mut s = s.borrow_mut();
            let line = &mut s.line[(fd - 1) as usize];
            for (p, l) in iovecs(iovs, n) {
                line.extend_from_slice(mem(p, l));
                total += l;
            }
            while let Some(k) = line.iter().position(|&b| b == b'\n') {
                let text: Vec<u8> = line.drain(..=k).collect();
                log(String::from_utf8_lossy(&text[..k]).as_ref());
            }
        });
        put_u32(nwritten, total as u32);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_environ_sizes_get(count: i32, size: i32) {
        STATE.with(|s| {
            let s = s.borrow();
            put_u32(count, s.env.len() as u32);
            put_u32(size, s.env.iter().map(|e| e.len() + 1).sum::<usize>() as u32);
        });
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_environ_get(ptrs: i32, buf: i32) {
        STATE.with(|s| {
            let mut at = buf;
            for (i, e) in s.borrow().env.iter().enumerate() {
                put_u32(ptrs + 4 * i as i32, at as u32);
                let m = mem(at, e.len() as i32 + 1);
                m[..e.len()].copy_from_slice(e.as_bytes());
                m[e.len()] = 0;
                at += e.len() as i32 + 1;
            }
        });
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_args_sizes_get(count: i32, size: i32) {
        put_u32(count, 0);
        put_u32(size, 0);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_args_get(argv: i32, buf: i32) { ESUCCESS }
    __imported_wasi_snapshot_preview1_clock_time_get(id: i32, precision: i64, out: i32) {
        put_u64(out, (miniquad::date::now() * 1e9) as u64);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_clock_res_get(id: i32, out: i32) {
        put_u64(out, 1_000);
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_random_get(buf: i32, n: i32) {
        STATE.with(|s| {
            let mut s = s.borrow_mut();
            s.seed ^= (miniquad::date::now() * 1e6) as u64;
            for b in mem(buf, n) {
                s.seed ^= s.seed << 13;
                s.seed ^= s.seed >> 7;
                s.seed ^= s.seed << 17;
                *b = s.seed as u8;
            }
        });
        ESUCCESS
    }
    __imported_wasi_snapshot_preview1_sched_yield() { ESUCCESS }
    // Read-only, no sockets, no directories to list: not supported.
    __imported_wasi_snapshot_preview1_fd_advise(fd: i32, off: i64, len: i64, advice: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_allocate(fd: i32, off: i64, len: i64) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_datasync(fd: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_fdstat_set_flags(fd: i32, flags: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_fdstat_set_rights(fd: i32, base: i64, inh: i64) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_filestat_set_size(fd: i32, size: i64) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_filestat_set_times(fd: i32, a: i64, m: i64, flags: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_pread(fd: i32, iovs: i32, n: i32, off: i64, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_pwrite(fd: i32, iovs: i32, n: i32, off: i64, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_readdir(fd: i32, buf: i32, len: i32, cookie: i64, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_renumber(fd: i32, to: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_fd_sync(fd: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_create_directory(fd: i32, p: i32, n: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_filestat_set_times(fd: i32, flags: i32, p: i32, n: i32, a: i64, m: i64, f: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_link(ofd: i32, of: i32, op: i32, on: i32, nfd: i32, np: i32, nn: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_readlink(fd: i32, p: i32, n: i32, buf: i32, len: i32, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_remove_directory(fd: i32, p: i32, n: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_rename(fd: i32, op: i32, on: i32, nfd: i32, np: i32, nn: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_symlink(op: i32, on: i32, fd: i32, np: i32, nn: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_path_unlink_file(fd: i32, p: i32, n: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_poll_oneoff(i: i32, o: i32, n: i32, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_sock_accept(fd: i32, flags: i32, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_sock_recv(fd: i32, d: i32, n: i32, f: i32, len: i32, of: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_sock_send(fd: i32, d: i32, n: i32, f: i32, out: i32) { ENOSYS }
    __imported_wasi_snapshot_preview1_sock_shutdown(fd: i32, how: i32) { ENOSYS }
}

/// exit() from C: there is nothing to exit to in a page.
#[unsafe(no_mangle)]
pub extern "C" fn __imported_wasi_snapshot_preview1_proc_exit(code: i32) {
    panic!("the game called exit({code})");
}
