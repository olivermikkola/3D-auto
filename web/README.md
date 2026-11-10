# Browser map example

This builds the Rust engine and the fictional map in `game/` into a WebAssembly
module. No external map data is fetched. The source is shared with the native
binary through `web/Cargo.toml`.

Install the `wasm32-unknown-unknown` Rust target and
[wasi-sdk 34](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-34).
Set `WASI_SDK_PATH` to the extracted SDK folder, then run:

```sh
web/build.sh
python3 -m http.server 8000 --directory web/dist
```

Open http://localhost:8000 in a browser with WebGL 2. Drag on touch screens to
orbit; + / - zoom. Keyboard controls match the native example. The manifest and
service worker allow installation; a WASM hash changes the cache each build.

CI builds the module, renders it in headless Chromium, exercises controls and
uploads a screenshot. The Pages workflow publishes the example after a main
branch update. Existing historical releases are unaffected by this build.
