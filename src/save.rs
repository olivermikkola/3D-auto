//! Save data. A script stores a plain Lua value (tables, strings, numbers,
//! booleans) under a key, and each key is one small file of Lua table syntax
//! in the user's data folder. Files are parsed as data, never run as code,
//! so a hand-edited or hostile save can't do anything but fail to load.

use mlua::{Lua, Table, Value};
use std::collections::HashMap;
use std::fmt::Write;
use std::path::PathBuf;

/// Largest encoded value, and most keys a store will hold. Saves are for
/// progress and settings, so these are generous; they bound what a runaway
/// or hostile script can write to disk.
pub const MAX_BYTES: usize = 256 * 1024;
pub const MAX_KEYS: usize = 64;
const MAX_DEPTH: usize = 64;
const HEADER: &str = "-- auto save data: plain Lua table syntax, read as data and never run.\nreturn ";

/// Where saves live: a folder on disk, the browser's localStorage, or
/// (headless runs, screenshots) memory that is gone when the process exits.
pub enum Store {
    Dir(PathBuf),
    Memory(HashMap<String, String>),
    #[cfg(target_arch = "wasm32")]
    Web,
}

impl Default for Store {
    fn default() -> Store {
        Store::Memory(HashMap::new())
    }
}

impl Store {
    /// The browser's localStorage (memory anywhere else).
    pub fn browser() -> Store {
        #[cfg(target_arch = "wasm32")]
        return Store::Web;
        #[cfg(not(target_arch = "wasm32"))]
        Store::default()
    }

    fn file(dir: &std::path::Path, key: &str) -> PathBuf {
        dir.join(format!("{key}.lua"))
    }

    pub fn read(&self, key: &str) -> std::io::Result<Option<String>> {
        match self {
            Store::Memory(m) => Ok(m.get(key).cloned()),
            #[cfg(target_arch = "wasm32")]
            Store::Web => Ok(crate::web::save_get(key)),
            Store::Dir(d) => match std::fs::read_to_string(Self::file(d, key)) {
                Ok(s) => Ok(Some(s)),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
                Err(e) => Err(e),
            },
        }
    }

    /// Write `text` under `key`, or delete the key when `text` is None. The
    /// file is replaced atomically, so a crash mid-save keeps the old one.
    pub fn write(&mut self, key: &str, text: Option<&str>) -> std::io::Result<()> {
        match (self, text) {
            (Store::Memory(m), Some(t)) => drop(m.insert(key.to_string(), t.to_string())),
            (Store::Memory(m), None) => drop(m.remove(key)),
            #[cfg(target_arch = "wasm32")]
            (Store::Web, t) => crate::web::save_set(key, t)?,
            (Store::Dir(d), Some(t)) => {
                std::fs::create_dir_all(&*d)?;
                let tmp = d.join(format!("{key}.lua.tmp"));
                std::fs::write(&tmp, t)?;
                std::fs::rename(&tmp, Self::file(d, key))?;
            }
            (Store::Dir(d), None) => match std::fs::remove_file(Self::file(d, key)) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e),
                _ => {}
            },
        }
        Ok(())
    }

    /// Set aside an unreadable save (as `key.lua.bad`) so the next save
    /// doesn't overwrite what a person may want to fix by hand.
    pub fn quarantine(&mut self, key: &str) -> Option<PathBuf> {
        match self {
            Store::Memory(m) => {
                m.remove(key);
                None
            }
            #[cfg(target_arch = "wasm32")]
            Store::Web => {
                let bad = format!("{key}.bad");
                let text = crate::web::save_get(key)?;
                crate::web::save_set(&bad, Some(&text)).ok()?;
                crate::web::save_set(key, None).ok()?;
                Some(PathBuf::from(bad))
            }
            Store::Dir(d) => {
                let bad = d.join(format!("{key}.lua.bad"));
                std::fs::rename(Self::file(d, key), &bad).ok().map(|_| bad)
            }
        }
    }

    /// Stored keys, sorted.
    pub fn keys(&self) -> Vec<String> {
        let mut k: Vec<String> = match self {
            Store::Memory(m) => m.keys().cloned().collect(),
            #[cfg(target_arch = "wasm32")]
            Store::Web => crate::web::save_keys().into_iter().filter(|k| !k.ends_with(".bad")).collect(),
            Store::Dir(d) => std::fs::read_dir(d)
                .map(|rd| rd.flatten().filter_map(|e| e.file_name().into_string().ok()?.strip_suffix(".lua").map(String::from)).collect())
                .unwrap_or_default(),
        };
        k.sort();
        k
    }
}

/// The per-user folder for a game's saves, e.g. `~/.local/share/auto/game`.
pub fn user_dir(game: &str) -> Option<PathBuf> {
    let env = |k: &str| std::env::var_os(k).filter(|v| !v.is_empty()).map(PathBuf::from);
    let base = if cfg!(windows) {
        env("APPDATA")?
    } else if cfg!(target_os = "macos") {
        env("HOME")?.join("Library/Application Support")
    } else {
        env("XDG_DATA_HOME").or_else(|| Some(env("HOME")?.join(".local/share")))?
    };
    Some(base.join("auto").join(game))
}

/// Keys become file names, so they are short and plain: letters, digits,
/// `_`, `-` and `.`, not starting with a dot, and never a name Windows reserves.
pub fn check_key(key: &str) -> Result<(), String> {
    let plain = key.bytes().all(|b| b.is_ascii_alphanumeric() || b"_-.".contains(&b));
    let stem = key.split('.').next().unwrap_or("").to_ascii_lowercase();
    let reserved = matches!(stem.as_str(), "con" | "prn" | "aux" | "nul")
        || (stem.len() == 4 && (stem.starts_with("com") || stem.starts_with("lpt")) && stem.as_bytes()[3].is_ascii_digit());
    if key.is_empty() || key.len() > 64 || !plain || key.starts_with('.') || key.contains("..") || reserved {
        return Err(format!("bad save key '{key}': use up to 64 letters, digits, '_', '-' or '.'"));
    }
    Ok(())
}

// ---- encoding ---------------------------------------------------------------

/// The file contents for a value.
pub fn encode(v: &Value) -> Result<String, String> {
    let mut out = String::from(HEADER);
    write_value(&mut out, v, 0)?;
    out.push('\n');
    if out.len() > MAX_BYTES {
        return Err(format!("save data is {} KB; the limit is {} KB", out.len() / 1024, MAX_BYTES / 1024));
    }
    Ok(out)
}

const KEYWORDS: &[&str] = &[
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while",
];

fn is_ident(s: &[u8]) -> bool {
    let ok_start = s.first().is_some_and(|c| c.is_ascii_alphabetic() || *c == b'_');
    ok_start && s.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_') && !KEYWORDS.iter().any(|k| k.as_bytes() == s)
}

fn write_string(out: &mut String, s: &[u8]) {
    let escape = |out: &mut String, c: char| match c {
        '"' => out.push_str("\\\""),
        '\\' => out.push_str("\\\\"),
        '\n' => out.push_str("\\n"),
        '\r' => out.push_str("\\r"),
        '\t' => out.push_str("\\t"),
        // Decimal escapes are always three digits so a following digit is safe.
        c if c < ' ' || c == '\x7f' => write!(out, "\\{:03}", c as u32).unwrap(),
        c => out.push(c),
    };
    out.push('"');
    match std::str::from_utf8(s) {
        // Valid UTF-8 stays readable; otherwise every non-ASCII byte is escaped.
        Ok(text) => text.chars().for_each(|c| escape(out, c)),
        Err(_) => s.iter().for_each(|&b| if b < 0x80 { escape(out, b as char) } else { write!(out, "\\{b:03}").unwrap() }),
    }
    out.push('"');
}

fn write_number(out: &mut String, n: f64) -> Result<(), String> {
    if !n.is_finite() {
        return Err(format!("can't save the number {n}"));
    }
    // Debug formatting is the shortest text that reads back to the same f64,
    // and always has a '.' or exponent, so it reloads as a float.
    write!(out, "{n:?}").unwrap();
    Ok(())
}

fn write_value(out: &mut String, v: &Value, depth: usize) -> Result<(), String> {
    match v {
        Value::Boolean(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Integer(i) => write!(out, "{i}").unwrap(),
        Value::Number(n) => write_number(out, *n)?,
        Value::String(s) => write_string(out, &s.as_bytes()),
        Value::Table(t) => write_table(out, t, depth + 1)?,
        Value::Nil => out.push_str("nil"),
        other => return Err(format!("can't save a {}", other.type_name())),
    }
    Ok(())
}

fn key_rank(k: &Value) -> (u8, f64, Vec<u8>) {
    match k {
        Value::Boolean(b) => (0, *b as u8 as f64, Vec::new()),
        Value::Integer(i) => (1, *i as f64, Vec::new()),
        Value::Number(n) => (1, *n, Vec::new()),
        Value::String(s) => (2, 0.0, s.as_bytes().to_vec()),
        _ => (3, 0.0, Vec::new()),
    }
}

fn write_table(out: &mut String, t: &Table, depth: usize) -> Result<(), String> {
    if depth > MAX_DEPTH {
        return Err("save data is nested too deeply (or a table contains itself)".into());
    }
    let mut pairs = Vec::new();
    for p in t.pairs::<Value, Value>() {
        pairs.push(p.map_err(|e| e.to_string())?);
    }
    if pairs.is_empty() {
        out.push_str("{}");
        return Ok(());
    }
    pairs.sort_by(|a, b| {
        let (ra, rb) = (key_rank(&a.0), key_rank(&b.0));
        ra.0.cmp(&rb.0).then(ra.1.total_cmp(&rb.1)).then(ra.2.cmp(&rb.2))
    });
    // A proper sequence (keys exactly 1..n) is written as a plain list.
    let list = pairs.iter().enumerate().all(|(i, (k, _))| matches!(k, Value::Integer(n) if *n == i as i64 + 1));
    let pad = "  ".repeat(depth);
    out.push_str("{\n");
    for (k, v) in &pairs {
        out.push_str(&pad);
        if !list {
            match k {
                Value::String(s) if is_ident(&s.as_bytes()) => out.push_str(&s.to_str().unwrap()),
                Value::String(_) | Value::Integer(_) | Value::Number(_) | Value::Boolean(_) => {
                    out.push('[');
                    write_value(out, k, depth)?;
                    out.push(']');
                }
                other => return Err(format!("can't save a table key of type {}", other.type_name())),
            }
            out.push_str(" = ");
        }
        write_value(out, v, depth)?;
        out.push_str(",\n");
    }
    out.push_str(&"  ".repeat(depth - 1));
    out.push('}');
    Ok(())
}

// ---- decoding ---------------------------------------------------------------

/// Parse a save file back into a Lua value. Accepts what `encode` writes
/// and what a person might reasonably type: comments, single quotes, `;`
/// separators, trailing commas and a leading `return`.
pub fn decode(lua: &Lua, src: &str) -> Result<Value, String> {
    let mut p = Parser { s: src.as_bytes(), i: 0, lua };
    p.skip();
    if p.word() == Some("return") {
        p.i += 6;
    }
    let v = p.value(0)?;
    p.skip();
    if p.i < p.s.len() {
        return Err(p.err("unexpected text after the value"));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
    lua: &'a Lua,
}

impl Parser<'_> {
    fn err(&self, what: &str) -> String {
        let line = 1 + self.s[..self.i.min(self.s.len())].iter().filter(|&&c| c == b'\n').count();
        format!("line {line}: {what}")
    }

    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }

    /// Skip whitespace and `--` comments, including `--[[ long ]]` ones.
    fn skip(&mut self) {
        loop {
            while self.peek().is_some_and(|c| c.is_ascii_whitespace()) {
                self.i += 1;
            }
            if !self.s[self.i..].starts_with(b"--") {
                return;
            }
            self.i += 2;
            if self.s[self.i..].starts_with(b"[[") {
                let end = self.s[self.i..].windows(2).position(|w| w == b"]]");
                self.i = end.map_or(self.s.len(), |e| self.i + e + 2);
            } else {
                while self.peek().is_some_and(|c| c != b'\n') {
                    self.i += 1;
                }
            }
        }
    }

    /// The identifier at the cursor, without consuming it.
    fn word(&self) -> Option<&str> {
        let len = self.s[self.i..].iter().take_while(|c| c.is_ascii_alphanumeric() || **c == b'_').count();
        let w = &self.s[self.i..self.i + len];
        is_ident(w).then(|| std::str::from_utf8(w).unwrap()).or_else(|| {
            // Keywords aren't identifiers, but true/false/nil/return are words here.
            let w = std::str::from_utf8(w).ok()?;
            ["true", "false", "nil", "return"].contains(&w).then_some(w)
        })
    }

    fn expect(&mut self, c: u8) -> Result<(), String> {
        self.skip();
        if self.peek() != Some(c) {
            return Err(self.err(&format!("expected '{}'", c as char)));
        }
        self.i += 1;
        Ok(())
    }

    fn value(&mut self, depth: usize) -> Result<Value, String> {
        self.skip();
        match self.peek() {
            Some(b'{') => self.table(depth + 1),
            Some(q @ (b'"' | b'\'')) => self.string(q),
            Some(b'-' | b'.' | b'0'..=b'9') => self.number(),
            Some(_) => {
                let (v, len) = match self.word() {
                    Some("true") => (Value::Boolean(true), 4),
                    Some("false") => (Value::Boolean(false), 5),
                    Some("nil") => (Value::Nil, 3),
                    _ => return Err(self.err("expected a value (table, string, number, true, false or nil)")),
                };
                self.i += len;
                Ok(v)
            }
            None => Err(self.err("unexpected end of file")),
        }
    }

    fn table(&mut self, depth: usize) -> Result<Value, String> {
        if depth > MAX_DEPTH {
            return Err(self.err("tables nested too deeply"));
        }
        self.i += 1; // {
        let t = self.lua.create_table().map_err(|e| e.to_string())?;
        let mut next = 1i64;
        loop {
            self.skip();
            if self.peek() == Some(b'}') {
                self.i += 1;
                return Ok(Value::Table(t));
            }
            let key = if self.peek() == Some(b'[') && self.s.get(self.i + 1) != Some(&b'[') {
                self.i += 1;
                let k = self.value(depth)?;
                self.expect(b']')?;
                self.expect(b'=')?;
                Some(k)
            } else if let Some(w) = self.word().filter(|w| !["true", "false", "nil"].contains(w)) {
                let w = w.to_string();
                self.i += w.len();
                self.expect(b'=')?;
                Some(Value::String(self.lua.create_string(&w).map_err(|e| e.to_string())?))
            } else {
                None
            };
            let v = self.value(depth)?;
            let k = match key {
                Some(Value::Nil) => return Err(self.err("a table key can't be nil")),
                Some(Value::Number(n)) if n.is_nan() => return Err(self.err("a table key can't be NaN")),
                Some(k) => k,
                None => {
                    next += 1;
                    Value::Integer(next - 1)
                }
            };
            t.raw_set(k, v).map_err(|e| e.to_string())?;
            self.skip();
            match self.peek() {
                Some(b',' | b';') => self.i += 1,
                Some(b'}') => {}
                _ => return Err(self.err("expected ',' or '}'")),
            }
        }
    }

    fn string(&mut self, quote: u8) -> Result<Value, String> {
        self.i += 1;
        let mut out = Vec::new();
        loop {
            let Some(c) = self.peek() else { return Err(self.err("unfinished string")) };
            self.i += 1;
            match c {
                c if c == quote => break,
                b'\n' => return Err(self.err("unfinished string")),
                b'\\' => {
                    let Some(e) = self.peek() else { return Err(self.err("unfinished string")) };
                    self.i += 1;
                    match e {
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'a' => out.push(7),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'v' => out.push(11),
                        b'\\' | b'"' | b'\'' | b'\n' => out.push(e),
                        b'0'..=b'9' => {
                            let digits = self.s[self.i - 1..].iter().take(3).take_while(|c| c.is_ascii_digit()).count();
                            let n: u32 = std::str::from_utf8(&self.s[self.i - 1..self.i - 1 + digits]).unwrap().parse().unwrap();
                            if n > 255 {
                                return Err(self.err("escape too large"));
                            }
                            out.push(n as u8);
                            self.i += digits - 1;
                        }
                        b'x' => {
                            let hex =
                                self.s.get(self.i..self.i + 2).and_then(|h| u8::from_str_radix(std::str::from_utf8(h).ok()?, 16).ok());
                            out.push(hex.ok_or_else(|| self.err("bad \\x escape"))?);
                            self.i += 2;
                        }
                        b'u' => {
                            let end = self.s[self.i..].iter().position(|&c| c == b'}').ok_or_else(|| self.err("bad \\u escape"))?;
                            let hex = std::str::from_utf8(&self.s[self.i..self.i + end]).unwrap_or("").trim_start_matches('{');
                            let ch =
                                u32::from_str_radix(hex, 16).ok().and_then(char::from_u32).ok_or_else(|| self.err("bad \\u escape"))?;
                            out.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes());
                            self.i += end + 1;
                        }
                        _ => return Err(self.err("unknown escape")),
                    }
                }
                c => out.push(c),
            }
        }
        Ok(Value::String(self.lua.create_string(&out).map_err(|e| e.to_string())?))
    }

    fn number(&mut self) -> Result<Value, String> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while let Some(c) = self.peek() {
            let sign_after_e = (c == b'-' || c == b'+') && matches!(self.s[self.i - 1], b'e' | b'E');
            if c.is_ascii_digit() || c == b'.' || c == b'e' || c == b'E' || sign_after_e {
                self.i += 1;
            } else {
                break;
            }
        }
        let text = std::str::from_utf8(&self.s[start..self.i]).unwrap();
        let float = text.contains(['.', 'e', 'E']);
        match (float, text.parse::<i64>(), text.parse::<f64>()) {
            (false, Ok(i), _) => Ok(Value::Integer(i)),
            (_, _, Ok(f)) if f.is_finite() => Ok(Value::Number(f)),
            _ => Err(self.err(&format!("bad number '{text}'"))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(lua: &Lua, src: &str) -> String {
        let v: Value = lua.load(src).eval().unwrap();
        let text = encode(&v).unwrap();
        let back = decode(lua, &text).unwrap_or_else(|e| panic!("{e}\n{text}"));
        // Encoding is canonical, so equal text means equal data.
        assert_eq!(encode(&back).unwrap(), text);
        text
    }

    #[test]
    fn values_survive_a_roundtrip() {
        let lua = Lua::new();
        let text = roundtrip(
            &lua,
            r#"{cash = 120, list = {1, 2.5, "three", false}, nested = {deep = {deeper = {}}},
                ["with space"] = 1, ["end"] = 2, [7] = "seven", [0.5] = "half", [true] = "yes",
                float = 0.1, tiny = -2.5e-8, big = 1e300, whole = 3.0, min = math.mininteger,
                text = "quote \" back \\ nl \n tab \t nul \0 bell \7 é 日本 9"}"#,
        );
        assert!(text.starts_with(HEADER));
        assert!(text.contains("cash = 120,") && text.contains("[\"end\"] = 2,") && text.contains("whole = 3.0,"));
        let v: Table = decode(&lua, &text).unwrap().as_table().unwrap().clone();
        assert_eq!(v.get::<f64>("float").unwrap(), 0.1);
        assert_eq!(v.get::<Value>("whole").unwrap(), Value::Number(3.0)); // stays a float
        assert_eq!(v.get::<Value>("cash").unwrap(), Value::Integer(120));
        assert_eq!(v.get::<String>("text").unwrap(), "quote \" back \\ nl \n tab \t nul \0 bell \x07 é 日本 9");
    }

    #[test]
    fn invalid_utf8_is_escaped() {
        let lua = Lua::new();
        let s = lua.create_string(b"a\xff\xfeb").unwrap();
        let text = encode(&Value::String(s)).unwrap();
        assert!(text.contains(r#""a\255\254b""#));
        assert_eq!(decode(&lua, &text).unwrap().as_string().unwrap().as_bytes().to_vec(), b"a\xff\xfeb");
    }

    #[test]
    fn handwritten_files_parse() {
        let lua = Lua::new();
        let src =
            "-- my edit\n--[[ block\ncomment ]] return { cash = 5000; missions = {'a', \"b\",}, [ 2 ] = -3, x = 1E3, u = '\\u{48}\\x49' }";
        let t = decode(&lua, src).unwrap().as_table().unwrap().clone();
        assert_eq!(t.get::<i64>("cash").unwrap(), 5000);
        assert_eq!(t.get::<Table>("missions").unwrap().get::<String>(2).unwrap(), "b");
        assert_eq!(t.get::<i64>(2).unwrap(), -3);
        assert_eq!(t.get::<f64>("x").unwrap(), 1000.0);
        assert_eq!(t.get::<String>("u").unwrap(), "HI");
    }

    #[test]
    fn code_and_garbage_are_rejected() {
        let lua = Lua::new();
        for bad in [
            "",
            "os.exit()",
            "{f = function() end}",
            "{a = 1} {b = 2}",
            "{a = 1",
            "{\"open}",
            "{x = 1 + 1}",
            "{[nil] = 1}",
            "{a = 0x10}",
            "{a = '\\q'}",
            &"{".repeat(200),
        ] {
            assert!(decode(&lua, bad).is_err(), "accepted {bad:?}");
        }
    }

    #[test]
    fn unsavable_values_are_refused() {
        let lua = Lua::new();
        for src in ["{f = print}", "{n = 0/0}", "{n = 1/0}", "(function() local t = {} t.self = t return t end)()"] {
            let v: Value = lua.load(src).eval().unwrap();
            assert!(encode(&v).is_err(), "encoded {src}");
        }
        let big: Value = lua.load("string.rep('x', 300 * 1024)").eval().unwrap();
        assert!(encode(&big).is_err());
    }

    #[test]
    fn keys_are_plain_file_names() {
        for ok in ["progress", "settings", "mod.taxi.best-fare", "slot_2"] {
            assert!(check_key(ok).is_ok(), "{ok}");
        }
        for bad in ["", ".hidden", "../x", "a/b", "a\\b", "c:x", "a..b", "con", "NUL.x", "com1", "lpt9", &"x".repeat(65), "space key"] {
            assert!(check_key(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn dir_store_writes_atomically_and_quarantines() {
        let dir = std::env::temp_dir().join(format!("auto-save-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Store::Dir(dir.clone());
        assert_eq!(s.read("progress").unwrap(), None);
        s.write("progress", Some("return 1\n")).unwrap();
        s.write("progress", Some("return 2\n")).unwrap();
        assert_eq!(s.read("progress").unwrap().as_deref(), Some("return 2\n"));
        assert_eq!(s.keys(), vec!["progress"]);
        assert!(s.quarantine("progress").unwrap().ends_with("progress.lua.bad"));
        assert_eq!(s.read("progress").unwrap(), None);
        s.write("gone", Some("1")).unwrap();
        s.write("gone", None).unwrap();
        s.write("gone", None).unwrap(); // deleting twice is fine
        assert!(s.keys().is_empty());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
