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

## Not yet

- Sound (WebAudio), gamepads (the Gamepad API), and saves (localStorage). Saves last until the
  page closes.
- Touch controls.
- Memory: wasm memory grows to its peak and stays there. Peaks are about 24 MB for the starter
  map, 740 MB for Raisio and 890 MB for Turku. That is fine on a desktop but too much for an
  iPhone, so a lighter mobile profile is next.
