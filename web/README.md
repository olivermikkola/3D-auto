# The game in a browser

`web/` builds the same engine (`../src/main.rs`) for `wasm32-unknown-unknown`, miniquad's web
target, with the whole `game/` folder packed into the module. The page is `index.html`, plus
miniquad's own `gl.js` loader. The result is a static folder (`dist/`) that any web host can serve.

```sh
WASI_SDK_PATH=~/tools/wasi-sdk-34.0-x86_64-linux web/build.sh   # -> web/dist
python3 tools/web_check.py --query "map=raisio" --wait 40 --shot /tmp/web.png
```

The page's address sets the game's environment: `index.html?map=raisio&hour=22` is
`MAP=raisio HOUR=22`. `?log=1` keeps the log box on screen.

## What it needs

- The Rust target: `rustup target add wasm32-unknown-unknown`.
- [wasi-sdk](https://github.com/WebAssembly/wasi-sdk/releases), for compiling Lua (C) to wasm
  against wasi-libc. Point `WASI_SDK_PATH` at it.
- For `tools/web_check.py`: Firefox and [geckodriver](https://github.com/mozilla/geckodriver/releases).

## How it works

- **Lua.** mlua builds Lua for wasm only through emscripten, which miniquad doesn't support. So
  `web/lua-src` is a patched copy of the Lua source crate that compiles Lua with wasi-sdk's clang.
  Lua's errors (setjmp/longjmp) become wasm exceptions in the legacy encoding, which Safari has
  supported since iOS 15.2. Only this crate uses the copy.
- **System calls.** wasi-libc's system calls are defined in `src/web.rs`, inside the module, so
  the page has nothing extra to provide. Files open read-only from the pack, the environment
  comes from the address, and print goes to the browser console and the page's log box. The
  Rust side reads the same pack through `src/vfs.rs`.
- **Graphics.** WebGL 2. The shaders were already GLSL 100.

## Measuring without mixing metrics

Use a fresh build and keep the map, seed, hour, viewport and browser version fixed:

```sh
python3 tools/web_check.py --query 'map=raisio&seed=1337&hour=12' --wait 40 \
  --report baseline/raisio.json --shot baseline/raisio.png
```

Repeat for `starter` and `turku`, sequentially. The JSON retains timestamped
samples, page logs, browser version and the largest observed wasm allocation.
The command fails if the game never logs its map/seed or the sampled log contains
a runtime error/panic. Missing build files fail before a driver is started.
`--firefox /path/to/firefox` selects a binary explicitly when needed.

Values are bytes (console display: **MiB**), not total browser RSS, GPU memory or
JavaScript heap. Samples start after WebDriver navigation returns; this does not
capture the complete startup timeline. Wasm allocation does not shrink when Lua
or Rust frees memory. This checker does not measure rendered FPS or prove visual
correctness. Capture Chrome DevTools traces and inspect screenshots separately.
Readiness here means the map/seed initialization marker, not an independently
verified playable frame. Keep generated reports/screenshots outside version control.

For a separate native CPU baseline, build `cargo build --release` first, then:

```sh
MAP=raisio SEED=1337 MESH_REPORT=1 /usr/bin/time -v target/release/auto game --headless 15
```

`MESH_REPORT` uses decimal MB; Linux `/usr/bin/time -v` maximum RSS is KiB.
Headless mode does not exercise GPU uploads or rendered frame pacing.

## Not yet

- Sound (WebAudio), gamepads (the Gamepad API), and saves (localStorage). Saves last until the
  page closes.
- Touch controls.
- Memory: wasm memory grows to its peak and stays there. Peaks are about 24 MB for the starter
  map, 740 MB for Raisio and 890 MB for Turku. That is fine on a desktop but too much for an
  iPhone, so a lighter mobile profile is next.
